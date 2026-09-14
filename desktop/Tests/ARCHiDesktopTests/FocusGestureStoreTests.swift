import AppKit
import XCTest
@testable import ARCHiDesktop

final class FocusGestureStoreTests: XCTestCase {
    @MainActor private final class Clock { var now: TimeInterval = 10 }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-gesture-\(UUID())")
        let clock = Clock()
        let client = GestureAssistant()
        let store: CompanionStore
        var geometry: SelectedPassageGeometry
        var environment: SpatialEnvironment
        var moves: [CGRect] = []
        var url: URL { directory.appendingPathComponent("preferences.json") }

        init() {
            let clock = clock
            store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
                assistant: client, monotonicTime: { clock.now })
            store.section = .context
            store.preferences.form = .particle
            store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
            store.evolution.observeJourneyOrigin(String(repeating: "b", count: 64))
            store.share(text: "A useful passage. Another sentence.", name: "practice.txt")
            store.selectText(range: NSRange(location: 0, length: 17), sourceRevision: store.sourceRevision)
            let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
            geometry = SelectedPassageGeometry(selection: store.textSelection!,
                rects: [CGRect(x: 300, y: 500, width: 220, height: 20)],
                viewport: CGRect(x: 280, y: 300, width: 340, height: 300),
                windowFrame: CGRect(x: 200, y: 100, width: 1000, height: 700),
                windowNumber: 12, screenID: 1, screenFrame: screen)
            environment = SpatialEnvironment(companionFrame: CGRect(x: 360, y: 450, width: 128, height: 154),
                displays: [SpatialDisplay(id: 1, frame: screen, visibleFrame: screen)])
            store.onObserveSelectedPassage = { [weak self] in self?.geometry }
            store.onObserveSpatialEnvironment = { [weak self] in self?.environment }
            store.onMoveCompanion = { [weak self] frame in self?.moves.append(frame) }
        }

        func cleanup() { store.stopFocusGesture(); try? FileManager.default.removeItem(at: directory) }
    }

    @MainActor
    func testPreviewAndCorrectionsStayInDraftWithoutChangingTheCompanionOrCallingModels() throws {
        let f = Fixture(); defer { f.cleanup() }
        let preferences = f.store.preferences, ticket = f.store.contextTicket()
        let natural = f.store.evolution.naturalVariation, revision = f.store.evolution.revision
        let appearance = f.store.reactor.appearanceID
        f.store.beginFocusGestureTeaching()
        f.store.previewFocusGesture()
        let first = try XCTUnwrap(f.store.focusGesturePlayback)
        XCTAssertEqual(first.purpose, .preview)
        XCTAssertNil(first.spatialPreviewID)
        XCTAssertNil(f.store.spatialPreview)
        f.store.focusGestureDraft?.pace = .unhurried
        XCTAssertNil(f.store.focusGesturePlayback)
        XCTAssertFalse(f.store.validateFocusGesturePlayback(id: first.id))
        f.store.previewFocusGesture()
        XCTAssertEqual(f.store.focusGesturePlayback?.configuration.pace, .unhurried)
        f.store.cancelFocusGestureTeaching()
        XCTAssertNil(f.store.focusGestureDraft)
        XCTAssertNil(f.store.keptFocusGesture)
        XCTAssertEqual(f.store.preferences, preferences)
        XCTAssertEqual(f.store.contextTicket(), ticket)
        XCTAssertEqual(f.store.evolution.naturalVariation, natural)
        XCTAssertEqual(f.store.evolution.revision, revision)
        XCTAssertEqual(f.store.reactor.appearanceID, appearance)
        XCTAssertTrue(f.moves.isEmpty)
        XCTAssertEqual(f.client.calls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
    }

    @MainActor
    func testKeepAndRestartSaveOnlyGestureAlongsideExistingLessonsAndSavedAppearance() throws {
        let f = Fixture(); defer { f.cleanup() }
        f.store.rememberPreferences = true
        f.store.savePreferences()
        f.store.beginLessonCorrection()
        f.store.lessonDraft?.topic = "planning"
        f.store.lessonDraft?.text = "Begin with three clear steps."
        XCTAssertTrue(f.store.keepLesson(try XCTUnwrap(f.store.lessonDraft)))
        let lessons = f.store.keptLessons
        let savedPreferences = try NativePreferencePersistence.read(f.url).document.preferences
        f.store.preferences.form = .geode // a deliberately unsaved visit choice
        let settings = f.store.nextReplySettings
        f.store.beginFocusGestureTeaching()
        let chosen = FocusGestureConfiguration(pace: .unhurried, sparkle: .none, hold: .lingering)
        f.store.focusGestureDraft = chosen
        XCTAssertTrue(f.store.keepFocusGesture())
        XCTAssertEqual(f.store.keptFocusGesture, chosen)
        XCTAssertEqual(f.store.nextReplySettings, settings)
        XCTAssertEqual(f.store.preferences.form, .geode)
        let reopened = CompanionStore(preferenceURL: f.url, assistant: GestureAssistant())
        XCTAssertEqual(reopened.keptFocusGesture, chosen)
        XCTAssertEqual(reopened.preferences, savedPreferences)
        XCTAssertEqual(reopened.keptLessons, lessons)
        XCTAssertNil(reopened.focusGestureDraft)
        XCTAssertNil(reopened.focusGesturePlayback)
    }

    @MainActor
    func testGestureOnlySaveAndScopedForgetDoNotCaptureVisitChoicesOrRemoveLessons() throws {
        let f = Fixture(); defer { f.cleanup() }
        f.store.beginFocusGestureTeaching()
        XCTAssertTrue(f.store.keepFocusGesture())
        let saved = try NativePreferencePersistence.read(f.url).document
        XCTAssertNil(saved.preferences)
        XCTAssertEqual(saved.focusGesture, FocusGestureConfiguration())
        XCTAssertTrue(saved.lessons.isEmpty)
        f.store.beginLessonCorrection()
        f.store.lessonDraft?.topic = "draft"
        f.store.lessonDraft?.text = "Keep examples concrete."
        XCTAssertTrue(f.store.keepLesson(try XCTUnwrap(f.store.lessonDraft)))
        let lessons = f.store.keptLessons
        let export = try NativePreferenceDocument.decode(f.store.lessonExportData())
        XCTAssertNil(export.preferences)
        XCTAssertNil(export.focusGesture, "Export kept lessons must not include a gesture preference")
        XCTAssertEqual(export.lessons, lessons)
        XCTAssertTrue(f.store.forgetFocusGesture())
        let reopened = CompanionStore(preferenceURL: f.url, assistant: GestureAssistant())
        XCTAssertNil(reopened.keptFocusGesture)
        XCTAssertEqual(reopened.keptLessons, lessons)
        XCTAssertEqual(reopened.preferences.form, .companion)
    }

    @MainActor
    func testExternalSaveConflictPreservesKeptGestureDraftAndFile() throws {
        let f = Fixture(); defer { f.cleanup() }
        f.store.beginFocusGestureTeaching()
        XCTAssertTrue(f.store.keepFocusGesture())
        let before = try NativePreferencePersistence.read(f.url)
        var elsewhere = before.document
        elsewhere.revision += 1
        elsewhere.focusGesture = FocusGestureConfiguration(pace: .quick, sparkle: .bright)
        let outside = try NativePreferencePersistence.write(document: elsewhere, to: f.url, expected: before.baseline)
        f.store.beginFocusGestureTeaching()
        f.store.focusGestureDraft?.pace = .unhurried
        XCTAssertFalse(f.store.keepFocusGesture())
        XCTAssertEqual(f.store.keptFocusGesture, FocusGestureConfiguration())
        XCTAssertEqual(f.store.focusGestureDraft?.pace, .unhurried)
        XCTAssertEqual(try Data(contentsOf: f.url), outside)
        XCTAssertFalse(f.store.forgetFocusGesture())
        XCTAssertEqual(try Data(contentsOf: f.url), outside)
    }

    @MainActor
    func testPracticeUsesDraftAndTheNextPointCommandUsesOnlyTheKeptGesture() throws {
        let f = Fixture(); defer { f.cleanup() }
        f.store.beginFocusGestureTeaching()
        f.store.focusGestureDraft = FocusGestureConfiguration(pace: .quick, sparkle: .none)
        XCTAssertTrue(f.store.keepFocusGesture())
        f.store.beginFocusGestureTeaching()
        f.store.focusGestureDraft = FocusGestureConfiguration(pace: .unhurried, sparkle: .bright, hold: .lingering)
        let ticket = f.store.contextTicket(), source = f.store.sharedText
        let revision = f.store.evolution.revision
        XCTAssertTrue(f.store.practiceFocusGesture())
        let practice = try XCTUnwrap(f.store.focusGesturePlayback)
        XCTAssertEqual(practice.configuration, f.store.focusGestureDraft)
        XCTAssertEqual(practice.purpose, .practice)
        XCTAssertEqual(practice.spatialPreviewID, f.store.spatialPreview?.id)
        XCTAssertEqual(f.store.spatialPreview?.geometry, f.geometry)
        XCTAssertTrue(f.store.activateEquippedItem())
        let point = try XCTUnwrap(f.store.focusGesturePlayback)
        XCTAssertEqual(point.configuration, f.store.keptFocusGesture)
        XCTAssertEqual(point.configuration.pace, .quick)
        XCTAssertEqual(point.purpose, .pointing)
        XCTAssertFalse(f.store.validateFocusGesturePlayback(id: practice.id))
        XCTAssertEqual(f.store.contextTicket(), ticket)
        XCTAssertEqual(f.store.sharedText, source)
        XCTAssertEqual(f.store.evolution.revision, revision)
        XCTAssertEqual(f.client.calls, 0)
        XCTAssertTrue(f.moves.isEmpty)
    }

    @MainActor
    func testStopAndLateCompletionCannotReviveOrClearAReplacementGesture() async throws {
        let f = Fixture(); defer { f.cleanup() }
        XCTAssertTrue(f.store.activateEquippedItem())
        let first = try XCTUnwrap(f.store.focusGesturePlayback)
        f.store.stopFocusGesture()
        XCTAssertNil(f.store.focusGesturePlayback)
        XCTAssertNil(f.store.spatialPreview)
        XCTAssertTrue(f.store.activateEquippedItem())
        let second = try XCTUnwrap(f.store.focusGesturePlayback)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(f.store.validateFocusGesturePlayback(id: first.id))
        try await Task.sleep(for: .milliseconds(110))
        XCTAssertEqual(f.store.focusGesturePlayback?.id, second.id)
        f.clock.now += second.configuration.duration
        XCTAssertFalse(f.store.validateFocusGesturePlayback(id: second.id))
        XCTAssertNil(f.store.focusGesturePlayback)
        XCTAssertNotNil(f.store.spatialPreview, "Finished cue does not claim the selected passage ceased to exist")
        f.store.dismissPlacementPreview()
        XCTAssertTrue(f.moves.isEmpty)
    }

    @MainActor
    func testSourcePlacementEquipmentAndVisibilityChangesRetireActiveGesture() throws {
        let changes: [(CompanionStore) -> Void] = [
            { $0.share(text: "Different source", name: "new.txt") },
            { $0.clearTextSelection() }, { $0.invalidateTextSelection(reason: "Scrolled") },
            { $0.placed(at: CGPoint(x: 50, y: 80)) }, { $0.preferences.equipment = .empty },
            { $0.preferences.form = .sprout }, { $0.preferences.quiet = true },
            { $0.preferences.reduceMotion = true }, { $0.hideCompanion() },
            { $0.section = .play }, { $0.cancelWork() }, { $0.dismissPlacementPreview() }
        ]
        for change in changes {
            let f = Fixture(); defer { f.cleanup() }
            XCTAssertTrue(f.store.activateEquippedItem())
            let id = try XCTUnwrap(f.store.focusGesturePlayback).id
            change(f.store)
            XCTAssertNil(f.store.focusGesturePlayback)
            XCTAssertNil(f.store.spatialPreview)
            XCTAssertFalse(f.store.validateFocusGesturePlayback(id: id))
            XCTAssertTrue(f.moves.isEmpty)
            XCTAssertEqual(f.client.calls, 0)
        }
    }

    @MainActor
    func testReobservationRejectsUnannouncedGeometryChangeAndBusyOrMissingTarget() throws {
        let f = Fixture(); defer { f.cleanup() }
        XCTAssertTrue(f.store.activateEquippedItem())
        let id = try XCTUnwrap(f.store.focusGesturePlayback).id
        f.environment = SpatialEnvironment(companionFrame: f.environment.companionFrame.offsetBy(dx: 1, dy: 0),
            displays: f.environment.displays)
        XCTAssertFalse(f.store.validateFocusGesturePlayback(id: id))
        XCTAssertNil(f.store.focusGesturePlayback)
        XCTAssertNil(f.store.spatialPreview)
        f.store.isWorking = true
        XCTAssertFalse(f.store.activateEquippedItem())
        f.store.isWorking = false
        f.store.onObserveSelectedPassage = { nil }
        XCTAssertFalse(f.store.activateEquippedItem())
        XCTAssertEqual(f.client.calls, 0)
        XCTAssertTrue(f.moves.isEmpty)
    }

    @MainActor
    func testNativeAccessibilityTracksTheIncomingGestureAndStopWithoutMoving() throws {
        let f = Fixture(); defer { f.cleanup() }
        let panel = CompanionPanelController(store: f.store)
        let frame = panel.window.frame
        f.store.selectText(range: NSRange(location: 0, length: 17), sourceRevision: f.store.sourceRevision)
        // The native panel supplies the actual environment; retain the fixture's target screen.
        f.store.onObserveSpatialEnvironment = { f.environment }
        XCTAssertTrue(f.store.activateEquippedItem())
        let interaction = try XCTUnwrap(panel.window.contentView)
        XCTAssertTrue((interaction.accessibilityValue() as? String)?.contains("Pointing with staff") == true)
        f.store.stopFocusGesture()
        XCTAssertFalse((interaction.accessibilityValue() as? String)?.contains("Pointing with staff") == true)
        XCTAssertEqual(panel.window.frame, frame)
        panel.hide()
    }
}

@MainActor
private final class GestureAssistant: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1 }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
    }
    func disconnect() {}
}
