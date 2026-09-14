import XCTest
@testable import ARCHiDesktop

final class AutomaticAssistantRoutingTests: XCTestCase {
    @MainActor
    func testManualRoutesStillRequireExplicitReadyConnections() async throws {
        for route in [AssistantRoute.local, .codex, .compare] {
            let f = AutomaticRoutingFixture(), store = f.store
            defer { f.drain() }
            store.setAssistantRoute(route)
            store.prompt = "Do not connect a manual route implicitly."
            store.submit()
            await Task.yield()
            XCTAssertFalse(store.isWorking, route.rawValue)
            XCTAssertEqual(f.local.connectCount, 0, route.rawValue)
            XCTAssertEqual(f.cloud.connectCount, 0, route.rawValue)
            XCTAssertTrue(f.local.replies.isEmpty, route.rawValue)
            XCTAssertTrue(f.cloud.replies.isEmpty, route.rawValue)
        }
    }

    @MainActor
    func testAutomaticSelectionDoesNoWorkAndSuccessfulLocalSendNeverContactsCodex() async throws {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        store.setAssistantRoute(.automatic)
        await Task.yield()
        XCTAssertEqual(f.local.connectCount, 0)
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.local.replies.isEmpty)
        XCTAssertTrue(f.cloud.replies.isEmpty)

        store.prompt = "Help arrange a short local task."
        store.submit()
        // A manual Connect in the same run-loop turn cannot steal the automatic
        // lane's connection epoch and strand its work owner.
        store.connectAssistant(provider: .qwen)
        try await wait("Automatic Send connects locally") { f.local.connectCount == 1 }
        XCTAssertTrue(store.isWorking)
        XCTAssertEqual(store.assistantActivity, .working)
        XCTAssertTrue(f.local.replies.isEmpty)
        XCTAssertEqual(store.compareResults[.qwen]?.receipt?.requestStarted, false)
        f.local.resolveConnection(0)
        try await wait("Connected local request starts") { f.local.replies.count == 1 }
        f.local.emit(0, text: "The local answer.")
        f.local.resolveReply(0)
        try await wait("Local success finishes Automatic") { !store.isWorking }
        XCTAssertEqual(store.reply, "The local answer.")
        XCTAssertEqual(store.assistantActivity, .ready)
        let receipt = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        XCTAssertEqual(receipt.route, .automatic)
        XCTAssertEqual(receipt.state, .complete)
        XCTAssertNotNil(receipt.routingReason)
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.cloud.replies.isEmpty)

        store.prompt = "A second local task."
        store.submit()
        try await wait("Next Automatic Send reuses the ready local connection") { f.local.replies.count == 2 }
        XCTAssertEqual(f.local.connectCount, 1)
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.cloud.replies.isEmpty)
    }

    @MainActor
    func testDefaultRemainsQwenAndAutoConnectBudgetHasNoExternalRequest() {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        XCTAssertEqual(store.route, .local)
        XCTAssertEqual(store.assistantProvider, .qwen)
        store.setAssistantRoute(.automatic)
        XCTAssertEqual(store.resultProviders, [.qwen])
        XCTAssertEqual(store.nextCallBudget, "1 local answer call · no external requests")
        store.setSessionContextEnabled(true)
        XCTAssertEqual(store.nextCallBudget, "1 local answer call, plus up to 2 context calls · no external requests")
    }

    @MainActor
    func testEveryLocalConnectionAndReplyFailureStaysLocal() async throws {
        let failures: [any Error] = [QwenFailure.unavailable, QwenFailure.unsupportedModel,
            QwenFailure.modelUnavailable, QwenFailure.nonLocalModel, QwenFailure.modelChanged,
            QwenFailure.invalidResponse, QwenFailure.contextLimit, QwenFailure.outputLimit,
            QwenFailure.timedOut, QwenFailure.stopped, QwenFailure.generationFailed, QwenFailure.busy,
            HamptonAssistantFailure.contextLimit, HamptonAssistantFailure.invalidProposal,
            HamptonAssistantFailure.timedOut, AssistantFailure.protocolError,
            AssistantFailure.stopped, CancellationError(), AutomaticRoutingTestFailure.unexpected]
        for error in failures {
            for stage in ["connect", "reply"] {
                let f = AutomaticRoutingFixture(), store = f.store
                defer { f.drain() }
                store.setAssistantRoute(.automatic)
                store.prompt = "This failure must not share my work externally."
                store.submit()
                try await wait("Local attempt begins") { f.local.connectCount == 1 }
                if stage == "connect" {
                    f.local.resolveConnection(0, result: .failure(error))
                } else {
                    f.local.resolveConnection(0)
                    try await wait("Local reply begins") { f.local.replies.count == 1 }
                    f.local.emit(0, text: "PRIVATE partial response")
                    f.local.resolveReply(0, result: .failure(error))
                }
                try await wait("Failure ends the local request") { !store.isWorking }
                await Task.yield()
                XCTAssertEqual(f.cloud.connectCount, 0, "\(stage): \(error)")
                XCTAssertTrue(f.cloud.replies.isEmpty, "\(stage): \(error)")
                XCTAssertNil(store.compareResults[.codex], "\(stage): \(error)")
                XCTAssertEqual(store.compareResults[.qwen]?.state, .failed)
                XCTAssertEqual(store.compareResults[.qwen]?.text, "")
                XCTAssertEqual(store.assistantProvider, .qwen)
                XCTAssertEqual(store.assistantActivity, .failed)
                XCTAssertEqual(f.local.connectCount, 1)
            }
        }
    }

    @MainActor
    func testRejectedOrMissingRevisionNeverStartsAnExternalRequest() async throws {
        for emitsUnvalidatedText in [false, true] {
            let f = AutomaticRoutingFixture(), store = f.store
            defer { f.drain() }
            store.share(text: "Keep this original passage.", name: "revision.txt")
            store.selectText(range: NSRange(location: 0, length: 26), sourceRevision: store.sourceRevision)
            store.requestsRevision = true
            try await beginLocal(f, question: "Make this passage shorter.")
            XCTAssertNotNil(f.local.replies[0].request.revisionTarget)
            if emitsUnvalidatedText { f.local.emit(0, text: "This is not a validated revision proposal.") }
            f.local.resolveReply(0)
            try await wait("Invalid revision ends locally") { !store.isWorking }
            await Task.yield()
            XCTAssertEqual(store.compareResults[.qwen]?.state, .failed)
            XCTAssertNil(store.compareResults[.qwen]?.revision)
            XCTAssertEqual(store.sharedText, "Keep this original passage.")
            XCTAssertEqual(f.cloud.connectCount, 0)
            XCTAssertTrue(f.cloud.replies.isEmpty)
            XCTAssertNil(store.compareResults[.codex])
        }
    }

    @MainActor
    func testLocalFailureNeverUsesAnAlreadyReadyCodexConnection() async throws {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        store.connectAssistant(provider: .codex)
        try await wait("Explicit external connection starts") { f.cloud.connectCount == 1 }
        f.cloud.resolveConnection(0)
        try await wait("External connection is ready") { store.connection(for: .codex) == .ready }
        try await beginLocal(f)
        f.local.resolveReply(0, result: .failure(QwenFailure.timedOut))
        try await wait("Local failure finishes") { !store.isWorking }
        XCTAssertEqual(f.cloud.connectCount, 1)
        XCTAssertTrue(f.cloud.replies.isEmpty)
        XCTAssertNil(store.compareResults[.codex])
        XCTAssertEqual(store.connection(for: .codex), .ready)
    }

    @MainActor
    func testExplicitExternalSendAfterFailureCapturesCurrentChoiceWithoutPrivateContext() async throws {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        store.share(text: "First. Café is the selected passage.", name: "original.txt")
        store.placed(at: CGPoint(x: -90, y: 320))
        store.selectText(range: NSRange(location: 7, length: 4), sourceRevision: store.sourceRevision)
        store.beginLessonCorrection()
        var draft = try XCTUnwrap(store.lessonDraft)
        draft.topic = "selected passage"
        draft.text = "LOCAL-ONLY-LESSON: Prefer a short explanation."
        draft.source = store.currentLessonSource
        XCTAssertTrue(store.keepLesson(draft), store.lessonMessage)
        store.preferences.tone = "Warm"
        store.evolution.confirmRole(.muse)
        store.evolution.confirmHelpStyle(.stepByStep)
        try await beginLocal(f, question: "Explain the selected passage.")
        let firstRequest = f.local.replies[0].request
        XCTAssertEqual(firstRequest.localLessons.count, 1)
        let originalReceipt = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        f.local.emit(0, text: "PRIVATE-LOCAL-PARTIAL")
        store.prompt = "Give a second opinion on the selected passage."
        store.preferences.tone = "Direct"
        store.evolution.confirmRole(.beacon)
        store.evolution.confirmHelpStyle(.concise)
        f.local.resolveReply(0, result: .failure(QwenFailure.invalidResponse))
        try await wait("Failed local request ends") { !store.isWorking }
        XCTAssertEqual(store.compareResults[.qwen]?.receipt?.settings, firstRequest.settings)
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.cloud.replies.isEmpty)

        store.setAssistantRoute(.codex)
        await Task.yield()
        XCTAssertEqual(f.cloud.connectCount, 0, "Choosing a reference route sends nothing")
        XCTAssertTrue(f.cloud.replies.isEmpty)
        store.connectAssistant(provider: .codex)
        try await wait("Explicit reference connection starts") { f.cloud.connectCount == 1 }
        f.cloud.resolveConnection(0)
        try await wait("Reference connection is ready") { store.connection(for: .codex) == .ready }
        XCTAssertTrue(f.cloud.replies.isEmpty, "Connection is not Send")
        let selectedSettings = store.nextReplySettings
        store.submit()
        try await wait("Explicit Send starts the reference request") { f.cloud.replies.count == 1 }
        let reference = f.cloud.replies[0].request
        XCTAssertEqual(reference.prompt, "Give a second opinion on the selected passage.")
        XCTAssertEqual(reference.settings, selectedSettings)
        XCTAssertNotEqual(reference.settings, firstRequest.settings)
        XCTAssertEqual(reference.sourceText, firstRequest.sourceText)
        XCTAssertEqual(reference.selection, firstRequest.selection)
        XCTAssertTrue(reference.localLessons.isEmpty)
        XCTAssertNil(reference.localLessonDigest)
        XCTAssertFalse(reference.codexInput.contains("LOCAL-ONLY-LESSON"))
        XCTAssertFalse(reference.codexInput.contains("PRIVATE-LOCAL-PARTIAL"))
        let receipt = try XCTUnwrap(store.compareResults[.codex]?.receipt)
        XCTAssertEqual(receipt.route, .codex)
        XCTAssertNotEqual(receipt.requestID, originalReceipt.requestID)
        XCTAssertNotEqual(receipt.inputDigest, originalReceipt.inputDigest)
        f.cloud.emit(0, text: "The requested external reference.")
        f.cloud.resolveReply(0)
        try await wait("Reference finishes") { !store.isWorking }
        XCTAssertEqual(store.reply, "The requested external reference.")
        f.local.emit(0, text: "Late local callback")
        await Task.yield()
        XCTAssertEqual(store.reply, "The requested external reference.")
        XCTAssertEqual(f.cloud.replies.count, 1)
    }

    @MainActor
    func testStopDuringLocalConnectionRejectsLateSuccessAndFailure() async throws {
        for lateResult in [Result<Void, any Error>.success(()), .failure(QwenFailure.unavailable)] {
            let f = AutomaticRoutingFixture(), store = f.store
            defer { f.drain() }
            store.setAssistantRoute(.automatic)
            store.prompt = "Stop before any inference."
            store.submit()
            try await wait("Local connection pending") { f.local.connectCount == 1 }
            store.cancelWork()
            XCTAssertFalse(store.isWorking)
            let reply = store.reply, status = store.status, results = store.compareResults
            f.local.resolveConnection(0, result: lateResult)
            try await wait("Late connection callback drained") { f.local.finishedConnections.contains(0) }
            await Task.yield()
            XCTAssertTrue(f.local.replies.isEmpty)
            XCTAssertEqual(f.cloud.connectCount, 0)
            XCTAssertTrue(f.cloud.replies.isEmpty)
            XCTAssertEqual(store.reply, reply)
            XCTAssertEqual(store.status, status)
            XCTAssertEqual(store.compareResults, results)
            XCTAssertFalse(store.isWorking)
        }
    }

    @MainActor
    func testLocalReplyInvalidationPreventsStaleReplyOrExternalRequest() async throws {
        for change in ["stop", "source", "placement", "selection", "route", "model", "context model", "clear context", "disable context"] {
            let f = AutomaticRoutingFixture(), store = f.store
            defer { f.drain() }
            store.share(text: "First. Second.", name: "source.txt")
            store.setSessionContextEnabled(true)
            try await beginLocal(f)
            f.local.emit(0, text: "An obsolete local partial.")
            switch change {
            case "stop": store.cancelWork()
            case "source": store.share(text: "New shared source.", name: "new.txt")
            case "placement": store.placed(at: CGPoint(x: 700, y: -120))
            case "selection": store.selectText(range: NSRange(location: 0, length: 6), sourceRevision: store.sourceRevision)
            case "route": store.setAssistantRoute(.local)
            case "model": store.selectQwenModel(try XCTUnwrap(QwenAssistant.supportedModels.first { $0 != store.qwenModel }))
            case "context model": store.selectQwenContextModel(try XCTUnwrap(QwenAssistant.supportedModels.first { $0 != store.qwenContextModel }))
            case "clear context": store.clearSessionContext()
            default: store.setSessionContextEnabled(false)
            }
            XCTAssertFalse(store.isWorking, change)
            let reply = store.reply, status = store.status, results = store.compareResults
            f.local.emit(0, text: "Stale local text.")
            f.local.resolveReply(0, result: .failure(QwenFailure.generationFailed))
            try await wait("Invalidated reply callback drains") { f.local.finishedReplies.contains(0) }
            await Task.yield()
            XCTAssertEqual(f.cloud.connectCount, 0, change)
            XCTAssertTrue(f.cloud.replies.isEmpty, change)
            XCTAssertEqual(store.reply, reply, change)
            XCTAssertEqual(store.status, status, change)
            XCTAssertEqual(store.compareResults, results, change)
            XCTAssertFalse(store.isWorking, change)
        }
    }

    @MainActor
    func testLocalFailureCanRetryLocallyWithoutExternalCalls() async throws {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        try await beginLocal(f)
        f.local.resolveReply(0, result: .failure(QwenFailure.generationFailed))
        try await wait("First local attempt ends") { !store.isWorking }
        store.prompt = "A shorter local retry."
        store.submit()
        try await wait("Local retry reconnects") { f.local.connectCount == 2 }
        f.local.resolveConnection(1)
        try await wait("Retry starts locally") { f.local.replies.count == 2 }
        f.local.emit(1, text: "The retry succeeded locally.")
        f.local.resolveReply(1)
        try await wait("Local retry finishes") { !store.isWorking }
        XCTAssertEqual(store.reply, "The retry succeeded locally.")
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.cloud.replies.isEmpty)
    }

    @MainActor
    private func beginLocal(_ fixture: AutomaticRoutingFixture, question: String = "A bounded Automatic task.") async throws {
        fixture.store.setAssistantRoute(.automatic)
        fixture.store.prompt = question
        fixture.store.submit()
        try await wait("Automatic connects Qwen") { fixture.local.connectCount == 1 }
        fixture.local.resolveConnection(0)
        try await wait("Automatic starts local inference") { fixture.local.replies.count == 1 }
    }

    @MainActor
    private func wait(_ message: String, file: StaticString = #filePath, line: UInt = #line,
                      _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail(message, file: file, line: line)
        throw AutomaticRoutingTestFailure.waitTimedOut
    }
}

private enum AutomaticRoutingTestFailure: Error { case waitTimedOut, unexpected }

@MainActor
private final class AutomaticRoutingFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ARCHi-AutomaticRouting-\(UUID().uuidString)")
    let local = AutomaticRoutingClient()
    let factory = AutomaticRoutingFactory()
    var cloud: AutomaticRoutingClient { factory.cloud }
    lazy var store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
        assistant: local, provider: .qwen,
        assistantFactory: { [factory] provider, model in factory.make(provider, model) })

    func drain() {
        store.cancelWork()
        store.disconnectAssistant(provider: .qwen)
        store.disconnectAssistant(provider: .codex)
        local.drain(); cloud.drain(); factory.replacements.forEach { $0.drain() }
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class AutomaticRoutingFactory {
    let cloud = AutomaticRoutingClient()
    private(set) var replacements: [AutomaticRoutingClient] = []
    func make(_ provider: AssistantProvider, _ model: String) -> AutomaticRoutingClient {
        if provider == .codex { return cloud }
        let client = AutomaticRoutingClient(); replacements.append(client); return client
    }
}

/// Deliberately delivers callbacks after cancellation. The production request
/// owner, not a cooperative mock transport, must prevent stale callbacks and external work.
@MainActor
private final class AutomaticRoutingClient: AssistantClient {
    struct Reply {
        let request: AssistantRequest
        let onEvent: @MainActor (AssistantEvent) -> Void
    }
    private(set) var connectCount = 0
    private(set) var replies: [Reply] = []
    private(set) var finishedConnections = Set<Int>()
    private(set) var finishedReplies = Set<Int>()
    private var connections: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var answers: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var draining = false

    func connect() async throws {
        let index = connectCount; connectCount += 1
        defer { finishedConnections.insert(index) }
        guard !draining else { throw AssistantFailure.stopped }
        try await withCheckedThrowingContinuation { connections[index] = $0 }
    }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        let index = replies.count; replies.append(Reply(request: request, onEvent: onEvent))
        defer { finishedReplies.insert(index) }
        guard !draining else { throw AssistantFailure.stopped }
        try await withCheckedThrowingContinuation { answers[index] = $0 }
    }
    func disconnect() {}
    func shutdown() async { disconnect() }
    func emit(_ index: Int, text: String) { replies[index].onEvent(.text(text)) }
    func resolveConnection(_ index: Int, result: Result<Void, any Error> = .success(())) {
        guard let continuation = connections.removeValue(forKey: index) else { XCTFail("No pending connection"); return }
        continuation.resume(with: result)
    }
    func resolveReply(_ index: Int, result: Result<Void, any Error> = .success(())) {
        guard let continuation = answers.removeValue(forKey: index) else { XCTFail("No pending reply"); return }
        continuation.resume(with: result)
    }
    func drain() {
        draining = true
        let pending = Array(connections.values) + Array(answers.values)
        connections.removeAll(); answers.removeAll()
        pending.forEach { $0.resume(throwing: AssistantFailure.stopped) }
    }
}
