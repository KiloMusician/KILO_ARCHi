import AppKit
import SwiftUI
import Testing
import XCTest
@testable import ARCHiDesktop

struct CompanionChatPlacementTests {
    @Test func prefersFullReadableSpaceToTheRightWithoutChangingTheCompanion() throws {
        let companion = CGRect(x: 500, y: 370, width: 128, height: 154)
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let layout = try #require(CompanionChatPlacement.layout(companion: companion, screens: [screen]))
        #expect(layout.edge == .leading)
        #expect(layout.frame.size == CompanionChatPlacement.preferredSize)
        #expect(layout.frame.minX == companion.maxX + CompanionChatPlacement.gap)
        #expect(screen.insetBy(dx: 8, dy: 8).contains(layout.frame))
        #expect(!layout.frame.intersects(companion))
        #expect(layout.tipOffset == layout.frame.maxY - companion.midY)
    }

    @Test func choosesLeftAtRightEdgeAndPointsTowardTheCharacter() throws {
        let companion = CGRect(x: 1280, y: 710, width: 128, height: 154)
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let layout = try #require(CompanionChatPlacement.layout(companion: companion, screens: [screen]))
        #expect(layout.edge == .trailing)
        #expect(layout.frame.maxX == companion.minX - CompanionChatPlacement.gap)
        #expect(screen.insetBy(dx: 8, dy: 8).contains(layout.frame))
        #expect(!layout.frame.intersects(companion))
        #expect(layout.tipOffset >= 30 && layout.tipOffset <= layout.frame.height - 30)
    }

    @Test func verticalGapsKeepTheBubbleOffTheCharacterOnNarrowDisplays() throws {
        let screen = CGRect(x: 0, y: 0, width: 700, height: 1100)
        for (companion, edge) in [(CGRect(x: 285, y: 60, width: 128, height: 154), CompanionChatEdge.bottom),
                                  (CGRect(x: 285, y: 850, width: 128, height: 154), .top)] {
            let layout = try #require(CompanionChatPlacement.layout(companion: companion, screens: [screen]))
            #expect(layout.edge == edge)
            #expect(screen.insetBy(dx: 8, dy: 8).contains(layout.frame))
            #expect(!layout.frame.intersects(companion))
            #expect(layout.tipOffset == companion.midX - layout.frame.minX)
        }
    }

    @Test func negativeAndStackedDisplayCoordinatesPreserveTranslatedLayout() throws {
        let companion = CGRect(x: 500, y: 370, width: 128, height: 154)
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let original = try #require(CompanionChatPlacement.layout(companion: companion, screens: [screen]))
        let translated = try #require(CompanionChatPlacement.layout(
            companion: companion.offsetBy(dx: -1700, dy: -1000),
            screens: [screen, screen.offsetBy(dx: -1700, dy: -1000)]))
        #expect(translated.frame == original.frame.offsetBy(dx: -1700, dy: -1000))
        #expect(translated.edge == original.edge)
        #expect(translated.tipOffset == original.tipOffset)
    }

    @Test func unavailableOrCrowdedScreensDeclineRatherThanCoverOrMoveTheCompanion() {
        let companion = CGRect(x: 160, y: 140, width: 128, height: 154)
        #expect(CompanionChatPlacement.layout(companion: companion, screens: []) == nil)
        #expect(CompanionChatPlacement.layout(companion: companion, screens: [.null, .infinite]) == nil)
        #expect(CompanionChatPlacement.layout(companion: companion,
            screens: [CGRect(x: 0, y: 0, width: 450, height: 450)]) == nil)
        #expect(CompanionChatPlacement.layout(companion: companion.offsetBy(dx: -2000, dy: 0),
            screens: [CGRect(x: 0, y: 0, width: 1440, height: 900)]) == nil)
        #expect(CompanionChatPlacement.layout(companion: .null,
            screens: [CGRect(x: 0, y: 0, width: 1440, height: 900)]) == nil)
    }

    @Test func pointerOutlineStaysInsideItsWindowOnEverySide() {
        let rect = CGRect(origin: .zero, size: CompanionChatPlacement.preferredSize)
        for edge in [CompanionChatEdge.leading, .trailing, .top, .bottom] {
            let shape = CompanionChatBubbleShape(edge: edge, tipOffset: 80)
            let path = shape.path(in: rect)
            #expect(path.boundingRect == rect)
            #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY)))
            #expect(!path.contains(.zero))
            let insideTip: CGPoint
            switch edge {
            case .leading: insideTip = CGPoint(x: 2, y: 80)
            case .trailing: insideTip = CGPoint(x: rect.maxX - 2, y: 80)
            case .top: insideTip = CGPoint(x: 80, y: 2)
            case .bottom: insideTip = CGPoint(x: 80, y: rect.maxY - 2)
            }
            #expect(path.contains(insideTip))
        }
    }
}

/// AppKit lifecycle is checked without showing windows or taking input focus.
/// Real click/drag/text-entry qualification belongs to native acceptance.
final class CompanionChatBubbleTests: XCTestCase {
    @MainActor
    func testPreparingAndRepositioningBubbleChangesNoDraftContextPreferenceOrConnection() throws {
        let fixture = ChatBubbleFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.share(text: "A local source.", name: "source.txt")
        store.prompt = "An unsent command-shaped request."
        store.setAssistantRoute(.automatic)
        let source = store.sourceRevision, placement = store.placementRevision
        let preferences = store.preferences, position = store.position, parentFrame = fixture.parent.frame
        XCTAssertTrue(fixture.bubble.prepare(screens: [fixture.screen]))
        XCTAssertEqual(fixture.parent.frame, parentFrame)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.sourceRevision, source)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.prompt, "An unsent command-shaped request.")
        XCTAssertEqual(store.route, .automatic)
        XCTAssertEqual(fixture.client.connectCount, 0)
        XCTAssertTrue(fixture.client.requests.isEmpty)
        XCTAssertFalse(fixture.bubble.window.isVisible)
        XCTAssertFalse(fixture.bubble.window.isKeyWindow)
        let first = fixture.bubble.window.frame
        fixture.parent.setFrameOrigin(CGPoint(x: 850, y: 300))
        let movedParent = fixture.parent.frame
        XCTAssertTrue(fixture.bubble.prepare(screens: [fixture.screen]))
        XCTAssertNotEqual(fixture.bubble.window.frame, first)
        XCTAssertEqual(fixture.parent.frame, movedParent)
        XCTAssertFalse(fixture.bubble.window.frame.intersects(movedParent))
        XCTAssertEqual(store.placementRevision, placement, "Only the companion owner publishes actual movement")
        XCTAssertEqual(fixture.client.connectCount, 0)
    }

    @MainActor
    func testDismissAndFullAssistantKeepSharedDraftRouteAndRevisionMode() throws {
        let fixture = ChatBubbleFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.share(text: "Original passage.", name: "draft.txt")
        store.selectText(range: NSRange(location: 0, length: 17), sourceRevision: store.sourceRevision)
        store.requestsRevision = true
        store.prompt = "Make it shorter."
        store.setAssistantRoute(.codex)
        var opened: [WorkspaceSection] = []
        store.onOpenWorkspace = { opened.append($0) }
        XCTAssertTrue(fixture.bubble.prepare(screens: [fixture.screen]))
        fixture.bubble.window.cancelOperation(nil)
        XCTAssertEqual(store.prompt, "Make it shorter.")
        XCTAssertEqual(store.route, .codex)
        XCTAssertTrue(store.requestsRevision)
        XCTAssertEqual(store.sharedText, "Original passage.")
        XCTAssertEqual(store.textSelection?.quote, "Original passage.")
        XCTAssertTrue(opened.isEmpty)
        fixture.bubble.openAssistant()
        XCTAssertEqual(opened, [.assistant])
        XCTAssertEqual(store.prompt, "Make it shorter.")
        XCTAssertTrue(store.requestsRevision)
        XCTAssertEqual(fixture.client.connectCount, 0)
        XCTAssertTrue(fixture.client.requests.isEmpty)
    }

    @MainActor
    func testLessonsHandoffDismissesBeforeOpeningEvenFromMemoryAndPreservesUnsentWork() throws {
        for startingSection in [WorkspaceSection.assistant, .memory] {
            let fixture = ChatBubbleFixture()
            defer { fixture.cleanUp() }
            let store = fixture.store
            store.beginLessonCorrection()
            var lesson = try XCTUnwrap(store.lessonDraft)
            lesson.topic = "launch review"
            lesson.text = "Use the reviewed project name."
            XCTAssertTrue(store.keepLesson(lesson))
            let saved = try Data(contentsOf: fixture.preferenceURL)
            store.share(text: "Original passage.", name: "draft.txt")
            store.selectText(range: NSRange(location: 0, length: 17), sourceRevision: store.sourceRevision)
            store.requestsRevision = true
            store.prompt = "Shorten this launch review."
            store.setAssistantRoute(.compare)
            store.preferences.tone = "Direct"
            store.section = startingSection
            let preferences = store.preferences, source = store.sourceRevision
            let placement = store.placementRevision, kept = store.keptLessons
            XCTAssertEqual(store.nextReplyLessons.count, 1)
            XCTAssertTrue(fixture.bubble.prepare(screens: [fixture.screen]))
            // A hidden parent/child relationship proves detachment without
            // showing the bubble or taking desktop input focus.
            fixture.parent.addChildWindow(fixture.bubble.window, ordered: .above)
            XCTAssertFalse(fixture.parent.isVisible)
            XCTAssertFalse(fixture.bubble.window.isVisible)
            XCTAssertTrue(fixture.bubble.window.parent === fixture.parent)
            var opened: [WorkspaceSection] = []
            store.onOpenWorkspace = {
                XCTAssertNil(fixture.bubble.window.parent, "Dismiss must precede workspace handoff")
                opened.append($0)
            }

            fixture.bubble.openLessons()

            XCTAssertEqual(opened, [.memory])
            XCTAssertEqual(store.section, .memory)
            XCTAssertNil(fixture.bubble.window.parent)
            XCTAssertNil(store.lessonDraft, "Inspecting lessons must not open a new correction")
            XCTAssertEqual(store.prompt, "Shorten this launch review.")
            XCTAssertEqual(store.route, .compare)
            XCTAssertTrue(store.requestsRevision)
            XCTAssertEqual(store.sharedText, "Original passage.")
            XCTAssertEqual(store.textSelection?.quote, "Original passage.")
            XCTAssertEqual(store.sourceRevision, source)
            XCTAssertEqual(store.placementRevision, placement)
            XCTAssertEqual(store.preferences, preferences)
            XCTAssertEqual(store.keptLessons, kept)
            XCTAssertEqual(try Data(contentsOf: fixture.preferenceURL), saved)
            XCTAssertEqual(fixture.client.connectCount + fixture.cloud.connectCount, 0)
            XCTAssertTrue(fixture.client.requests.isEmpty && fixture.cloud.requests.isEmpty)
            store.onOpenWorkspace = nil
        }
    }

    @MainActor
    func testSingleAndCompareCorrectionHandoffsUseCompletedOriginWithoutSavingOrSendingAgain() async throws {
        let cases: [(AssistantRoute, AssistantProvider)] = [
            (.local, .qwen), (.codex, .codex), (.compare, .qwen), (.compare, .codex)
        ]
        for (route, provider) in cases {
            let fixture = ChatBubbleFixture()
            defer { fixture.cleanUp() }
            let store = fixture.store
            store.setAssistantRoute(route)
            store.share(text: "Original passage.", name: "draft.txt")
            store.selectText(range: NSRange(location: 0, length: 17), sourceRevision: store.sourceRevision)
            store.prompt = "Prepare the launch review."
            store.connectAssistant()
            try await wait { store.connectionState == .ready }
            store.submit()
            try await wait { route.providers.allSatisfy { fixture.client(for: $0).requests.count == 1 } }
            for lane in route.providers {
                fixture.client(for: lane).emit("Synthetic completed answer for \(lane.name).")
                fixture.client(for: lane).finish()
            }
            try await wait { !store.isWorking }
            XCTAssertEqual(store.compareResults[provider]?.state, .complete)
            let originReceipt = try XCTUnwrap(store.compareResults[provider]?.receipt)
            let results = store.compareResults
            let localCalls = fixture.client.requests.count, cloudCalls = fixture.cloud.requests.count
            let connects = fixture.client.connectCount + fixture.cloud.connectCount
            store.prompt = "A different unsent question."
            store.requestsRevision = true
            let preferences = store.preferences, source = store.sourceRevision
            let placement = store.placementRevision
            store.section = .memory
            XCTAssertTrue(fixture.bubble.prepare(screens: [fixture.screen]))
            fixture.parent.addChildWindow(fixture.bubble.window, ordered: .above)
            XCTAssertFalse(fixture.bubble.window.isVisible)
            XCTAssertTrue(fixture.bubble.window.parent === fixture.parent)
            var opened: [WorkspaceSection] = []
            store.onOpenWorkspace = {
                XCTAssertNil(fixture.bubble.window.parent, "The draft event must dismiss even with Memory already selected")
                opened.append($0)
            }

            // Single replies and Compare invoke this same existing owner via
            // LessonReplyControls. The bubble only observes its draft event.
            store.beginLessonCorrection(for: provider)

            let draft = try XCTUnwrap(store.lessonDraft)
            XCTAssertEqual(draft.origin?.requestID, originReceipt.requestID)
            XCTAssertEqual(draft.origin?.inputDigest, originReceipt.inputDigest)
            XCTAssertEqual(draft.topic, "")
            XCTAssertEqual(draft.text, "", "An answer is not automatically copied into a reviewed lesson")
            XCTAssertNil(draft.source)
            XCTAssertEqual(opened, [.memory])
            XCTAssertNil(fixture.bubble.window.parent)
            XCTAssertFalse(fixture.bubble.window.isVisible)
            XCTAssertFalse(fixture.bubble.window.isKeyWindow)
            XCTAssertEqual(store.prompt, "A different unsent question.")
            XCTAssertEqual(store.route, route)
            XCTAssertTrue(store.requestsRevision)
            XCTAssertEqual(store.textSelection?.quote, "Original passage.")
            XCTAssertEqual(store.sourceRevision, source)
            XCTAssertEqual(store.placementRevision, placement)
            XCTAssertEqual(store.preferences, preferences)
            XCTAssertEqual(store.compareResults, results)
            XCTAssertTrue(store.keptLessons.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.preferenceURL.path))
            XCTAssertEqual(fixture.client.requests.count, localCalls)
            XCTAssertEqual(fixture.cloud.requests.count, cloudCalls)
            XCTAssertEqual(fixture.client.connectCount + fixture.cloud.connectCount, connects)
            store.onOpenWorkspace = nil
        }
    }

    @MainActor
    func testBubbleDismissDoesNotCancelOwnedRequestButStopStillFencesLateCallbacks() async throws {
        let fixture = ChatBubbleFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.setAssistantRoute(.automatic)
        store.prompt = "Help me plan this task."
        XCTAssertTrue(fixture.bubble.prepare(screens: [fixture.screen]))
        XCTAssertTrue(fixture.client.requests.isEmpty, "Opening is never Send")
        store.submit()
        try await wait { fixture.client.requests.count == 1 }
        XCTAssertEqual(fixture.client.requests[0].prompt, "Help me plan this task.")
        let receipt = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        fixture.bubble.dismiss()
        XCTAssertTrue(store.isWorking)
        XCTAssertEqual(store.compareResults[.qwen]?.receipt, receipt)
        XCTAssertEqual(store.prompt, "Help me plan this task.")
        XCTAssertTrue(fixture.bubble.prepare(screens: [fixture.screen]))
        fixture.bubble.openAssistant()
        XCTAssertTrue(store.isWorking)
        XCTAssertEqual(store.compareResults[.qwen]?.receipt?.requestID, receipt.requestID)
        store.cancelWork()
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.assistantActivity, .stopped)
        let result = store.compareResults
        fixture.client.emit("Late response after Stop")
        fixture.client.finish()
        await Task.yield()
        XCTAssertEqual(store.compareResults, result)
        XCTAssertNil(store.compareResults[.codex])
    }

    @MainActor
    func testMinimumBubbleRenderKeepsSizeWithDisconnectedCompareAndLongDraft() async throws {
        try await renderMinimumBubble(voiceReview: false)
    }

    @MainActor
    func testMinimumBubbleVoiceReviewRenderKeepsDraftAndSendSpace() async throws {
        try await renderMinimumBubble(voiceReview: true)
    }

    @MainActor
    func testMinimumBubbleRecordingRenderKeepsFinishAndCancelSpace() async throws {
        try await renderMinimumBubble(voiceReview: false, recording: true)
    }

    @MainActor
    private func renderMinimumBubble(voiceReview: Bool, recording: Bool = false) async throws {
        let capture = ChatBubbleVoiceCapture()
        let voice = VoiceInputController(service: capture)
        let fixture = ChatBubbleFixture(voiceInput: voice)
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.setAssistantRoute(.compare)
        store.prompt = "First draft line.\nSecond draft line.\nThird draft line."
        store.share(text: "A deliberately shared synthetic document for layout.",
                    name: "a-long-shared-document-name-for-the-native-layout-check.txt")
        store.status = "This is a long local connection or request error. Nothing has been sent; your draft remains available."
        if voiceReview || recording {
            store.beginVoiceInput(from: .bubble)
            for _ in 0..<10 where voice.phase == .authorizing { await Task.yield() }
            XCTAssertEqual(voice.phase, .recording)
            if recording { capture.emit(.partial("Please help me plan a short drawing session…")) }
            else {
                capture.emit(.final("Please help me plan a short drawing session. Start with a few choices, then let me decide which one to explore. This is synthetic candidate text for the layout check; it has not been added to my typed draft or sent to a model."))
            }
            XCTAssertEqual(voice.phase, recording ? .recording : .review)
        }
        let size = CompanionChatPlacement.minimumSize
        let layout = CompanionChatLayout(frame: CGRect(origin: .zero, size: size), edge: .leading, tipOffset: 100)
        let hosting = NSHostingView(rootView: CompanionChatBubble(store: store, layout: layout,
            focusRequest: 0, dismiss: {}, openAssistant: {}, openLessons: {}))
        let panel = NSPanel(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        defer { panel.contentView = nil; panel.close() }
        panel.setContentSize(size)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        hosting.layoutSubtreeIfNeeded()
        // fittingSize is the unconstrained ideal size, not the minimum layout.
        // Hidden SwiftUI views do not expose native AX children, so click/AX
        // reachability is qualified separately in the real desktop app.
        XCTAssertEqual(hosting.bounds.size, size)
        XCTAssertEqual(panel.frame.size, size)
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertEqual(fixture.client.connectCount, 0)
        XCTAssertTrue(fixture.client.requests.isEmpty)
        XCTAssertEqual(store.prompt, "First draft line.\nSecond draft line.\nThird draft line.")
        XCTAssertEqual(capture.starts, voiceReview || recording ? 1 : 0)
        if let path = ProcessInfo.processInfo.environment["ARCHI_CHAT_LAYOUT_DIR"] {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let image = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: image)
            let name = recording ? "minimum-bubble-recording"
                : voiceReview ? "minimum-bubble-voice-review" : "minimum-bubble-compare"
            try XCTUnwrap(image.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent(name + ".png"))
            let proof: [String: Any] = ["requested": NSStringFromSize(size),
                "actualWindow": NSStringFromRect(panel.frame), "fittingSize": NSStringFromSize(hosting.fittingSize),
                "windowShown": panel.isVisible, "providerCalls": fixture.client.connectCount + fixture.client.requests.count,
                "voiceFixture": voiceReview || recording, "realAudioCapture": false,
                "controlReachability": "Visual inspection only; native AX acceptance is separate."]
            try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent(name + "-layout.json"))
        }
    }

    @MainActor
    func testHiddenParentOrHiddenCompanionCannotPresentOrConnect() {
        let fixture = ChatBubbleFixture()
        defer { fixture.cleanUp() }
        XCTAssertFalse(fixture.bubble.show())
        fixture.store.isVisible = false
        XCTAssertFalse(fixture.bubble.show())
        XCTAssertFalse(fixture.bubble.window.isVisible)
        XCTAssertEqual(fixture.client.connectCount, 0)
        XCTAssertTrue(fixture.client.requests.isEmpty)
    }

    @MainActor
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Synthetic request did not start")
        throw ChatBubbleTestError.timedOut
    }
}

private enum ChatBubbleTestError: Error { case timedOut }

@MainActor
private final class ChatBubbleFixture {
    let voiceInput: VoiceInputController?
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ARCHiChatBubble-\(UUID().uuidString)")
    var preferenceURL: URL { directory.appendingPathComponent("preferences.json") }
    let client = ChatBubbleClient()
    let cloud = ChatBubbleClient()
    let parent: NSPanel
    lazy var store = CompanionStore(preferenceURL: preferenceURL, assistant: client,
        assistantFactory: { [client, cloud] provider, _ in provider == .qwen ? client : cloud }, allowsPlay: false,
        voiceInput: voiceInput)
    lazy var bubble = CompanionChatBubbleController(store: store, companionWindow: parent)
    init(voiceInput: VoiceInputController? = nil) {
        self.voiceInput = voiceInput
        _ = NSApplication.shared
        parent = NSPanel(contentRect: CGRect(x: 550, y: 360, width: 128, height: 154),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
    }
    func cleanUp() {
        bubble.dismiss(); bubble.window.close(); parent.close()
        store.onOpenWorkspace = nil
        store.cancelWork(); client.finish(); cloud.finish()
        try? FileManager.default.removeItem(at: directory)
    }
    func client(for provider: AssistantProvider) -> ChatBubbleClient { provider == .qwen ? client : cloud }
}

@MainActor
private final class ChatBubbleVoiceCapture: VoiceCaptureService {
    private var observer: (@MainActor (VoiceCaptureEvent) -> Void)?
    private(set) var starts = 0
    func start(onEvent: @escaping @MainActor (VoiceCaptureEvent) -> Void) async throws {
        starts += 1
        observer = onEvent
    }
    func finish() {}
    func cancel() {}
    func emit(_ event: VoiceCaptureEvent) { observer?(event) }
}

@MainActor
private final class ChatBubbleClient: AssistantClient {
    private(set) var connectCount = 0
    private(set) var requests: [AssistantRequest] = []
    private var observer: (@MainActor (AssistantEvent) -> Void)?
    private var continuation: CheckedContinuation<Void, any Error>?
    func connect() async throws { connectCount += 1 }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requests.append(request); observer = onEvent
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func emit(_ text: String) { observer?(.text(text)) }
    func finish() { let pending = continuation; continuation = nil; pending?.resume() }
    func disconnect() {}
}
