import XCTest
@testable import ARCHiDesktop

final class KinLightAbilityTests: XCTestCase {
    func testRulesPrioritizeActualWorkAndDistinguishExplicitPreviews() {
        let expected: [(AssistantActivity, KinLightMode)] = [
            (.idle, .rest), (.stopped, .rest), (.working, .orbit),
            (.responding, .pulse), (.ready, .delight), (.failed, .hold)
        ]
        for (activity, mode) in expected {
            let actual = resolve(activity)
            XCTAssertEqual(actual.mode, mode)
            XCTAssertFalse(actual.isPreview)
            XCTAssertEqual(resolve(activity, focus: true, preview: .core).mode, .focus)
        }
        for activity in [AssistantActivity.idle, .ready, .failed, .stopped] {
            let preview = resolve(activity, preview: .focus)
            XCTAssertEqual(preview.mode, .focus)
            XCTAssertTrue(preview.isPreview)
            XCTAssertTrue(preview.label.hasPrefix("Preview:"))
        }
        XCTAssertEqual(resolve(.working, preview: .hold).mode, .orbit)
        XCTAssertEqual(resolve(.responding, preview: .hold).mode, .pulse)
    }

    func testInactiveHiddenAndQuietExpressionsAreAlwaysResting() {
        for activity in AssistantActivity.allCases {
            for preview in KinLightMode.allCases {
                for flags in [(false, false, true), (true, true, true), (true, false, false)] {
                    XCTAssertEqual(KinLightRules.resolve(activity: activity, hasFreshFocus: true, preview: preview,
                        visible: flags.0, quiet: flags.1, activeKin: flags.2), .resting)
                }
            }
        }
    }

    @MainActor
    func testPreviewExpiryReplacementAndMemoryStaySeparate() throws {
        let f = try KinLightFixture(); defer { f.cleanup() }
        f.store.beginLessonCorrection()
        f.store.lessonDraft?.topic = "planning"
        f.store.lessonDraft?.text = "Start with three concise steps."
        XCTAssertTrue(f.store.keepLesson(try XCTUnwrap(f.store.lessonDraft)))
        let bytes = try Data(contentsOf: f.url)
        let individual = f.store.activeQiMon, lessons = f.store.keptLessons
        let preferences = f.store.preferences, history = f.store.evolution.history
        let context = f.store.contextTicket(), placement = f.store.placementRevision
        XCTAssertTrue(f.store.previewKinLight(.focus))
        let first = try XCTUnwrap(f.store.kinLightPreview)
        XCTAssertEqual(f.store.kinLightExpression, KinLightExpression(mode: .focus, isPreview: true))
        XCTAssertFalse(f.store.hasFreshKinFocus)
        XCTAssertNil(f.store.spatialPreview, "A light preview does not observe or highlight a passage")
        XCTAssertTrue(f.store.previewKinLight(.core))
        let second = try XCTUnwrap(f.store.kinLightPreview)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(f.store.validateKinLightPreview(id: first.id))
        XCTAssertEqual(f.store.kinLightPreview?.id, second.id)
        f.clock.now = second.startedAt + 4.999
        XCTAssertTrue(f.store.validateKinLightPreview(id: second.id))
        f.clock.now = second.startedAt + 5
        XCTAssertEqual(f.store.kinLightExpression, .resting)
        XCTAssertFalse(f.store.validateKinLightPreview(id: second.id))
        XCTAssertNil(f.store.kinLightPreview)
        XCTAssertEqual(f.store.preferences, preferences)
        XCTAssertEqual(f.store.activeQiMon, individual)
        XCTAssertEqual(f.store.presentationForm, .kinSeed)
        XCTAssertEqual(f.store.keptLessons, lessons)
        XCTAssertEqual(f.store.evolution.history, history)
        XCTAssertEqual(f.store.contextTicket(), context)
        XCTAssertEqual(f.store.placementRevision, placement)
        XCTAssertEqual(try Data(contentsOf: f.url), bytes)
        XCTAssertEqual(f.local.connects + f.cloud.connects, 0)
        XCTAssertTrue(f.local.callbacks.isEmpty && f.cloud.callbacks.isEmpty)
    }

    @MainActor
    func testStopContextChangesAndInvalidClockCannotReviveAnOldPreview() throws {
        let changes: [(KinLightFixture) -> Void] = [
            { $0.store.cancelWork() }, { $0.store.share(text: "Changed note", name: "new.txt") },
            { $0.store.placed(at: CGPoint(x: 50, y: 80)) }, { $0.store.hideCompanion() },
            { $0.store.preferences.quiet = true }, { $0.store.observeQiMonJourney(nil) },
            { $0.clock.now = .nan }, { $0.clock.now = .infinity }, { $0.clock.now = 9 }
        ]
        for change in changes {
            let f = try KinLightFixture(); defer { f.cleanup() }
            XCTAssertTrue(f.store.previewKinLight(.orbit))
            let id = try XCTUnwrap(f.store.kinLightPreview).id
            change(f)
            XCTAssertEqual(f.store.kinLightExpression, .resting)
            XCTAssertFalse(f.store.validateKinLightPreview(id: id))
            XCTAssertNil(f.store.kinLightPreview)
            XCTAssertEqual(f.store.keptQiMon?.currentBody, .kinSeed)
            XCTAssertTrue(f.local.callbacks.isEmpty && f.cloud.callbacks.isEmpty)
        }
    }

    @MainActor
    func testAccessibilityUsesIncomingQuietPreferencesBeforeStorePublication() throws {
        let f = try KinLightFixture(); defer { f.cleanup() }
        XCTAssertTrue(f.store.previewKinLight(.pulse))
        let preview = try XCTUnwrap(f.store.kinLightPreview)
        let before = f.store.assistantAccessibilityValue
        var incoming = f.store.preferences
        incoming.quiet = true
        let value = f.store.assistantAccessibilityValue(for: incoming)
        XCTAssertTrue(value.hasSuffix(". Light expression: " + KinLightExpression.resting.label))
        XCTAssertFalse(value.contains("Preview:"))
        XCTAssertNotEqual(value, before)
        XCTAssertFalse(f.store.preferences.quiet, "The incoming preference must be evaluated without mutating the store")
        XCTAssertEqual(f.store.kinLightPreview?.id, preview.id)
        XCTAssertEqual(f.store.kinLightExpression, KinLightExpression(mode: .pulse, isPreview: true))
    }

    @MainActor
    func testQuietAndHideImmediatelyRetirePreviewWithoutAValidationCall() throws {
        for hide in [false, true] {
            let f = try KinLightFixture(); defer { f.cleanup() }
            XCTAssertTrue(f.store.previewKinLight(.pulse))
            XCTAssertNotNil(f.store.kinLightPreview)
            if hide { f.store.hideCompanion() }
            else { f.store.preferences.quiet = true }
            XCTAssertNil(f.store.kinLightPreview, "Retire the preview immediately, before any validator is called")
            XCTAssertEqual(f.store.kinLightExpression, .resting)
            if hide { f.store.showCompanion() }
            else { f.store.preferences.quiet = false }
            XCTAssertNil(f.store.kinLightPreview)
            XCTAssertEqual(f.store.kinLightExpression, .resting, "Showing KIN again cannot revive the old preview")
        }
    }

    @MainActor
    func testFocusRequiresFreshObservedGeometryAndNeverComesFromTheLightPreview() throws {
        let f = try KinLightFixture(); defer { f.cleanup() }
        f.store.share(text: "A useful passage. Another sentence.", name: "focus.txt")
        f.store.selectText(range: NSRange(location: 0, length: 17), sourceRevision: f.store.sourceRevision)
        let selection = try XCTUnwrap(f.store.textSelection)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let geometry = SelectedPassageGeometry(selection: selection,
            rects: [CGRect(x: 300, y: 500, width: 220, height: 20)],
            viewport: CGRect(x: 280, y: 300, width: 340, height: 300),
            windowFrame: CGRect(x: 200, y: 100, width: 1000, height: 700),
            windowNumber: 12, screenID: 1, screenFrame: screen)
        let environment = SpatialEnvironment(companionFrame: CGRect(x: 360, y: 450, width: 128, height: 154),
            displays: [SpatialDisplay(id: 1, frame: screen, visibleFrame: screen)])
        var observedGeometry: SelectedPassageGeometry? = geometry
        f.store.onObserveSelectedPassage = { observedGeometry }
        f.store.onObserveSpatialEnvironment = { environment }
        XCTAssertTrue(f.store.previewKinLight(.focus))
        XCTAssertFalse(f.store.hasFreshKinFocus)
        XCTAssertTrue(f.store.kinLightExpression.isPreview)
        f.store.previewPlacement()
        XCTAssertNotNil(f.store.spatialPreview)
        XCTAssertTrue(f.store.hasFreshKinFocus)
        XCTAssertEqual(f.store.kinLightExpression, KinLightExpression(mode: .focus))
        XCTAssertNil(f.store.kinLightPreview)
        XCTAssertFalse(f.store.previewKinLight(.core))
        observedGeometry = nil
        XCTAssertFalse(f.store.hasFreshKinFocus)
        XCTAssertEqual(f.store.kinLightExpression, .resting,
            "A no-longer-observed passage cannot keep the focus expression alive")
        observedGeometry = geometry
        f.clock.now += 30
        XCTAssertFalse(f.store.hasFreshKinFocus)
        XCTAssertEqual(f.store.kinLightExpression, .resting)
        XCTAssertEqual(f.store.presentationForm, .kinSeed)
        XCTAssertTrue(f.local.callbacks.isEmpty && f.cloud.callbacks.isEmpty)
    }

    @MainActor
    func testThemePreviewIsManualAndDoesNotWriteMemoryOrStartModels() throws {
        let f = try KinLightFixture(); defer { f.cleanup() }
        XCTAssertFalse(f.store.canPreviewHarmonyTheme)
        f.store.previewHarmonyTheme()
        XCTAssertNil(f.store.harmonyThemeRequest)
        f.store.preferences.musicalCues = true
        f.store.preferences.musicalVolume = 0.35
        XCTAssertTrue(f.store.canPreviewHarmonyTheme)
        XCTAssertNil(f.store.harmonyThemeRequest, "Enabling musical cues must never start the theme")
        f.store.beginLessonCorrection()
        f.store.lessonDraft?.topic = "planning"
        f.store.lessonDraft?.text = "Offer a brief first step."
        XCTAssertTrue(f.store.keepLesson(try XCTUnwrap(f.store.lessonDraft)))
        let bytes = try Data(contentsOf: f.url)
        let preferences = f.store.preferences, lessons = f.store.keptLessons
        let identity = f.store.activeQiMon, history = f.store.evolution.history
        let ticket = f.store.contextTicket(), placement = f.store.placementRevision
        XCTAssertTrue(f.store.previewKinLight(.core))
        f.store.previewHarmonyTheme()
        let first = try XCTUnwrap(f.store.harmonyThemeRequest)
        XCTAssertNil(f.store.kinLightPreview, "The manual theme preempts the shorter light preview")
        f.store.previewHarmonyTheme()
        XCTAssertNotEqual(f.store.harmonyThemeRequest, first, "A deliberate replay owns a new request")
        f.store.stopHarmonyTheme()
        XCTAssertNil(f.store.harmonyThemeRequest)
        XCTAssertEqual(f.store.preferences, preferences)
        XCTAssertEqual(f.store.keptLessons, lessons)
        XCTAssertEqual(f.store.activeQiMon, identity)
        XCTAssertEqual(f.store.evolution.history, history)
        XCTAssertEqual(f.store.contextTicket(), ticket)
        XCTAssertEqual(f.store.placementRevision, placement)
        XCTAssertEqual(try Data(contentsOf: f.url), bytes)
        XCTAssertEqual(f.local.connects + f.cloud.connects, 0)
        XCTAssertTrue(f.local.callbacks.isEmpty && f.cloud.callbacks.isEmpty)
    }

    @MainActor
    func testThemeRequestIsRetiredByNewLightStopFocusSourceQuietMuteAndHide() throws {
        let changes: [(CompanionStore) -> Void] = [
            { _ = $0.previewKinLight(.pulse) }, { $0.cancelWork() },
            { $0.previewPlacement() }, { $0.share(text: "New task", name: "new.txt") },
            { $0.preferences.quiet = true }, { $0.preferences.musicalVolume = 0 },
            { $0.preferences.musicalCues = false }, { $0.hideCompanion() }
        ]
        for change in changes {
            let f = try KinLightFixture(); defer { f.cleanup() }
            f.store.preferences.musicalCues = true
            f.store.previewHarmonyTheme()
            XCTAssertNotNil(f.store.harmonyThemeRequest)
            let bytes = try Data(contentsOf: f.url)
            let identity = f.store.activeQiMon, history = f.store.evolution.history
            change(f.store)
            XCTAssertNil(f.store.harmonyThemeRequest, "A cancelled request cannot be started by late audio synthesis")
            XCTAssertEqual(f.store.activeQiMon, identity)
            XCTAssertEqual(f.store.evolution.history, history)
            XCTAssertEqual(try Data(contentsOf: f.url), bytes)
            XCTAssertEqual(f.local.connects + f.cloud.connects, 0)
            XCTAssertTrue(f.local.callbacks.isEmpty && f.cloud.callbacks.isEmpty)
        }
    }

    @MainActor
    func testThemeCannotBeRequestedWhileDisabledMutedQuietHiddenOrWithoutKin() throws {
        let restrictions: [(CompanionStore) -> Void] = [
            { $0.preferences.musicalCues = false }, { $0.preferences.musicalVolume = 0 },
            { $0.preferences.quiet = true }, { $0.hideCompanion() }, { $0.observeQiMonJourney(nil) }
        ]
        for restrict in restrictions {
            let f = try KinLightFixture(); defer { f.cleanup() }
            f.store.preferences.musicalCues = true
            restrict(f.store)
            XCTAssertFalse(f.store.canPreviewHarmonyTheme)
            f.store.previewHarmonyTheme()
            XCTAssertNil(f.store.harmonyThemeRequest)
            XCTAssertTrue(f.local.callbacks.isEmpty && f.cloud.callbacks.isEmpty)
        }
    }

    @MainActor
    func testActualReplyLifecycleAndLateCallbacksKeepStopFinal() async throws {
        let f = try KinLightFixture(); defer { f.cleanup() }
        f.store.connectAssistant()
        try await wait { f.store.connectionState == .ready }
        f.store.prompt = "Help with this synthetic task."
        f.store.submit()
        try await wait { f.local.callbacks.count == 1 }
        XCTAssertEqual(f.store.kinLightExpression.mode, .orbit)
        XCTAssertFalse(f.store.previewKinLight(.core), "A cosmetic preview cannot displace active work")
        f.store.preferences.musicalCues = true
        XCTAssertFalse(f.store.canPreviewHarmonyTheme)
        f.store.previewHarmonyTheme()
        XCTAssertNil(f.store.harmonyThemeRequest, "The theme cannot start while an answer is being prepared")
        f.local.emit(0, "A useful answer.")
        XCTAssertEqual(f.store.kinLightExpression.mode, .pulse)
        f.local.finish(0)
        try await wait { !f.store.isWorking }
        XCTAssertEqual(f.store.kinLightExpression.mode, .delight)
        f.store.submit()
        try await wait { f.local.callbacks.count == 2 }
        f.store.cancelWork()
        XCTAssertEqual(f.store.kinLightExpression, .resting)
        f.local.emit(1, "A stale answer must not light KIN again.")
        f.local.finish(1)
        try await wait { f.local.pending.isEmpty }
        await Task.yield()
        XCTAssertEqual(f.store.assistantActivity, .stopped)
        XCTAssertEqual(f.store.kinLightExpression, .resting)
        XCTAssertEqual(f.store.presentationForm, .kinSeed)
    }

    @MainActor
    func testCompareUsesRemainingWorkBeforeACompletedSibling() async throws {
        let f = try KinLightFixture(); defer { f.cleanup() }
        f.store.setAssistantRoute(.compare)
        f.store.connectAssistant(provider: .qwen)
        f.store.connectAssistant(provider: .codex)
        try await wait { f.store.connectionState == .ready }
        f.store.prompt = "Compare this synthetic note."
        f.store.submit()
        try await wait { f.local.callbacks.count == 1 && f.cloud.callbacks.count == 1 }
        f.local.emit(0, "A completed local answer.")
        f.local.finish(0)
        try await wait { f.store.compareResults[.qwen]?.state == .complete }
        XCTAssertEqual(f.store.kinLightExpression.mode, .orbit)
        f.cloud.emit(0, "Cloud text is arriving.")
        XCTAssertEqual(f.store.kinLightExpression.mode, .pulse)
        f.cloud.finish(0, failure: AssistantFailure.protocolError)
        try await wait { !f.store.isWorking }
        XCTAssertEqual(f.store.kinLightExpression.mode, .delight, "A successful sibling remains an available answer")
        XCTAssertEqual(f.store.compareResults[.codex]?.state, .failed)
    }

    private func resolve(_ activity: AssistantActivity, focus: Bool = false, preview: KinLightMode? = nil) -> KinLightExpression {
        KinLightRules.resolve(activity: activity, hasFreshFocus: focus, preview: preview,
            visible: true, quiet: false, activeKin: true)
    }

    @MainActor private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Synthetic light-ability lifecycle did not settle")
        throw NSError(domain: "KinLightAbilityTests", code: 1)
    }
}

@MainActor private final class KinLightClock { var now: TimeInterval = 10 }

@MainActor private final class KinLightFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-kin-light-\(UUID())")
    var url: URL { directory.appendingPathComponent("preferences.json") }
    let clock = KinLightClock()
    let local = KinLightClient(), cloud = KinLightClient()
    let store: CompanionStore
    init() throws {
        let clock = clock, cloud = cloud
        store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"), assistant: local,
            assistantFactory: { _, _ in cloud }, monotonicTime: { clock.now })
        store.observeQiMonJourney(HostedPlayProjection(version: 3, host: "archi-desktop", sessionId: UUID().uuidString,
            sequence: 1, kind: "journey-projection", readiness: .ready, storage: .localBrowser, mode: .habitat,
            journeyId: "ARCHI-AAAAAAAA", revision: "saved", eventCount: 4, visible: false,
            originDigest: String(repeating: "a", count: 64), practices: [], arena: nil))
        XCTAssertTrue(store.welcomeKin())
    }
    func cleanup() {
        store.cancelWork()
        store.disconnectAssistant(provider: .qwen)
        store.disconnectAssistant(provider: .codex)
        local.drain(); cloud.drain()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Retain cancelled callbacks so the test exercises the real store's ownership checks.
@MainActor private final class KinLightClient: AssistantClient {
    var connects = 0
    var callbacks: [@MainActor (AssistantEvent) -> Void] = []
    var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var draining = false
    func connect() async throws { connects += 1 }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        guard !draining else { throw AssistantFailure.stopped }
        let index = callbacks.count
        callbacks.append(onEvent)
        try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func emit(_ index: Int, _ text: String) { callbacks[index](.text(text)) }
    func finish(_ index: Int, failure: (any Error)? = nil) {
        guard let continuation = pending.removeValue(forKey: index) else { XCTFail("No pending fixture reply"); return }
        if let failure { continuation.resume(throwing: failure) } else { continuation.resume() }
    }
    func disconnect() {}
    func drain() {
        draining = true
        let work = Array(pending.values); pending.removeAll()
        work.forEach { $0.resume(throwing: AssistantFailure.stopped) }
    }
}
