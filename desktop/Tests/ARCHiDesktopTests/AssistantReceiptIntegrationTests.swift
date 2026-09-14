import XCTest
@testable import ARCHiDesktop

final class AssistantReceiptIntegrationTests: XCTestCase {
    @MainActor
    func testCompletedLaneKeepsItsAccountingWhenPreferencesAndInspectorReset() async throws {
        let fixture = try ReceiptStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.share(text: "The fixture launch is Friday.", name: "notes.txt")
        store.prompt = "Explain the launch."
        try await connect(store)
        store.submit()
        try await waitUntil { !store.isWorking }
        let captured = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        let invocation = try XCTUnwrap(captured.localInvocationReceipts?.first)
        let evidence = try XCTUnwrap(captured.evidence)
        XCTAssertEqual(captured.state, .complete)
        XCTAssertEqual(invocation.outcome, .completed)
        XCTAssertEqual(invocation.metrics, ReceiptRoleClient.metrics)
        XCTAssertEqual(evidence.reasoningSourceIDsDispatched, ["current-question", "shared-copy"])
        XCTAssertEqual(evidence.sourceIDsCited, ["current-question", "shared-copy"])
        XCTAssertEqual(captured.localInvocationReceipts, store.hamptonSnapshot.invocations)
        XCTAssertFalse(String(describing: evidence).contains("fixture launch"))

        store.preferences.tone = "Warm"
        store.preferences.replyLength = 0.8
        store.section = .advanced
        store.clearSessionContext()
        let retained = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        XCTAssertEqual(retained.localInvocationReceipts, captured.localInvocationReceipts)
        XCTAssertEqual(retained.evidence, evidence)
        XCTAssertEqual(retained.settings, captured.settings)
        XCTAssertEqual(retained.localLessonOmissions, captured.localLessonOmissions)
        XCTAssertEqual(retained.state, .cancelled, "Reset revokes the visible answer while its receipt keeps the original accounting")
        XCTAssertTrue(store.hamptonSnapshot.invocations.isEmpty)
        XCTAssertNil(store.hamptonSnapshot.evidence)
        XCTAssertEqual(fixture.reasoner.requests.count, 1)
        XCTAssertTrue(fixture.selector.requests.isEmpty)
        XCTAssertTrue(fixture.codex.requests.isEmpty)
    }

    @MainActor
    func testStopCapturesAttemptAndLateCompletionCannotRestoreMetricsOrCitations() async throws {
        let fixture = try ReceiptStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        fixture.reasoner.hold = true
        store.prompt = "Keep this pending."
        try await connect(store)
        store.submit()
        try await waitUntil { fixture.reasoner.isPending }
        XCTAssertTrue(store.isWorking)
        store.cancelWork()
        let stopped = try XCTUnwrap(store.compareResults[.qwen])
        let receipt = try XCTUnwrap(stopped.receipt)
        let invocation = try XCTUnwrap(receipt.localInvocationReceipts?.first)
        XCTAssertEqual(invocation.outcome, .cancelled)
        XCTAssertNil(invocation.metrics)
        XCTAssertEqual(receipt.localInvocations, [.reasoning])
        XCTAssertEqual(receipt.evidence?.reasoningSourceIDsDispatched, ["current-question"])
        XCTAssertTrue(receipt.evidence?.sourceIDsCited.isEmpty == true)
        XCTAssertEqual(receipt.admissionOutcome?.status, .stopped)
        let status = store.status, reply = store.reply, inspector = store.hamptonSnapshot

        fixture.reasoner.resolve()
        try await waitUntil { fixture.reasoner.finished == 1 }
        await Task.yield()
        XCTAssertEqual(store.compareResults[.qwen], stopped)
        XCTAssertEqual(store.hamptonSnapshot, inspector)
        XCTAssertEqual(store.status, status)
        XCTAssertEqual(store.reply, reply)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(fixture.reasoner.requests.count, 1)
    }

    @MainActor
    func testExplicitCompareKeepsLocalAccountingAndLessonOmissionsOutOfCodex() async throws {
        let lesson = KeptLesson(topic: "drawing", text: "Private local lesson.", createdAt: ReceiptStoreFixture.instant)
        let fixture = try ReceiptStoreFixture(lessons: [lesson])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.setAssistantRoute(.compare)
        store.prompt = "Help with planning."
        try await connect(store)
        store.submit()
        try await waitUntil { !store.isWorking }
        let local = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        let external = try XCTUnwrap(store.compareResults[.codex]?.receipt)
        XCTAssertEqual(local.state, .complete)
        XCTAssertEqual(external.state, .complete)
        XCTAssertNotNil(local.localInvocationReceipts?.first?.metrics)
        XCTAssertEqual(local.localLessonOmissions.map(\.reason), [.unmatched])
        XCTAssertNil(external.localInvocationReceipts)
        XCTAssertNil(external.localInvocations)
        XCTAssertNil(external.evidence)
        XCTAssertTrue(external.localLessonOmissions.isEmpty)
        XCTAssertTrue(external.localLessons.isEmpty)
        let externalRequest = try XCTUnwrap(fixture.codex.requests.first)
        XCTAssertTrue(externalRequest.localLessons.isEmpty)
        XCTAssertFalse(externalRequest.input.contains(lesson.text))
        XCTAssertEqual(fixture.codex.requests.count, 1)
        XCTAssertEqual(fixture.reasoner.requests.count, 1)
        XCTAssertTrue(fixture.selector.requests.isEmpty)
    }

    @MainActor
    func testSendTimeLessonOmissionsUseClockAndLeaveActualProviderInputUnchanged() async throws {
        let now = ReceiptStoreFixture.instant
        let source = LessonSource(name: "notes.txt", digest: LessonSource.digest(of: "Current source."))
        let included = KeptLesson(topic: "planning", text: "Included local guidance.", source: source,
            createdAt: now.addingTimeInterval(-120), expiresAt: now.addingTimeInterval(60))
        let expired = KeptLesson(topic: "planning", text: "Expired private guidance.",
            createdAt: now.addingTimeInterval(-120), expiresAt: now.addingTimeInterval(-60))
        let otherSource = KeptLesson(topic: "planning", text: "Other-source private guidance.",
            source: LessonSource(name: "other.txt", digest: LessonSource.digest(of: "Different source.")), createdAt: now)
        let unmatched = KeptLesson(topic: "drawing", text: "Unmatched private guidance.", createdAt: now)
        let lessons = [included, expired, otherSource, unmatched]
        let fixture = try ReceiptStoreFixture(lessons: lessons)
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.share(text: "Current source.", name: "notes.txt")
        store.prompt = "Help with planning today."
        try await connect(store)
        store.submit()
        try await waitUntil { !store.isWorking }
        let receipt = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        let includedID = LessonSnapshot(lesson: included).modelID
        XCTAssertEqual(receipt.localLessons.map(\.modelID), [includedID])
        XCTAssertEqual(receipt.localLessonOmissions.map(\.reason), [.expired, .otherSource, .unmatched])
        XCTAssertEqual(receipt.localLessonOmissions.flatMap(\.ids), lessons.dropFirst().map { LessonSnapshot(lesson: $0).modelID })
        XCTAssertEqual(receipt.evidence?.reasoningMemoryIDsDispatched, [includedID])
        XCTAssertEqual(receipt.evidence?.memoryIDsCited, [includedID])
        XCTAssertEqual(receipt.evidence?.omissions.filter { $0.kind == .lessons }, receipt.localLessonOmissions)
        let actual = try XCTUnwrap(fixture.reasoner.requests.first)
        XCTAssertEqual(ReceiptRoleClient.ids(actual, "memories"), [includedID])
        let encodedInput = String(decoding: try JSONEncoder().encode(actual.input), as: UTF8.self)
        XCTAssertTrue(encodedInput.contains(included.text))
        for omitted in lessons.dropFirst() {
            XCTAssertFalse(encodedInput.contains(omitted.text))
            XCTAssertFalse(String(describing: receipt.evidence).contains(omitted.text))
        }
        XCTAssertEqual(store.keptLessons, lessons)
        XCTAssertEqual(fixture.reasoner.requests.count, 1)
        XCTAssertTrue(fixture.selector.requests.isEmpty)

        fixture.clock.now = now.addingTimeInterval(120)
        XCTAssertEqual(store.compareResults[.qwen]?.receipt, receipt,
                       "Later expiry must not rewrite the completed request's evidence accounting")
    }

    @MainActor
    private func connect(_ store: CompanionStore) async throws {
        store.connectAssistant()
        try await waitUntil { store.connectionState == .ready }
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The in-process receipt fixture did not finish within its bounded wait")
        throw ReceiptFixtureFailure.waitTimedOut
    }
}

private enum ReceiptFixtureFailure: Error { case waitTimedOut }

@MainActor
private final class ReceiptFixtureClock {
    var now = ReceiptStoreFixture.instant
}

@MainActor
private final class ReceiptStoreFixture {
    static let instant = Date(timeIntervalSince1970: 1_500_000_000)
    let clock = ReceiptFixtureClock()
    let reasoner = ReceiptRoleClient()
    let selector = ReceiptRoleClient()
    let codex = ReceiptCodexClient()
    let assistant: HamptonReasonsAssistant
    let store: CompanionStore
    let directory: URL

    init(lessons: [KeptLesson] = []) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-receipt-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let profile = directory.appendingPathComponent("preferences.json")
        try NativePreferenceDocument(lessons: lessons).encoded().write(to: profile)
        assistant = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
        let local = assistant, external = codex, fixtureClock = clock
        store = CompanionStore(preferenceURL: profile, assistant: local,
            assistantFactory: { provider, _ in
                if provider == .qwen { return local }
                return external
            },
            wallClock: { fixtureClock.now }, allowsPlay: false)
    }

    func cleanUp() {
        store.disconnectAssistant(provider: .qwen)
        store.disconnectAssistant(provider: .codex)
        reasoner.drain(); selector.drain()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Deliberately returns a valid terminal after Stop so the two ownership fences
/// must prevent that late result from becoming an answer or accounting update.
@MainActor
private final class ReceiptRoleClient: LocalRoleClient {
    static let metrics = LocalInferenceMetrics(inputTokens: 44, outputTokens: 11, totalNanoseconds: 12_000_000)
    var hold = false
    private(set) var requests: [LocalRoleRequest] = []
    private(set) var finished = 0
    private var pending: CheckedContinuation<Void, Error>?
    var isPending: Bool { pending != nil }

    func connect() async throws {}
    func disconnect() {}
    func shutdown() async {}

    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        requests.append(request)
        defer { finished += 1 }
        if hold { try await withCheckedThrowingContinuation { pending = $0 } }
        let payload: JSONValue
        switch request.role {
        case .reasoning:
            payload = .object(["requestID": .string(request.id), "schema": .string("archi-reason-proposal/v1"),
                "kind": .string("ANSWER"), "answer": .string("Receipt fixture answer."), "uncertainty": .string(""),
                "sourceIDs": .array(Self.ids(request, "sources").map(JSONValue.string)),
                "memoryIDs": .array(Self.ids(request, "memories").map(JSONValue.string))])
        case .memorySelection:
            payload = .object(["requestID": .string(request.id), "schema": .string("archi-session-selection/v1"),
                "candidateIDs": .array([])])
        case .memoryReminder:
            payload = .object(["requestID": .string(request.id), "schema": .string("archi-session-reminder/v1"),
                "decision": .string("NONE"), "memoryIDs": .array([])])
        }
        return LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self),
            model: QwenModelMetadata(name: "receipt-fixture", family: "fixture", parameterSize: "fixture",
                quantization: "fixture", digest: String(repeating: "a", count: 64)),
            elapsedMilliseconds: 12, metrics: Self.metrics)
    }

    static func ids(_ request: LocalRoleRequest, _ key: String) -> [String] {
        request.input[key]?.array?.compactMap { $0["id"]?.string } ?? []
    }

    func resolve() { let continuation = pending; pending = nil; continuation?.resume() }
    func drain() { let continuation = pending; pending = nil; continuation?.resume(throwing: QwenFailure.stopped) }
}

@MainActor
private final class ReceiptCodexClient: AssistantClient {
    private(set) var requests: [AssistantRequest] = []
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requests.append(request)
        onEvent(.text("External receipt fixture answer."))
    }
}
