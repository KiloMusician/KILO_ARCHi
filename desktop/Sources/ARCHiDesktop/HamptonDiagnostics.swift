import Foundation

/// Explicit acceptance checks. Only authored synthetic questions enter local models.
@MainActor
enum HamptonDiagnostics {
    static func run(cancel: Bool = false) async -> Bool {
        let reasoner = HamptonDiagnosticRoleClient(model: QwenAssistant.defaultModel)
        let selector = HamptonDiagnosticRoleClient(model: HamptonReasonsAssistant.defaultContextModel)
        let client = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
        var report: [String: JSONValue] = [
            "schema": .string("archi-native-hampton-check/v1"),
            "mode": .string(cancel ? "local-cancellation" : "local-context-follow-up"),
            "startedAt": .string(ISO8601DateFormatter().string(from: Date())),
            "privateSourceUsed": .bool(false), "passed": .bool(false)
        ]
        let start = ContinuousClock.now
        do {
            try await client.connect()
            if cancel {
                var emitted = false, completed = false, interrupted = false
                let task = Task { @MainActor in
                    do {
                        try await client.reply(to: request("Explain how a desktop companion can check its location before showing a highlight. Use several sentences.")) { _ in emitted = true }
                        completed = true
                    } catch { interrupted = true }
                }
                try await Task.sleep(for: .milliseconds(750))
                client.disconnect()
                await task.value
                report["cancelledBeforeAcceptedAnswer"] = .bool(interrupted && !emitted && !completed)
                report["contextRecords"] = .number(Double(client.snapshot.records.count))
                report["passed"] = .bool(interrupted && !emitted && !completed && client.snapshot.records.isEmpty)
            } else {
                var steps: [JSONValue] = []
                let source = "Option A: Rehearsal is Monday at 09:00 in Oak.\nOption B: Rehearsal is Friday at 15:30 in Cedar."
                let selection = DocumentSelection(range: (source as NSString).range(of: "Option B: Rehearsal is Friday at 15:30 in Cedar."), text: source, sourceRevision: 1)!
                let selected = AssistantRequest(prompt: "What are the rehearsal day, exact 24-hour time, and room in the selected passage?", sourceName: "synthetic-selection.txt", sourceText: source,
                    sourceRevision: 1, placementRevision: 1, tone: "Direct", replyLength: 0.2, selection: selection)
                let answer = try await turn(client, selected)
                let selectedPassed = ["Friday", "15:30", "Cedar"].allSatisfy(answer.contains)
                    && !["Monday", "09:00", "Oak"].contains(where: answer.contains)
                    && client.snapshot.receipts.map(\.role) == [.reasoning]
                    && client.snapshot.proposal?.sourceIDs.contains("selected-passage") == true
                steps.append(step("selected-passage-context-off", client, answer: answer, passed: selectedPassed))
                report["steps"] = .array(steps)

                client.setContextEnabled(true)
                let first = try await turn(client, request("For this session, our project codename is Juniper. Please acknowledge the codename in one sentence."))
                let firstIDs = Set(client.snapshot.records.filter { $0.text.contains("Juniper") }.map(\.id))
                let firstPassed = first.contains("Juniper") && !firstIDs.isEmpty
                    && client.snapshot.receipts.map(\.role) == [.memorySelection, .reasoning]
                steps.append(step("retain-exact-user-excerpt", client, answer: first, passed: firstPassed))
                report["steps"] = .array(steps)
                let followup = try await turn(client, request("What is our project codename?"))
                let used = Set(client.snapshot.proposal?.memoryIDs ?? [])
                let followupPassed = followup.contains("Juniper") && !used.intersection(firstIDs).isEmpty
                    && client.snapshot.receipts.map(\.role) == [.memorySelection, .memoryReminder, .reasoning]
                steps.append(step("follow-up-with-approved-context", client, answer: followup, passed: followupPassed))
                report["steps"] = .array(steps)
                client.clearSessionContext()
                let cleared = client.snapshot.records.isEmpty
                client.setContextEnabled(false)
                let missing = try await turn(client, request("What is our project codename? If it has not been supplied, ask me for it instead of guessing."))
                let missingPassed = cleared && !missing.contains("Juniper")
                    && client.snapshot.proposal?.kind != .answer
                    && client.snapshot.proposal?.memoryIDs.isEmpty == true
                    && client.snapshot.receipts.map(\.role) == [.reasoning]
                steps.append(step("clear-context-then-missing-information", client, answer: missing, passed: missingPassed))
                report["steps"] = .array(steps)
                report["passed"] = .bool(selectedPassed && firstPassed && followupPassed && missingPassed)
            }
        } catch {
            report["error"] = .string((error as? LocalizedError)?.errorDescription ?? String(describing: error))
            report["phase"] = .string(client.snapshot.phase)
            report["receipts"] = receipts(client.snapshot.receipts)
            report["attemptedInvocations"] = .array(client.snapshot.attemptedInvocations.map { .string($0.rawValue) })
            report["elapsedMilliseconds"] = .number(Double(client.snapshot.elapsedMilliseconds))
            report["lastReasonRole"] = reasoner.diagnostic
            report["lastContextRole"] = selector.diagnostic
        }
        await client.shutdown()
        report["sessionClearedOnShutdown"] = .bool(client.snapshot.records.isEmpty)
        let elapsed = start.duration(to: .now)
        report["elapsedSeconds"] = .number(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let data = try? encoder.encode(JSONValue.object(report)) { print(String(decoding: data, as: UTF8.self)) }
        return report["passed"]?.bool == true
    }

    private static func request(_ question: String) -> AssistantRequest {
        AssistantRequest(prompt: question, sourceName: nil, sourceText: "", sourceRevision: 0, placementRevision: 1,
            tone: "Direct", replyLength: 0.2)
    }
    private static func turn(_ client: HamptonReasonsAssistant, _ request: AssistantRequest) async throws -> String {
        var answer = ""
        try await client.reply(to: request) { if case .text(let text) = $0 { answer = text } }
        return answer
    }
    private static func step(_ name: String, _ client: HamptonReasonsAssistant, answer: String, passed: Bool) -> JSONValue {
        .object(["name": .string(name), "passed": .bool(passed), "answer": .string(answer),
            "kind": .string(client.snapshot.proposal?.kind.rawValue ?? "NONE"),
            "sourceIDs": .array((client.snapshot.proposal?.sourceIDs ?? []).map(JSONValue.string)),
            "memoryIDs": .array((client.snapshot.proposal?.memoryIDs ?? []).map(JSONValue.string)),
            "contextRecords": .number(Double(client.snapshot.records.count)), "receipts": receipts(client.snapshot.receipts),
            "attemptedInvocations": .array(client.snapshot.attemptedInvocations.map { .string($0.rawValue) }),
            "elapsedMilliseconds": .number(Double(client.snapshot.elapsedMilliseconds))])
    }
    private static func receipts(_ items: [HamptonRoleReceipt]) -> JSONValue {
        .array(items.map { .object(["role": .string($0.role.rawValue), "model": .string($0.model.name),
            "modelDigest": .string($0.model.digest), "elapsedMilliseconds": .number(Double($0.elapsedMilliseconds)),
            "requestID": .string($0.id), "inputDigest": .string($0.inputDigest), "outputDigest": .string($0.outputDigest),
            "systemDigest": .string($0.systemDigest), "schemaDigest": .string($0.schemaDigest),
            "policyVersion": .string($0.policyVersion), "temperature": .number(HamptonInvocationPolicy.temperature),
            "contextTokens": .number(Double(HamptonInvocationPolicy.contextTokens)),
            "outputTokens": .number(Double(HamptonInvocationPolicy.outputTokens))]) })
    }
}

/// Raw final JSON is retained only by this explicitly invoked synthetic diagnostic.
@MainActor
private final class HamptonDiagnosticRoleClient: LocalRoleClient {
    private let client: QwenAssistant
    private var lastRequest: LocalRoleRequest?
    private var lastResult: LocalRoleResult?
    init(model: String) { client = QwenAssistant(model: model) }
    func connect() async throws { try await client.connect() }
    func disconnect() { client.disconnect() }
    func shutdown() async { await client.shutdown() }
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        lastRequest = request; lastResult = nil
        let result = try await client.generate(request)
        lastResult = result
        return result
    }
    var diagnostic: JSONValue {
        guard let request = lastRequest, let result = lastResult else { return .null }
        var issue = "VALID"
        func ids(_ key: String) -> Set<String> { Set(request.input[key]?.array?.compactMap { $0["id"]?.string } ?? []) }
        do {
            switch request.role {
            case .memorySelection: _ = try HamptonProposalValidator.parseSelection(result, request: request, allowedCandidateIDs: ids("candidates"))
            case .memoryReminder: _ = try HamptonProposalValidator.parseReminder(result, request: request, allowedMemoryIDs: ids("memories"))
            case .reasoning: _ = try HamptonProposalValidator.parseReason(result, request: request, allowedSourceIDs: ids("sources"), allowedMemoryIDs: ids("memories"))
            }
        } catch { issue = String(describing: error) }
        return .object(["requestID": .string(request.id), "role": .string(request.role.rawValue),
            "validation": .string(issue), "rawFinalJSON": .string(result.text)])
    }
}
