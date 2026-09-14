import XCTest
@testable import ARCHiDesktop

/// Additional artwork uses the same explicit choice and persistence owners.
/// The assistant below records unexpected work without invoking any provider.
final class TealFamilyStateTests: XCTestCase {
    private let newForms: [CompanionForm] = [.constellation, .sprout, .ribbonSpirit, .geode]

    func testAdditionalFormsPreserveEveryExistingSavedNameAndDefault() throws {
        let originals: [(CompanionForm, String)] = [
            (.companion, "Companion"), (.light, "Guide light"), (.particle, "Particle light"),
            (.ribbon, "Ribbon"), (.ink, "Ink"), (.pixel, "Pixel")
        ]
        XCTAssertEqual(CompanionPreferences().form, .companion)
        // Further optional forms may be inserted without removing or renaming
        // the saved originals. Their relative order remains stable.
        let originalForms = originals.map(\.0)
        XCTAssertEqual(CompanionForm.allCases.filter { originalForms.contains($0) }, originalForms)
        for (form, savedName) in originals {
            let old: [String: Any] = ["form": savedName, "tone": "Warm", "replyLength": 0.6,
                "size": 1.2, "adaptive": false, "reduceMotion": true, "quiet": true]
            let data = try JSONSerialization.data(withJSONObject: old)
            let restored = try XCTUnwrap(NativePreferenceDocument.decode(data).preferences)
            XCTAssertEqual(restored.form, form)
            XCTAssertEqual(restored.equipment, .empty)
            XCTAssertEqual(restored.visualTreatment, .original)
            XCTAssertEqual(restored.tone, "Warm")
            XCTAssertTrue(restored.reduceMotion && restored.quiet)
        }
        XCTAssertEqual(newForms.map(\.rawValue), ["Constellation", "Jade Sprout", "Ribbon Spirit", "Crystal Core"])
        for form in newForms {
            XCTAssertEqual(try JSONDecoder().decode(CompanionForm.self, from: JSONEncoder().encode(form)), form)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(CompanionForm.self, from: Data(#""Emerald Particle""#.utf8)),
            "Concept names are not silently reinterpreted as saved forms")
    }

    @MainActor
    func testEveryNewChoicePreservesTheIndividualPlacementAndReviewedLessonHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = TealStateAssistant()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"), assistant: client)
        store.placed(at: CGPoint(x: 381, y: 142))
        store.preferences.tone = "Direct"
        store.preferences.replyLength = 0.7
        store.preferences.visualTreatment = .pearlStudy
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        store.preferences.quiet = true
        store.preferences.reduceMotion = true
        let journeyOrigin = String(repeating: "a", count: 64)
        store.evolution.observeJourneyOrigin(journeyOrigin)
        XCTAssertTrue(store.evolution.bindPracticeJourney(journeyOrigin))
        store.evolution.confirmRole(.muse)
        store.evolution.confirmHelpStyle(.reflective)
        let lesson = try keepSyntheticLesson(in: store)
        XCTAssertTrue(store.evolution.markUseful(receipt: receipt(lesson: lesson),
            sourceDigest: journeyOrigin, confirmedLesson: lesson))
        let preferences = store.preferences, position = store.position, context = store.contextTicket()
        let placement = store.placementRevision, settings = store.nextReplySettings
        let origin = store.evolution.origin, natural = store.evolution.naturalVariation
        let history = store.evolution.history, receipts = store.evolution.usefulReceipts
        let practices = store.evolution.reviewedPractices, lessons = store.keptLessons
        let evolutionPreferences = store.evolution.preferences

        for form in newForms + [.particle, .companion] {
            store.chooseStartingForm(form)
            var expected = preferences; expected.form = form
            XCTAssertEqual(store.preferences, expected)
            XCTAssertEqual(store.position, position)
            XCTAssertEqual(store.placementRevision, placement)
            XCTAssertEqual(store.contextTicket(), context)
            XCTAssertEqual(store.nextReplySettings, settings)
            XCTAssertEqual(store.evolution.origin, origin)
            XCTAssertNil(store.evolution.activeFamily)
            XCTAssertEqual(store.evolution.naturalVariation, natural)
            XCTAssertEqual(store.evolution.history, history)
            XCTAssertEqual(store.evolution.usefulReceipts, receipts)
            XCTAssertEqual(store.evolution.reviewedPractices, practices)
            XCTAssertEqual(store.evolution.preferences, evolutionPreferences)
            XCTAssertEqual(store.evolution.observedJourneyOriginDigest, journeyOrigin)
            XCTAssertEqual(store.evolution.practiceJourneyOriginDigest, journeyOrigin)
            XCTAssertEqual(store.keptLessons, lessons)
            XCTAssertEqual(store.assistantActivity, .idle)
            XCTAssertEqual(store.reactor.state, .idle)
            XCTAssertFalse(store.isWorking)
        }
        XCTAssertEqual(client.connectCount, 0)
        XCTAssertEqual(client.replyCount, 0)
        XCTAssertEqual(client.disconnectCount, 0)
    }

    @MainActor
    func testAllNewFormsSaveExplicitlyAndReopenAlongsideAnExistingLesson() throws {
        for form in newForms {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("preferences.json")
            let store = CompanionStore(preferenceURL: url, assistant: TealStateAssistant())
            let lesson = try keepSyntheticLesson(in: store)
            let savedBeforeChoice = try Data(contentsOf: url)
            store.chooseStartingForm(form)
            store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
            store.preferences.visualTreatment = .pearlStudy
            store.preferences.reduceMotion = true
            store.savePreferences()
            XCTAssertEqual(try Data(contentsOf: url), savedBeforeChoice,
                "A new form cannot turn on saving choices implicitly")
            store.rememberPreferences = true
            store.savePreferences()
            let reopened = CompanionStore(preferenceURL: url, assistant: TealStateAssistant())
            XCTAssertEqual(reopened.preferences, store.preferences)
            XCTAssertEqual(reopened.keptLessons.map(LessonSnapshot.init(lesson:)), [lesson])
            XCTAssertEqual(reopened.evolution.origin, form)
            XCTAssertNil(reopened.evolution.activeFamily)
            XCTAssertTrue(reopened.evolution.history.isEmpty)
            XCTAssertTrue(reopened.rememberPreferences)
            reopened.chooseStartingForm(.particle)
            reopened.savePreferences()
            XCTAssertEqual(CompanionStore(preferenceURL: url, assistant: TealStateAssistant()).preferences.form, .particle)
        }
    }

    @MainActor
    func testChoosingANewFormUsesTheExistingReturnHistoryAndRetainsSavedIdentity() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let store = CompanionStore(preferenceURL: url, assistant: TealStateAssistant())
        let original = store.evolution.origin
        let journeyOrigin = String(repeating: "a", count: 64)
        store.evolution.observeJourneyOrigin(journeyOrigin)
        store.evolution.confirmFamily(.lumen)
        XCTAssertTrue(store.evolution.keepEvolution(try XCTUnwrap(store.evolution.proposeEvolution())))
        let keptHistory = store.evolution.history, natural = store.evolution.naturalVariation
        store.chooseStartingForm(.sprout)
        XCTAssertNil(store.evolution.activeFamily)
        XCTAssertEqual(Array(store.evolution.history.prefix(keptHistory.count)), keptHistory)
        XCTAssertEqual(store.evolution.history.count, keptHistory.count + 1)
        XCTAssertEqual(store.evolution.history.last?.kind, .returned)
        XCTAssertEqual(store.evolution.origin, original)
        XCTAssertEqual(store.evolution.naturalVariation, natural)
        XCTAssertTrue(store.evolution.save())
        store.rememberPreferences = true
        store.savePreferences()
        let reopened = CompanionStore(preferenceURL: url, assistant: TealStateAssistant())
        XCTAssertEqual(reopened.preferences.form, .sprout)
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertEqual(reopened.evolution.origin, original)
        XCTAssertEqual(reopened.evolution.history, store.evolution.history)
        XCTAssertNil(reopened.evolution.naturalVariation,
            "Evolution saving does not take ownership of the current Journey")
        reopened.evolution.observeJourneyOrigin(journeyOrigin)
        XCTAssertEqual(reopened.evolution.naturalVariation, natural)
        XCTAssertEqual(reopened.preferences.form, .sprout)
    }

    @MainActor
    func testFloatingAccessibilityReceivesEveryNewFormWithoutMovingTheWindow() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"), assistant: TealStateAssistant())
        let panel = CompanionPanelController(store: store)
        defer { panel.window.orderOut(nil) }
        let frame = panel.window.frame, placement = store.placementRevision
        for form in newForms + [.particle] {
            store.chooseStartingForm(form)
            XCTAssertEqual(panel.window.contentView?.accessibilityValue() as? String, store.assistantAccessibilityValue)
            XCTAssertTrue(store.assistantAccessibilityValue.contains(form.rawValue))
            XCTAssertEqual(panel.window.frame, frame)
            XCTAssertEqual(store.placementRevision, placement)
        }
    }

    @MainActor
    private func keepSyntheticLesson(in store: CompanionStore) throws -> LessonSnapshot {
        store.beginLessonCorrection()
        var draft = try XCTUnwrap(store.lessonDraft)
        draft.topic = "drawing plan"
        draft.text = "Start with a light pencil outline."
        XCTAssertTrue(store.keepLesson(draft))
        return LessonSnapshot(lesson: try XCTUnwrap(store.keptLessons.first))
    }

    private func receipt(lesson: LessonSnapshot) -> AssistantLaneReceipt {
        var receipt = AssistantLaneReceipt(requestID: UUID().uuidString, route: .local, provider: .qwen,
            context: ContextTicket(generation: 1, placement: 1, source: 1, selection: 1),
            inputDigest: String(repeating: "b", count: 64), sourceDigest: String(repeating: "a", count: 64),
            inputContract: "native-assistant-input/v2", deadline: .distantFuture,
            modelIdentity: "synthetic-state-fixture", state: .complete)
        receipt.localLessons = [lesson]
        receipt.usedLessonIDs = [lesson.modelID]
        return receipt
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("archi-teal-state-\(UUID().uuidString)")
    }
}

@MainActor
private final class TealStateAssistant: AssistantClient {
    var connectCount = 0
    var replyCount = 0
    var disconnectCount = 0
    func connect() async throws { connectCount += 1 }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        replyCount += 1
    }
    func disconnect() { disconnectCount += 1 }
}
