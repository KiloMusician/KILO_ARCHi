import Foundation
import Testing
@testable import ARCHiDesktop

@MainActor
struct HamptonReasonsAssistantTests {
    @Test func revisionUsesOneReasoningInvocationAndEmitsTypedValidatedProposal() async throws {
        let fixture = CoordinatorFixture(contextEnabled: false)
        defer { fixture.cleanUp() }
        fixture.reasoner.response = { try revisionRoleResult($0, model: $1) }
        let request = try makeRevisionRequest()
        try await fixture.assistant.connect()
        let events = CoordinatorEvents()
        try await fixture.assistant.reply(to: request, onEvent: events.receive)
        #expect(fixture.trace.roles == [.reasoning])
        #expect(fixture.selector.connectCount == 0)
        #expect(events.texts.isEmpty)
        #expect(events.revisions.count == 1)
        #expect(events.revisions.first?.target == request.revisionTarget)
        #expect(events.revisions.first?.memoryIDs == request.localLessons.map(\.modelID))
        let sent = try #require(fixture.reasoner.requests.first)
        #expect(sent.outputSchema == PassageRevisionValidator.schema(target: try #require(request.revisionTarget),
            sourceIDs: request.sourceIDs, memoryIDs: request.localLessons.map(\.modelID)))
        #expect(sent.input["context"] == (try JSONDecoder().decode(JSONValue.self, from: Data(request.input.utf8))))
        #expect(sent.systemInstruction.contains(AssistantInstructions.passageRevisionText))
        #expect(sent.systemInstruction.contains(LocalLessonGuidance.text))
        #expect(!sent.systemInstruction.contains("Keep answer under 1200"))
        #expect(fixture.assistant.snapshot.proposal == nil)
        #expect(fixture.assistant.snapshot.records.isEmpty)
        #expect(fixture.assistant.snapshot.receipts.map(\.role) == [.reasoning])
        #expect(fixture.assistant.snapshot.attemptedInvocations == [.reasoning])
        #expect(fixture.assistant.snapshot.receipts.first?.policyVersion == "native-hampton/v4")
    }

    @Test func revisionValidationFailureDoesNotCommitTentativeContext() async throws {
        let fixture = CoordinatorFixture(contextEnabled: true)
        defer { fixture.cleanUp() }
        fixture.reasoner.response = { request, model in
            LocalRoleResult(requestID: request.id, role: request.role, text: "{invalid}", model: model, elapsedMilliseconds: 7)
        }
        try await fixture.assistant.connect()
        let events = CoordinatorEvents()
        await #expect(throws: HamptonAssistantFailure.self) {
            try await fixture.assistant.reply(to: try makeRevisionRequest(), onEvent: events.receive)
        }
        #expect(fixture.trace.roles == [.memorySelection, .reasoning])
        #expect(events.texts.isEmpty && events.revisions.isEmpty)
        #expect(fixture.assistant.snapshot.records.isEmpty)
        #expect(fixture.assistant.snapshot.turn == 0)
        #expect(fixture.assistant.snapshot.proposal == nil)
    }

    @Test func cancelledRevisionRejectsLateValidResultAndTentativeContext() async throws {
        let fixture = CoordinatorFixture(contextEnabled: true)
        defer { fixture.cleanUp() }
        fixture.reasoner.response = { try revisionRoleResult($0, model: $1) }
        fixture.reasoner.shouldPause = { _ in true }
        try await fixture.assistant.connect()
        let request = try makeRevisionRequest(), events = CoordinatorEvents()
        let task = Task { try await fixture.assistant.reply(to: request, onEvent: events.receive) }
        defer { task.cancel() }
        try await eventually { fixture.reasoner.pendingGenerationCount == 1 }
        fixture.assistant.disconnect()
        let after = fixture.assistant.snapshot
        try fixture.reasoner.resolveFirstGeneration()
        await expectStopped(task)
        #expect(fixture.assistant.snapshot == after)
        #expect(after.records.isEmpty)
        #expect(events.texts.isEmpty && events.revisions.isEmpty)
    }

    @Test func mismatchedRevisionTargetNeverInvokesAnyLocalRole() async throws {
        let fixture = CoordinatorFixture(contextEnabled: true)
        defer { fixture.cleanUp() }
        try await fixture.assistant.connect()
        let request = try makeRevisionRequest()
        let mismatched = AssistantRequest(prompt: request.prompt, sourceName: request.sourceName,
            sourceText: request.sourceText + " Changed.", sourceRevision: request.sourceRevision,
            placementRevision: request.placementRevision, settings: request.settings,
            selection: request.selection, revisionTarget: request.revisionTarget)
        #expect(mismatched.hasValidSelection)
        #expect(!mismatched.hasValidRevisionTarget)
        await #expect(throws: QwenFailure.invalidResponse) {
            try await fixture.assistant.reply(to: mismatched) { _ in Issue.record("A stale target published") }
        }
        #expect(fixture.trace.roles.isEmpty)
    }

    @Test func connectionPerformsMetadataWorkWithoutGeneratingOrConnectingUnusedSelector() async throws {
        let fixture = CoordinatorFixture(contextEnabled: true)
        defer { fixture.cleanUp() }
        #expect(fixture.reasoner.connectCount == 0)
        try await fixture.assistant.connect()
        #expect(fixture.reasoner.connectCount == 1)
        #expect(fixture.selector.connectCount == 0)
        #expect(fixture.trace.roles.isEmpty)
        #expect(fixture.assistant.snapshot.records.isEmpty)
        #expect(fixture.assistant.snapshot.proposal == nil)
    }

    @Test func disabledContextUsesOnlyReasoningAndPreservesExactCurrentInput() async throws {
        let fixture = CoordinatorFixture(contextEnabled: false)
        defer { fixture.cleanUp() }
        try await fixture.assistant.connect()
        let request = makeRequest("Explain this copy.", text: "Deadline Friday.", selection: true)
        let events = CoordinatorEvents()
        try await fixture.assistant.reply(to: request, onEvent: events.receive)

        #expect(fixture.trace.roles == [.reasoning])
        #expect(fixture.selector.connectCount == 0)
        #expect(fixture.selector.requests.isEmpty)
        let reasoning = try #require(fixture.reasoner.requests.first)
        let current = try JSONDecoder().decode(JSONValue.self, from: Data(request.input.utf8))
        #expect(reasoning.input["context"] == current)
        #expect(reasoning.input["requestID"] == .string(reasoning.id))
        #expect(ids(reasoning, "sources") == ["current-question", "shared-copy", "selected-passage"])
        #expect(ids(reasoning, "memories").isEmpty)
        #expect(events.texts == ["Accepted local answer."])
        #expect(fixture.assistant.snapshot.receipts.map(\.role) == [.reasoning])
        #expect(fixture.assistant.snapshot.attemptedInvocations == [.reasoning])
        #expect(fixture.assistant.snapshot.records.isEmpty)
        #expect(fixture.assistant.snapshot.turn == 0)
    }

    @Test func enabledRolesAreSequentialAndOnlyEarlierEligibleReferencesReachReasoning() async throws {
        let fixture = CoordinatorFixture(contextEnabled: true)
        defer { fixture.cleanUp() }
        try await fixture.assistant.connect()
        let first = makeRequest("Keep replies brief.", text: "Deadline Friday.", selection: true)
        try await fixture.assistant.reply(to: first, onEvent: { _ in })

        #expect(fixture.trace.roles == [.memorySelection, .reasoning])
        #expect(fixture.selector.connectCount == 1)
        let retained = try #require(fixture.assistant.snapshot.records.first)
        #expect(retained.text == first.prompt)
        #expect(retained.kind == .userQuestion)
        #expect(fixture.assistant.snapshot.records.count == 1)
        #expect(fixture.selector.requests.map(\.role) == [.memorySelection],
                "A newly retained span is already visible, so there is no reminder invocation.")
        #expect(fixture.assistant.snapshot.attemptedInvocations == [.memorySelection, .reasoning])
        #expect(ids(fixture.reasoner.requests[0], "memories").isEmpty)
        #expect(ids(fixture.reasoner.requests[0], "sources") == ["current-question", "shared-copy", "selected-passage"])

        let second = makeRequest("What earlier constraint should guide this answer?")
        try await fixture.assistant.reply(to: second, onEvent: { _ in })
        #expect(fixture.trace.roles == [.memorySelection, .reasoning,
                                       .memorySelection, .memoryReminder, .reasoning])
        #expect(fixture.selector.connectCount == 1)
        let reminder = fixture.selector.requests[2]
        let reasoning = fixture.reasoner.requests[1]
        #expect(ids(reminder, "memories") == [retained.id])
        #expect(reminder.input["memories"]?.array?.first?["text"] == .string(first.prompt))
        #expect(ids(reasoning, "memories") == [retained.id])
        #expect(reasoning.input["memories"] == reminder.input["memories"])
        #expect(fixture.assistant.snapshot.proposal?.memoryIDs == [retained.id])
        #expect(fixture.assistant.snapshot.records.first?.lastReminderTurn == 2)
        #expect(fixture.assistant.snapshot.turn == 2)
        #expect(!fixture.assistant.snapshot.records.contains { $0.text == "Accepted local answer." })

        let receipts = fixture.assistant.snapshot.receipts
        #expect(receipts.map(\.role) == [.memorySelection, .memoryReminder, .reasoning])
        #expect(receipts.map(\.id) == [fixture.selector.requests[1].id, reminder.id, reasoning.id])
        #expect(fixture.assistant.snapshot.attemptedInvocations == [.memorySelection, .memoryReminder, .reasoning])
        #expect(receipts.map(\.model.name) == ["selector-fixture", "selector-fixture", "reasoner-fixture"])
        #expect(receipts.allSatisfy { $0.elapsedMilliseconds == 7 && isDigest($0.inputDigest) && isDigest($0.outputDigest) })
        #expect(Set(fixture.trace.requestIDs).count == fixture.trace.requestIDs.count)
    }

    @Test func enabledContextSkipsBothOptionalRolesWhenNoSpansAreEligible() async throws {
        let fixture = CoordinatorFixture(contextEnabled: true)
        defer { fixture.cleanUp() }
        try await fixture.assistant.connect()
        // This single grapheme exceeds the candidate byte cap, while the request
        // remains valid and small. Candidate extraction deliberately omits it.
        let request = makeRequest("e" + String(repeating: "\u{301}", count: 800))
        try await fixture.assistant.reply(to: request, onEvent: { _ in })
        #expect(fixture.trace.roles == [.reasoning])
        #expect(fixture.selector.connectCount == 0)
        #expect(fixture.selector.requests.isEmpty)
        #expect(fixture.assistant.snapshot.attemptedInvocations == [.reasoning])
        #expect(fixture.assistant.snapshot.receipts.map(\.role) == [.reasoning])
        #expect(ids(fixture.reasoner.requests[0], "memories").isEmpty)
        #expect(fixture.assistant.snapshot.records.isEmpty)
        #expect(fixture.assistant.snapshot.turn == 1)
        #expect(fixture.assistant.snapshot.proposal != nil)
    }

    @Test func earlierMemoriesStillConnectTheSelectorWhenThereAreNoNewCandidates() async throws {
        let fixture = CoordinatorFixture(contextEnabled: true)
        defer { fixture.cleanUp() }
        try await fixture.assistant.connect()
        try await fixture.assistant.reply(to: makeRequest("Keep the earlier constraint."), onEvent: { _ in })
        let retained = try #require(fixture.assistant.snapshot.records.first)
        fixture.assistant.disconnect()
        try await fixture.assistant.connect()
        let previousCalls = fixture.selector.requests.count
        let request = makeRequest("e" + String(repeating: "\u{301}", count: 800))
        try await fixture.assistant.reply(to: request, onEvent: { _ in })
        #expect(fixture.selector.connectCount == 2)
        #expect(fixture.selector.requests.dropFirst(previousCalls).map(\.role) == [.memoryReminder])
        #expect(fixture.assistant.snapshot.attemptedInvocations == [.memoryReminder, .reasoning])
        #expect(fixture.assistant.snapshot.receipts.map(\.role) == [.memoryReminder, .reasoning])
        #expect(fixture.assistant.snapshot.proposal?.memoryIDs == [retained.id])
        #expect(fixture.assistant.snapshot.records.count == 1)
        #expect(fixture.assistant.snapshot.turn == 2)
    }

    @Test func turnsWithoutNewCandidatesStillExpireEarlierContext() async throws {
        let fixture = CoordinatorFixture(contextEnabled: true)
        defer { fixture.cleanUp() }
        try await fixture.assistant.connect()
        try await fixture.assistant.reply(to: makeRequest("A bounded earlier constraint."), onEvent: { _ in })
        let request = makeRequest("e" + String(repeating: "\u{301}", count: 800))
        for _ in 0..<HamptonSessionContext.userLifetimeTurns {
            try await fixture.assistant.reply(to: request, onEvent: { _ in })
        }
        #expect(fixture.assistant.snapshot.records.isEmpty)
        #expect(fixture.assistant.snapshot.turn == 1 + HamptonSessionContext.userLifetimeTurns)
        #expect(fixture.assistant.snapshot.attemptedInvocations == [.reasoning])
        #expect(fixture.assistant.snapshot.proposal?.memoryIDs.isEmpty == true)
    }

    @Test func invalidOutputAtEveryRolePreservesThePreviouslyCommittedBankAndEmitsNothing() async throws {
        for rejectedRole in [LocalModelRole.memorySelection, .memoryReminder, .reasoning] {
            let fixture = CoordinatorFixture(contextEnabled: true)
            defer { fixture.cleanUp() }
            try await fixture.assistant.connect()
            try await fixture.assistant.reply(to: makeRequest("An earlier explicit constraint."), onEvent: { _ in })
            let committed = fixture.assistant.snapshot.records
            let turn = fixture.assistant.snapshot.turn
            let invalid: (LocalRoleRequest, QwenModelMetadata) throws -> LocalRoleResult = { request, model in
                try roleResult(request, model: model, additionalFields:
                    request.role == rejectedRole ? ["permissionGrant": .bool(true)] : [:])
            }
            fixture.selector.response = invalid
            fixture.reasoner.response = invalid
            let events = CoordinatorEvents()
            do {
                try await fixture.assistant.reply(to: makeRequest("A tentative new constraint."), onEvent: events.receive)
                Issue.record("An unknown authority field must reject the current turn.")
            } catch {
                #expect(error is HamptonAssistantFailure)
            }
            #expect(events.texts.isEmpty)
            #expect(fixture.assistant.snapshot.records == committed)
            #expect(fixture.assistant.snapshot.turn == turn)
            #expect(fixture.assistant.snapshot.proposal == nil)
            let acceptedRoleCount = rejectedRole == .memorySelection ? 0 : rejectedRole == .memoryReminder ? 1 : 2
            #expect(fixture.assistant.snapshot.receipts.count == acceptedRoleCount)
            #expect(fixture.assistant.snapshot.attemptedInvocations.count == acceptedRoleCount + 1)
            #expect(fixture.assistant.snapshot.attemptedInvocations.last == rejectedRole)
        }
    }

    @Test func modelFailureAfterSelectionCannotCommitTentativeContext() async throws {
        let fixture = CoordinatorFixture(contextEnabled: true)
        defer { fixture.cleanUp() }
        try await fixture.assistant.connect()
        fixture.reasoner.response = { _, _ in throw CoordinatorTestFailure.modelFailed }
        let events = CoordinatorEvents()
        do {
            try await fixture.assistant.reply(to: makeRequest("This must remain tentative."), onEvent: events.receive)
            Issue.record("The model failure must escape without an admitted reply.")
        } catch {
            #expect((error as? CoordinatorTestFailure) == .modelFailed)
        }
        #expect(fixture.trace.roles == [.memorySelection, .reasoning])
        #expect(fixture.assistant.snapshot.attemptedInvocations == [.memorySelection, .reasoning])
        #expect(fixture.assistant.snapshot.receipts.map(\.role) == [.memorySelection])
        #expect(fixture.assistant.snapshot.records.isEmpty)
        #expect(fixture.assistant.snapshot.turn == 0)
        #expect(fixture.assistant.snapshot.proposal == nil)
        #expect(events.texts.isEmpty)
    }

    @Test func cancellationAtEachAwaitedRoleRejectsItsLateValidCompletion() async throws {
        for pausedRole in [LocalModelRole.memorySelection, .memoryReminder, .reasoning] {
            let fixture = CoordinatorFixture(contextEnabled: true)
            defer { fixture.cleanUp() }
            try await fixture.assistant.connect()
            try await fixture.assistant.reply(to: makeRequest("Earlier committed context."), onEvent: { _ in })
            let committed = fixture.assistant.snapshot.records
            let previousCalls = fixture.trace.roles.count
            let client = pausedRole == .reasoning ? fixture.reasoner : fixture.selector
            client.shouldPause = { $0.role == pausedRole }
            let events = CoordinatorEvents()
            let work = Task { try await fixture.assistant.reply(to: makeRequest("A cancelled candidate."), onEvent: events.receive) }
            defer { work.cancel() }
            try await eventually { client.pendingGenerationCount == 1 }
            let attempts = fixture.assistant.snapshot.attemptedInvocations
            #expect(attempts.last == pausedRole)
            try await Task.sleep(for: .milliseconds(10))
            work.cancel()
            try client.resolveFirstGeneration()
            await expectStopped(work)
            #expect(events.texts.isEmpty)
            #expect(fixture.assistant.snapshot.records == committed)
            #expect(fixture.assistant.snapshot.proposal == nil)
            let expectedCount = pausedRole == .memorySelection ? 1 : pausedRole == .memoryReminder ? 2 : 3
            #expect(fixture.trace.roles.count - previousCalls == expectedCount)
            #expect(fixture.assistant.snapshot.attemptedInvocations == attempts)
            #expect(fixture.assistant.snapshot.receipts.count == expectedCount - 1)
            #expect(fixture.assistant.snapshot.elapsedMilliseconds >= 10)
            #expect(client.pendingGenerationCount == 0)
        }
    }

    @Test func clearingOrDisablingDuringReasoningErasesTheBankAndFencesLateOutput() async throws {
        for disable in [false, true] {
            let fixture = CoordinatorFixture(contextEnabled: true)
            defer { fixture.cleanUp() }
            try await fixture.assistant.connect()
            try await fixture.assistant.reply(to: makeRequest("Previously retained context."), onEvent: { _ in })
            #expect(!fixture.assistant.snapshot.records.isEmpty)
            fixture.reasoner.shouldPause = { _ in true }
            let events = CoordinatorEvents()
            let work = Task { try await fixture.assistant.reply(to: makeRequest("New pending context."), onEvent: events.receive) }
            defer { work.cancel() }
            try await eventually { fixture.reasoner.pendingGenerationCount == 1 }
            if disable { fixture.assistant.setContextEnabled(false) }
            else { fixture.assistant.clearSessionContext() }
            let cleared = fixture.assistant.snapshot
            #expect(cleared.records.isEmpty)
            #expect(cleared.proposal == nil)
            #expect(cleared.turn == 0)
            #expect(fixture.assistant.contextEnabled == !disable)
            try fixture.reasoner.resolveFirstGeneration()
            await expectStopped(work)
            #expect(fixture.assistant.snapshot == cleared)
            #expect(events.texts.isEmpty)
            do {
                try await fixture.assistant.reply(to: makeRequest("Requires reconnect."), onEvent: { _ in })
                Issue.record("Invalidation during work must require an explicit reconnect.")
            } catch { #expect((error as? QwenFailure) == .unavailable) }
        }
    }

    @Test func disconnectedOldTurnCannotOverwriteANewEpochAfterLateSuccessOrFailure() async throws {
        for lateFailure in [false, true] {
            let fixture = CoordinatorFixture(contextEnabled: true)
            defer { fixture.cleanUp() }
            try await fixture.assistant.connect()
            fixture.reasoner.shouldPause = { _ in true }
            let oldEvents = CoordinatorEvents()
            let oldWork = Task { try await fixture.assistant.reply(to: makeRequest("Old uncommitted question."), onEvent: oldEvents.receive) }
            defer { oldWork.cancel() }
            try await eventually { fixture.reasoner.pendingGenerationCount == 1 }
            fixture.assistant.disconnect()
            try await fixture.assistant.connect()
            fixture.reasoner.shouldPause = { _ in false }
            let currentEvents = CoordinatorEvents()
            try await fixture.assistant.reply(to: makeRequest("Current question."), onEvent: currentEvents.receive)
            let current = fixture.assistant.snapshot
            #expect(current.records.map(\.text) == ["Current question."])
            if lateFailure { fixture.reasoner.failFirstGeneration(CoordinatorTestFailure.modelFailed) }
            else { try fixture.reasoner.resolveFirstGeneration() }
            do {
                try await oldWork.value
                Issue.record("The retired turn must fail.")
            } catch { /* A retired transport failure or stopped result may escape; neither can publish. */ }
            #expect(fixture.assistant.snapshot == current)
            #expect(oldEvents.texts.isEmpty)
            #expect(currentEvents.texts == ["Accepted local answer."])
            #expect(fixture.reasoner.pendingGenerationCount == 0)
        }
    }

    @Test func lateConnectionCompletionCannotReviveAnOlderConnectionEpoch() async throws {
        let fixture = CoordinatorFixture(contextEnabled: false)
        defer { fixture.cleanUp() }
        fixture.reasoner.pauseConnections = true
        let oldConnect = Task { try await fixture.assistant.connect() }
        defer { oldConnect.cancel() }
        try await eventually { fixture.reasoner.pendingConnectionCount == 1 }
        fixture.assistant.disconnect()
        let newConnect = Task { try await fixture.assistant.connect() }
        defer { newConnect.cancel() }
        try await eventually { fixture.reasoner.pendingConnectionCount == 2 }
        fixture.reasoner.resolveConnection(1)
        try await newConnect.value
        fixture.reasoner.resolveConnection(0)
        await expectStopped(oldConnect)
        #expect(fixture.trace.roles.isEmpty)
        let events = CoordinatorEvents()
        try await fixture.assistant.reply(to: makeRequest("Use the current connection."), onEvent: events.receive)
        #expect(events.texts == ["Accepted local answer."])
        #expect(fixture.trace.roles == [.reasoning])
        #expect(fixture.reasoner.pendingConnectionCount == 0)
    }

    @Test func invalidationInsideTheSnapshotCallbackPreventsAnswerEmission() async throws {
        let fixture = CoordinatorFixture(contextEnabled: true)
        defer { fixture.cleanUp() }
        try await fixture.assistant.connect()
        fixture.assistant.onSnapshot = { [weak assistant = fixture.assistant] snapshot in
            if snapshot.proposal != nil { assistant?.clearSessionContext() }
        }
        let events = CoordinatorEvents()
        do {
            try await fixture.assistant.reply(to: makeRequest("Revoked at publication."), onEvent: events.receive)
            Issue.record("A synchronous observer may revoke context before text emission.")
        } catch { #expect((error as? QwenFailure) == .stopped) }
        #expect(events.texts.isEmpty)
        #expect(fixture.assistant.snapshot.records.isEmpty)
        #expect(fixture.assistant.snapshot.proposal == nil)
        #expect(fixture.assistant.snapshot.turn == 0)
    }

    @Test func cancellationAtPhasePublicationDoesNotCountAnUnsentInvocation() async throws {
        let fixture = CoordinatorFixture(contextEnabled: false)
        defer { fixture.cleanUp() }
        try await fixture.assistant.connect()
        fixture.assistant.onSnapshot = { [weak assistant = fixture.assistant] snapshot in
            if snapshot.phase == "Preparing an answer from the supplied context…" { assistant?.disconnect() }
        }
        do {
            try await fixture.assistant.reply(to: makeRequest("Do not dispatch after Stop."), onEvent: { _ in Issue.record("Cancelled answer") })
            Issue.record("A synchronous phase cancellation must stop dispatch")
        } catch { #expect((error as? QwenFailure) == .stopped) }
        #expect(fixture.trace.roles.isEmpty)
        #expect(fixture.assistant.snapshot.attemptedInvocations.isEmpty)
    }

    @Test func optionalCandidateBudgetTrimsBeforeModelDispatch() async throws {
        let fixture = CoordinatorFixture(contextEnabled: true)
        defer { fixture.cleanUp() }
        try await fixture.assistant.connect()
        let request = makeRequest(String(repeating: "Remember this useful sentence. ", count: 500))
        var candidateBank = HamptonSessionContext()
        let originalCandidates = candidateBank.beginTurn(request: request)
        #expect(originalCandidates.count == HamptonSessionContext.maximumCandidates)
        try await fixture.assistant.reply(to: request, onEvent: { _ in })
        let selection = try #require(fixture.selector.requests.first)
        let offered = ids(selection, "candidates")
        #expect(!offered.isEmpty)
        #expect(offered.count < originalCandidates.count)
        #expect(selection.input["candidates"]?.array?.allSatisfy { candidate in
            originalCandidates.contains { $0.text == candidate["text"]?.string }
        } == true)
        #expect(fixture.assistant.snapshot.attemptedInvocations == [.memorySelection, .reasoning])
    }

    @Test func shutdownDisposesPendingWorkAndPreventsFutureConnections() async throws {
        let fixture = CoordinatorFixture(contextEnabled: true)
        defer { fixture.cleanUp() }
        try await fixture.assistant.connect()
        fixture.selector.shouldPause = { _ in true }
        let events = CoordinatorEvents()
        let work = Task { try await fixture.assistant.reply(to: makeRequest("Discard on shutdown."), onEvent: events.receive) }
        defer { work.cancel() }
        try await eventually { fixture.selector.pendingGenerationCount == 1 }
        await fixture.assistant.shutdown()
        let disposed = fixture.assistant.snapshot
        try fixture.selector.resolveFirstGeneration()
        await expectStopped(work)
        #expect(fixture.assistant.snapshot == disposed)
        #expect(disposed.records.isEmpty)
        #expect(events.texts.isEmpty)
        #expect(fixture.reasoner.shutdownCount == 1)
        #expect(fixture.selector.shutdownCount == 1)
        do {
            try await fixture.assistant.connect()
            Issue.record("A disposed coordinator cannot reconnect.")
        } catch { #expect((error as? QwenFailure) == .stopped) }
    }
}

private enum CoordinatorTestFailure: Error, Equatable { case modelFailed, waitExpired, noPendingCall }

@MainActor
private final class CoordinatorTrace {
    var roles: [LocalModelRole] = []
    var requestIDs: [String] = []
}

@MainActor
private final class CoordinatorEvents {
    var texts: [String] = []
    var revisions: [PassageRevisionProposal] = []
    func receive(_ event: AssistantEvent) {
        switch event { case .text(let text): texts.append(text); case .revision(let proposal): revisions.append(proposal) }
    }
}

@MainActor
private final class CoordinatorFixture {
    let trace: CoordinatorTrace
    let reasoner: ControlledRoleClient
    let selector: ControlledRoleClient
    let assistant: HamptonReasonsAssistant

    init(contextEnabled: Bool) {
        let trace = CoordinatorTrace()
        self.trace = trace
        reasoner = ControlledRoleClient(name: "reasoner-fixture", trace: trace)
        selector = ControlledRoleClient(name: "selector-fixture", trace: trace)
        assistant = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector, contextEnabled: contextEnabled)
    }

    func cleanUp() {
        assistant.onSnapshot = nil
        assistant.disconnect()
        reasoner.drainPending()
        selector.drainPending()
    }
}

/// Disconnect deliberately does not resolve held calls: the coordinator must
/// defend against a transport that delivers a result after it has been retired.
@MainActor
private final class ControlledRoleClient: LocalRoleClient {
    let model: QwenModelMetadata
    let trace: CoordinatorTrace
    var connectCount = 0
    var disconnectCount = 0
    var shutdownCount = 0
    var requests: [LocalRoleRequest] = []
    var pauseConnections = false
    var shouldPause: (LocalRoleRequest) -> Bool = { _ in false }
    var response: (LocalRoleRequest, QwenModelMetadata) throws -> LocalRoleResult = { try roleResult($0, model: $1) }
    private var connections: [Int: CheckedContinuation<Void, Error>] = [:]
    private var generations: [Int: CheckedContinuation<LocalRoleResult, Error>] = [:]
    var pendingConnectionCount: Int { connections.count }
    var pendingGenerationCount: Int { generations.count }

    init(name: String, trace: CoordinatorTrace) {
        self.trace = trace
        model = QwenModelMetadata(name: name, family: "fixture", parameterSize: "fixture",
            quantization: "fixture", digest: String(repeating: "a", count: 64))
    }

    func connect() async throws {
        let index = connectCount
        connectCount += 1
        if pauseConnections {
            try await withCheckedThrowingContinuation { connections[index] = $0 }
        }
    }

    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        let index = requests.count
        requests.append(request)
        trace.roles.append(request.role)
        trace.requestIDs.append(request.id)
        if shouldPause(request) {
            return try await withCheckedThrowingContinuation { generations[index] = $0 }
        }
        return try response(request, model)
    }

    func disconnect() { disconnectCount += 1 }
    func shutdown() async { shutdownCount += 1; disconnect() }
    func resolveConnection(_ index: Int) { connections.removeValue(forKey: index)?.resume() }

    func resolveFirstGeneration() throws {
        guard let index = generations.keys.min() else { throw CoordinatorTestFailure.noPendingCall }
        let result = try response(requests[index], model)
        generations.removeValue(forKey: index)?.resume(returning: result)
    }

    func failFirstGeneration(_ error: Error) {
        guard let index = generations.keys.min() else { return }
        generations.removeValue(forKey: index)?.resume(throwing: error)
    }

    func drainPending() {
        let pendingConnections = Array(connections.values)
        let pendingGenerations = Array(generations.values)
        connections.removeAll(); generations.removeAll()
        pendingConnections.forEach { $0.resume(throwing: QwenFailure.stopped) }
        pendingGenerations.forEach { $0.resume(throwing: QwenFailure.stopped) }
    }
}

private func makeRequest(_ prompt: String, text: String? = nil, selection: Bool = false) -> AssistantRequest {
    AssistantRequest(prompt: prompt, sourceName: text == nil ? nil : "fixture.txt", sourceText: text ?? "",
        sourceRevision: 4, placementRevision: 7, tone: "Warm", replyLength: 0.25,
        selection: selection ? DocumentSelection(range: NSRange(location: 0, length: (text ?? "").utf16.count), text: text ?? "", sourceRevision: 4) : nil)
}

private func makeRevisionRequest() throws -> AssistantRequest {
    let source = "The launch is Friday."
    let selection = try #require(DocumentSelection(range: NSRange(location: 0, length: source.utf16.count), text: source, sourceRevision: 4))
    let target = try #require(RevisionTarget(text: source, sourceRevision: 4, selection: selection))
    return AssistantRequest(prompt: "Make the launch sentence concise.", sourceName: "fixture.txt", sourceText: source,
        sourceRevision: 4, placementRevision: 7, tone: "Warm", replyLength: 0.25, selection: selection,
        localLessons: [LessonSnapshot(id: UUID().uuidString, revision: 1, topic: "launch", text: "Keep the launch day.")],
        revisionTarget: target)
}

private func revisionRoleResult(_ request: LocalRoleRequest, model: QwenModelMetadata) throws -> LocalRoleResult {
    let target = try #require(request.input["context"]?["revisionTarget"]?["id"]?.string)
    let payload: JSONValue = .object(["schema": .string("native-passage-revision/v1"), "targetID": .string(target),
        "decision": .string("PROPOSE"), "replacement": .string("Launch: Friday."), "explanation": .string("Shortened the wording."),
        "sourceIDs": .array([.string("selected-passage")]), "memoryIDs": .array(ids(request, "memories").map(JSONValue.string))])
    return LocalRoleResult(requestID: request.id, role: request.role,
        text: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self), model: model, elapsedMilliseconds: 7)
}

private func ids(_ request: LocalRoleRequest, _ field: String) -> [String] {
    request.input[field]?.array?.compactMap { $0["id"]?.string } ?? []
}

private func roleResult(_ request: LocalRoleRequest, model: QwenModelMetadata,
                        additionalFields: [String: JSONValue] = [:]) throws -> LocalRoleResult {
    var payload: [String: JSONValue] = ["requestID": .string(request.id)]
    switch request.role {
    case .memorySelection:
        payload["schema"] = .string("archi-session-selection/v1")
        payload["candidateIDs"] = .array(ids(request, "candidates").prefix(1).map(JSONValue.string))
    case .memoryReminder:
        let selected = Array(ids(request, "memories").prefix(3))
        payload["schema"] = .string("archi-session-reminder/v1")
        payload["decision"] = .string(selected.isEmpty ? "NONE" : "SELECT")
        payload["memoryIDs"] = .array(selected.map(JSONValue.string))
    case .reasoning:
        payload["schema"] = .string("archi-reason-proposal/v1")
        payload["kind"] = .string("ANSWER")
        payload["answer"] = .string("Accepted local answer.")
        payload["uncertainty"] = .string("")
        payload["sourceIDs"] = .array(ids(request, "sources").map(JSONValue.string))
        payload["memoryIDs"] = .array(ids(request, "memories").map(JSONValue.string))
    }
    payload.merge(additionalFields) { _, supplied in supplied }
    let bytes = try JSONEncoder().encode(JSONValue.object(payload))
    return LocalRoleResult(requestID: request.id, role: request.role,
        text: String(decoding: bytes, as: UTF8.self), model: model, elapsedMilliseconds: 7)
}

private func isDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}

@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw CoordinatorTestFailure.waitExpired }
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
private func expectStopped(_ work: Task<Void, Error>) async {
    do {
        try await work.value
        Issue.record("Retired or cancelled work must not complete successfully.")
    } catch { #expect((error as? QwenFailure) == .stopped) }
}
