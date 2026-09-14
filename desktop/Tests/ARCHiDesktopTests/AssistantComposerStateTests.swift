import XCTest
@testable import ARCHiDesktop

final class AssistantComposerStateTests: XCTestCase {
    @MainActor
    func testRecoveryFollowsRouteDraftAndSelectionWithoutStartingARequest() async throws {
        let client = ComposerNoCalls()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("composer-state-\(UUID()).json")
        let store = CompanionStore(preferenceURL: url, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false)
        store.prompt = "Help with this thought."
        XCTAssertEqual(AssistantComposerState(store: store).blockedReason, "Connect Qwen to send.")
        store.setAssistantRoute(.compare)
        XCTAssertEqual(AssistantComposerState(store: store).blockedReason, "Connect both assistants to send.")
        store.setAssistantRoute(.automatic)
        XCTAssertTrue(AssistantComposerState(store: store).canSend)
        XCTAssertTrue(AssistantComposerState(store: store).sendDisclosure.contains("Your message stays on this Mac"))
        XCTAssertFalse(AssistantComposerState(store: store).sendDisclosure.contains("full copy"))

        store.prompt = " \n "
        XCTAssertEqual(AssistantComposerState(store: store).blockedReason, "Write a message to send.")
        store.requestsRevision = true
        XCTAssertEqual(AssistantComposerState(store: store).blockedReason, "Select the passage to revise.")
        store.share(text: "A selected passage. Another sentence.", name: "synthetic.txt")
        store.requestsRevision = true
        store.prompt = "Make it clearer."
        store.selectText(range: NSRange(location: 0, length: 19), sourceRevision: store.sourceRevision)
        XCTAssertTrue(AssistantComposerState(store: store).canSend)
        XCTAssertTrue(AssistantComposerState(store: store).sendDisclosure.contains("full copy and selected passage"))
        store.clearTextSelection()
        XCTAssertFalse(AssistantComposerState(store: store).canSend)
        XCTAssertEqual(AssistantComposerState(store: store).sendDisclosure, "Select the passage to revise.")
        XCTAssertEqual(store.prompt, "Make it clearer.")
        XCTAssertEqual(store.sharedText, "A selected passage. Another sentence.")
        XCTAssertEqual(client.calls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        await store.shutdownAssistant()
    }

    @MainActor
    func testDictationAndShutdownExplainWhyAnOtherwiseReadyDraftCannotSend() async throws {
        let service = ComposerVoiceService()
        let voice = VoiceInputController(service: service)
        let client = ComposerNoCalls()
        let store = CompanionStore(preferenceURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("composer-voice-\(UUID()).json"), assistant: client,
            allowsPlay: false, voiceInput: voice)
        store.setAssistantRoute(.automatic)
        store.prompt = "A draft to keep."
        XCTAssertTrue(AssistantComposerState(store: store).canSend)
        voice.start(from: .assistant)
        XCTAssertFalse(AssistantComposerState(store: store).canSend)
        XCTAssertEqual(AssistantComposerState(store: store).sendDisclosure, "Finish or cancel dictation before sending.")
        voice.cancel()
        XCTAssertTrue(AssistantComposerState(store: store).canSend)
        await store.shutdownAssistant()
        XCTAssertFalse(AssistantComposerState(store: store).canSend)
        XCTAssertEqual(AssistantComposerState(store: store).sendDisclosure, "ARCHi is closing.")
        XCTAssertEqual(store.prompt, "A draft to keep.")
        XCTAssertEqual(client.calls, 0)
    }
}

@MainActor
private final class ComposerNoCalls: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.unavailable }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.unavailable
    }
    func disconnect() {}
}

@MainActor
private final class ComposerVoiceService: VoiceCaptureService {
    func start(onEvent: @escaping @MainActor (VoiceCaptureEvent) -> Void) async throws {}
    func finish() {}
    func cancel() {}
}
