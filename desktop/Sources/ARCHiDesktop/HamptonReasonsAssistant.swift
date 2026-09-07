import Foundation
import CryptoKit

struct HamptonRoleReceipt: Identifiable, Equatable, Sendable {
    let id: String
    let role: LocalModelRole
    let model: QwenModelMetadata
    let elapsedMilliseconds: Int
    let inputDigest: String
    let outputDigest: String
    let systemDigest: String
    let schemaDigest: String
    let policyVersion = HamptonInvocationPolicy.version
}

struct HamptonAssistantSnapshot: Equatable, Sendable {
    var records: [SessionContextRecord] = []
    var proposal: HamptonReasonProposal?
    var receipts: [HamptonRoleReceipt] = []
    var attemptedInvocations: [LocalModelRole] = []
    var elapsedMilliseconds = 0
    var phase = "Ready for a local question"
    var turn = 0
}

enum HamptonAssistantFailure: Error, LocalizedError {
    case invalidProposal, timedOut, contextLimit
    var errorDescription: String? {
        switch self {
        case .invalidProposal: "The local model returned a proposal that did not pass the response checks. No answer or new session context was accepted."
        case .timedOut: "The local workflow reached its three-minute limit. No answer or new session context was accepted."
        case .contextLimit: "The local workflow exceeds its request budget. Use a shorter question or shared copy. No answer or new session context was accepted."
        }
    }
}

/// A native adaptation of Hampton's memory-selector / Reasons separation.
/// Model output is proposed text or IDs. This owner alone admits a completed
/// answer and a tentative in-memory bank; it has no action or durable-write port.
@MainActor
final class HamptonReasonsAssistant: AssistantClient {
    static let defaultContextModel = "qwen3:8b"
    private(set) var snapshot = HamptonAssistantSnapshot()
    var inFlightInvocations: [LocalModelRole]? { operation == nil ? nil : snapshot.attemptedInvocations }
    var onSnapshot: (@MainActor (HamptonAssistantSnapshot) -> Void)?
    private(set) var contextEnabled: Bool
    private(set) var contextModel: String
    private let reasoner: any LocalRoleClient
    private var selector: any LocalRoleClient
    private var bank = HamptonSessionContext()
    private var connected = false
    private var selectorConnected = false
    private var disposed = false
    private var generation: UInt64 = 0
    private var operation: UUID?
    private var operationStarted: ContinuousClock.Instant?
    private var retirements: [UUID: Task<Void, Never>] = [:]

    init(model: String = QwenAssistant.defaultModel, contextModel: String = defaultContextModel,
         reasoner: (any LocalRoleClient)? = nil, contextSelector: (any LocalRoleClient)? = nil,
         contextEnabled: Bool = false) {
        self.reasoner = reasoner ?? QwenAssistant(model: model)
        self.selector = contextSelector ?? QwenAssistant(model: contextModel)
        self.contextModel = contextModel
        self.contextEnabled = contextEnabled
    }

    func connect() async throws {
        guard !disposed else { throw QwenFailure.stopped }
        disconnect()
        let owner = generation
        try await reasoner.connect()
        try require(owner)
        connected = true
    }

    func setContextEnabled(_ enabled: Bool) {
        guard !disposed, enabled != contextEnabled else { return }
        if operation != nil { disconnect() }
        contextEnabled = enabled
        clearSessionContext()
    }

    func setContextModel(_ model: String) {
        guard !disposed, QwenAssistant.supportedModels.contains(model), model != contextModel else { return }
        disconnect()
        let previous = selector
        selector = QwenAssistant(model: model)
        contextModel = model
        clearSessionContext()
        let id = UUID()
        retirements[id] = Task { [weak self, previous] in
            await previous.shutdown()
            self?.retirements[id] = nil
        }
    }

    func clearSessionContext() {
        if operation != nil { disconnect() }
        bank.clear()
        snapshot = HamptonAssistantSnapshot(attemptedInvocations: snapshot.attemptedInvocations,
            elapsedMilliseconds: snapshot.elapsedMilliseconds, phase: "Session context cleared")
        publish()
    }

    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        guard !disposed, connected else { throw QwenFailure.unavailable }
        guard operation == nil else { throw QwenFailure.busy }
        guard request.hasValidSelection, request.hasValidRevisionTarget else { throw QwenFailure.invalidResponse }
        guard request.hasValidLocalLessons else { throw QwenFailure.invalidResponse }
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.prompt.utf8.count <= 16_000, request.sourceText.utf8.count <= 100_000 else {
            throw HamptonAssistantFailure.contextLimit
        }
        let id = UUID(), owner = generation, started = ContinuousClock.now
        let deadline = started.advanced(by: .seconds(180))
        operation = id
        operationStarted = started
        snapshot.proposal = nil; snapshot.receipts = []
        snapshot.attemptedInvocations = []; snapshot.elapsedMilliseconds = 0
        let timeout = Task { [weak self] in
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            guard let self, self.generation == owner, self.operation == id else { return }
            self.disconnect()
            self.snapshot.phase = "Local workflow timed out"; self.publish()
        }
        defer {
            timeout.cancel()
            if generation == owner, operation == id { operation = nil; operationStarted = nil }
        }
        var tentative = bank
        var receipts: [HamptonRoleReceipt] = []
        do {
            let current = try JSONDecoder().decode(JSONValue.self, from: Data(request.input.utf8))
            let sourceIDs = request.sourceIDs
            let sources = sourceIDs.map { JSONValue.object(["id": .string($0), "label": .string($0)]) }
            let lessonInputs = request.localLessons.map(\.modelInput)
            let lessonIDs = request.localLessons.map(\.modelID)
            var reminders: [SessionContextRecord] = []
            // Keep the complete current source and user-confirmed lesson snapshot
            // within the reasoning budget before any optional inference occurs.
            _ = try makeRequest(.reasoning, fields: ["context": current, "sources": .array(sources),
                "memories": .array(lessonInputs)], sourceIDs: sourceIDs, memoryIDs: lessonIDs, revisionTarget: request.revisionTarget)
            if contextEnabled {
                let allCandidates = tentative.beginTurn(request: request)
                if let selectionRequest = try boundedRequest(.memorySelection, question: request.prompt,
                    values: allCandidates.map(Self.candidateInput), key: "candidates") {
                    let offeredCandidates = Set(selectionRequest.input["candidates"]!.array!.compactMap { $0["id"]?.string })
                    setPhase("Choosing temporary context…")
                    try await connectSelector(owner, operation: id)
                    try beginInvocation(.memorySelection, owner: owner, operation: id)
                    let selection = try await selector.generate(selectionRequest)
                    try require(owner, operation: id)
                    let selected = try HamptonProposalValidator.parseSelection(selection, request: selectionRequest,
                        allowedCandidateIDs: offeredCandidates)
                    try tentative.retain(candidateIDs: selected, candidates: allCandidates)
                    receipts.append(try Self.receipt(selection, request: selectionRequest))
                    snapshot.receipts = receipts
                }

                let eligible = tentative.eligibleReminders(for: request)
                if let reminderRequest = try boundedRequest(.memoryReminder, question: request.prompt,
                    values: eligible.map(Self.recordInput), key: "memories") {
                    let offeredMemories = Set(reminderRequest.input["memories"]!.array!.compactMap { $0["id"]?.string })
                    setPhase("Finding useful earlier context…")
                    try await connectSelector(owner, operation: id)
                    try beginInvocation(.memoryReminder, owner: owner, operation: id)
                    let reminder = try await selector.generate(reminderRequest)
                    try require(owner, operation: id)
                    let ids = try HamptonProposalValidator.parseReminder(reminder, request: reminderRequest,
                        allowedMemoryIDs: offeredMemories)
                    reminders = try tentative.useReminderIDs(ids, eligible: eligible)
                    receipts.append(try Self.receipt(reminder, request: reminderRequest))
                    snapshot.receipts = receipts
                }
            }
            let memoryIDs = lessonIDs + reminders.map(\.id)
            let reasonRequest = try makeRequest(.reasoning, fields: ["context": current, "sources": .array(sources),
                "memories": .array(lessonInputs + reminders.map(Self.recordInput))], sourceIDs: sourceIDs, memoryIDs: memoryIDs,
                revisionTarget: request.revisionTarget)
            setPhase(request.revisionTarget == nil ? "Preparing an answer from the supplied context…" : "Preparing a passage revision for review…")
            try beginInvocation(.reasoning, owner: owner, operation: id)
            let result = try await reasoner.generate(reasonRequest)
            try require(owner, operation: id)
            let proposal: HamptonReasonProposal?
            let revision: PassageRevisionProposal?
            if let target = request.revisionTarget {
                guard result.role == .reasoning else { throw HamptonProposalValidationError.wrongRole }
                guard result.requestID.utf8.elementsEqual(reasonRequest.id.utf8) else { throw HamptonProposalValidationError.wrongRequest }
                revision = try PassageRevisionValidator.parse(result.text, target: target, sourceIDs: sourceIDs, memoryIDs: memoryIDs)
                proposal = nil
            } else {
                proposal = try HamptonProposalValidator.parseReason(result, request: reasonRequest,
                    allowedSourceIDs: Set(sourceIDs), allowedMemoryIDs: Set(memoryIDs))
                revision = nil
            }
            receipts.append(try Self.receipt(result, request: reasonRequest))
            try require(owner, operation: id)
            // No suspension between the final ownership check and state publication.
            if contextEnabled { bank = tentative }
            updateElapsed()
            snapshot = HamptonAssistantSnapshot(records: bank.records, proposal: proposal,
                receipts: receipts, attemptedInvocations: snapshot.attemptedInvocations,
                elapsedMilliseconds: snapshot.elapsedMilliseconds, phase: "Response checks passed", turn: bank.turn)
            publish()
            try require(owner, operation: id)
            if let revision { onEvent(.revision(revision)) }
            else if let proposal { onEvent(.text(proposal.answer)) }
        } catch {
            if generation == owner, operation == id {
                snapshot.proposal = nil; snapshot.receipts = receipts
                updateElapsed()
                snapshot.phase = "No new answer or context accepted"; publish()
            }
            if ContinuousClock.now >= deadline { throw HamptonAssistantFailure.timedOut }
            if error is HamptonProposalValidationError || error is SessionContextError {
                throw HamptonAssistantFailure.invalidProposal
            }
            if (error as? QwenFailure) == .contextLimit { throw HamptonAssistantFailure.contextLimit }
            throw error
        }
    }

    func disconnect() {
        updateElapsed()
        operationStarted = nil
        generation &+= 1; operation = nil; connected = false; selectorConnected = false
        reasoner.disconnect(); selector.disconnect()
        snapshot.proposal = nil; snapshot.phase = "Disconnected"; publish()
    }

    func shutdown() async {
        disposed = true
        disconnect(); clearSessionContext()
        await reasoner.shutdown(); await selector.shutdown()
        for retirement in Array(retirements.values) { await retirement.value }
    }

    private func require(_ owner: UInt64, operation id: UUID? = nil) throws {
        guard !disposed, owner == generation, !Task.isCancelled,
              id == nil || operation == id else { throw QwenFailure.stopped }
    }

    private func connectSelector(_ owner: UInt64, operation id: UUID) async throws {
        try require(owner, operation: id)
        if !selectorConnected {
            try await selector.connect()
            try require(owner, operation: id)
            selectorConnected = true
        }
    }

    private func beginInvocation(_ role: LocalModelRole, owner: UInt64, operation id: UUID) throws {
        try require(owner, operation: id)
        snapshot.attemptedInvocations.append(role)
        updateElapsed()
        // No observer callback between counting this invocation and entering the
        // transport. Phase/final publications and stop capture expose the count.
    }

    private func updateElapsed() {
        guard let operationStarted else { return }
        let components = operationStarted.duration(to: .now).components
        snapshot.elapsedMilliseconds = max(0, Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000))
    }

    private func setPhase(_ phase: String) { updateElapsed(); snapshot.phase = phase; publish() }
    private func publish() { onSnapshot?(snapshot) }

    private func boundedRequest(_ role: LocalModelRole, question: String, values: [JSONValue], key: String) throws -> LocalRoleRequest? {
        var offered = values
        while !offered.isEmpty {
            let ids = offered.compactMap { $0["id"]?.string }
            do {
                return try makeRequest(role, fields: ["question": .string(question), key: .array(offered)],
                    memoryIDs: role == .memoryReminder ? ids : [], candidateIDs: role == .memorySelection ? ids : [])
            } catch HamptonAssistantFailure.contextLimit {
                offered.removeLast()
            }
        }
        // No optional inference or selector connection when budgeting leaves no IDs.
        return nil
    }

    private func makeRequest(_ role: LocalModelRole, fields: [String: JSONValue], sourceIDs: [String] = [],
                             memoryIDs: [String] = [], candidateIDs: [String] = [],
                             revisionTarget: RevisionTarget? = nil) throws -> LocalRoleRequest {
        let id = UUID().uuidString
        let schema = revisionTarget.map { PassageRevisionValidator.schema(target: $0, sourceIDs: sourceIDs, memoryIDs: memoryIDs) }
            ?? HamptonProposalValidator.schema(for: role, requestID: id,
                sourceIDs: sourceIDs, memoryIDs: memoryIDs, candidateIDs: candidateIDs)
        var input = fields
        input["requestID"] = .string(id)
        input["outputSchema"] = schema
        let request = LocalRoleRequest(id: id, role: role, input: .object(input), outputSchema: schema,
            systemInstructionOverride: revisionTarget == nil ? nil : AssistantInstructions.passageRevisionText + "\n" + LocalLessonGuidance.text)
        // Conservative encoded envelope preflight, including JSON-in-message escaping.
        // Transport independently enforces its exact 24 KB /api/chat body bound.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(request.input), as: UTF8.self)
        let envelope: JSONValue = .object(["system": .string(request.systemInstruction), "input": .string(text), "format": schema])
        guard try encoder.encode(envelope).count <= 22_000 else { throw HamptonAssistantFailure.contextLimit }
        return request
    }

    private static func candidateInput(_ record: SessionContextCandidate) -> JSONValue {
        .object(["id": .string(record.id), "text": .string(record.text), "kind": .string(record.kind.rawValue),
                 "sourceID": .string(record.sourceID)])
    }

    private static func recordInput(_ record: SessionContextRecord) -> JSONValue {
        .object(["id": .string(record.id), "text": .string(record.text), "kind": .string(record.kind.rawValue),
                 "sourceID": .string(record.sourceID)])
    }

    private static func receipt(_ result: LocalRoleResult, request: LocalRoleRequest) throws -> HamptonRoleReceipt {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return HamptonRoleReceipt(id: request.id, role: request.role, model: result.model,
            elapsedMilliseconds: result.elapsedMilliseconds, inputDigest: digest(try encoder.encode(request.input)),
            outputDigest: digest(Data(result.text.utf8)), systemDigest: digest(Data(request.systemInstruction.utf8)),
            schemaDigest: digest(try encoder.encode(request.outputSchema)))
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
