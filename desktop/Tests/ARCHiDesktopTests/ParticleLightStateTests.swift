import XCTest
@testable import ARCHiDesktop

final class ParticleLightStateTests: XCTestCase {
    @MainActor
    func testFloatingAccessibilityUsesTheIncomingFormAndEquipmentWithoutMoving() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"), assistant: ParticleStateAssistant())
        let panel = CompanionPanelController(store: store)
        defer { panel.window.orderOut(nil) }
        let frame = panel.window.frame, placement = store.placementRevision
        for form in [CompanionForm.particle, .light, .kinSeed, .particle] {
            store.chooseStartingForm(form)
            XCTAssertEqual(panel.window.contentView?.accessibilityValue() as? String, store.assistantAccessibilityValue)
            XCTAssertEqual(panel.window.frame, frame)
            XCTAssertEqual(store.placementRevision, placement)
        }
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        XCTAssertEqual(panel.window.contentView?.accessibilityValue() as? String, store.assistantAccessibilityValue)
        store.preferences.equipment = .empty
        XCTAssertEqual(panel.window.contentView?.accessibilityValue() as? String, store.assistantAccessibilityValue)
        XCTAssertEqual(panel.window.frame, frame)
        XCTAssertEqual(store.placementRevision, placement)
    }

    func testParticleIsAnAdditionalStarterAndGuideLightSavesRetainTheirMeaning() throws {
        XCTAssertEqual(CompanionForm.particle.rawValue, "Particle light")
        XCTAssertEqual(CompanionForm.light.rawValue, "Guide light")
        XCTAssertNotEqual(CompanionForm.particle, .light)
        XCTAssertTrue(CompanionForm.allCases.contains(.particle))
        XCTAssertEqual(CompanionPreferences().form, .companion)
        XCTAssertEqual(CompanionPreferences().equipment, .empty)

        let old = Data(#"{"form":"Guide light","tone":"Warm","replyLength":0.6,"size":1.2,"adaptive":false,"reduceMotion":true,"quiet":true}"#.utf8)
        let preferences = try XCTUnwrap(NativePreferenceDocument.decode(old).preferences)
        XCTAssertEqual(preferences.form, .light)
        XCTAssertEqual(preferences.equipment, .empty)
        XCTAssertEqual(preferences.visualTreatment, .original)
        XCTAssertEqual(preferences.tone, "Warm")
        XCTAssertEqual(preferences.size, 1.2)
        XCTAssertTrue(preferences.reduceMotion && preferences.quiet)

        XCTAssertEqual(try JSONDecoder().decode(CompanionForm.self,
            from: JSONEncoder().encode(CompanionForm.particle)), .particle)
        XCTAssertThrowsError(try JSONDecoder().decode(CompanionForm.self,
            from: Data(#""particle""#.utf8)), "Only the exact saved form identifier is supported")
    }

    @MainActor
    func testChoosingParticleKeepsPlacementEquipmentRequestSettingsAndIndividual() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ParticleStateAssistant()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"), assistant: client)
        store.placed(at: CGPoint(x: 421, y: 83))
        store.preferences.visualTreatment = .pearlStudy
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        store.preferences.quiet = true
        store.evolution.observeJourneyOrigin(String(repeating: "a", count: 64))
        store.evolution.confirmRole(.muse)
        store.evolution.confirmHelpStyle(.reflective)
        let position = store.position, placement = store.placementRevision
        let settings = store.nextReplySettings, natural = store.evolution.naturalVariation
        let preferences = store.evolution.preferences, history = store.evolution.history
        let receipts = store.evolution.usefulReceipts, practices = store.evolution.reviewedPractices
        let context = store.contextTicket()

        store.chooseStartingForm(.particle)

        XCTAssertEqual(store.preferences.form, .particle)
        XCTAssertNil(store.evolution.activeFamily)
        XCTAssertEqual(store.preferences.visualTreatment, .pearlStudy)
        XCTAssertEqual(store.preferences.equipment.hand, .focusStaff)
        XCTAssertTrue(store.preferences.quiet)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.contextTicket(), context)
        XCTAssertEqual(store.nextReplySettings, settings)
        XCTAssertEqual(store.evolution.naturalVariation, natural)
        XCTAssertEqual(store.evolution.preferences, preferences)
        XCTAssertEqual(store.evolution.history, history)
        XCTAssertEqual(store.evolution.usefulReceipts, receipts)
        XCTAssertEqual(store.evolution.reviewedPractices, practices)
        XCTAssertEqual(store.assistantActivity, .idle)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(client.connectCount, 0)
        XCTAssertEqual(client.replyCount, 0)
        XCTAssertEqual(client.disconnectCount, 0)
        XCTAssertEqual(store.reactor.state, .idle)
    }

    @MainActor
    func testParticleUsesExistingExplicitPreferenceSaveAndReopen() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let store = CompanionStore(preferenceURL: url, assistant: ParticleStateAssistant())
        store.chooseStartingForm(.particle)
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        store.preferences.tone = "Direct"
        store.preferences.reduceMotion = true
        store.savePreferences()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        store.rememberPreferences = true
        store.savePreferences()
        let document = try NativePreferenceDocument.decode(Data(contentsOf: url))
        XCTAssertEqual(document.preferences?.form, .particle)
        XCTAssertTrue(document.lessons.isEmpty)

        let reopened = CompanionStore(preferenceURL: url, assistant: ParticleStateAssistant())
        XCTAssertEqual(reopened.preferences, store.preferences)
        XCTAssertEqual(reopened.evolution.origin, .particle)
        XCTAssertNil(reopened.evolution.activeFamily)
        XCTAssertTrue(reopened.evolution.history.isEmpty)
        XCTAssertTrue(reopened.rememberPreferences)
        reopened.chooseStartingForm(.light)
        reopened.savePreferences()
        XCTAssertEqual(CompanionStore(preferenceURL: url, assistant: ParticleStateAssistant()).preferences.form, .light)
    }

    @MainActor
    func testParticleOriginSurvivesEvolutionSaveLoadAndReturn() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("evolution.json")
        let evolution = EvolutionStore(origin: .particle, saveURL: url)
        let origin = String(repeating: "b", count: 64)
        evolution.observeJourneyOrigin(origin)
        XCTAssertTrue(evolution.bindPracticeJourney(origin))
        evolution.confirmFamily(.lumen)
        XCTAssertTrue(evolution.keepEvolution(try XCTUnwrap(evolution.proposeEvolution())))
        let natural = evolution.naturalVariation, history = evolution.history
        XCTAssertTrue(evolution.save())

        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.load())
        XCTAssertEqual(reopened.origin, .particle)
        XCTAssertEqual(reopened.activeFamily, .lumen)
        XCTAssertEqual(reopened.history, history)
        XCTAssertEqual(reopened.naturalVariation, natural)
        reopened.returnToStarter()
        XCTAssertEqual(reopened.origin, .particle)
        XCTAssertNil(reopened.activeFamily)
        XCTAssertEqual(reopened.history.last?.kind, .returned)
        XCTAssertEqual(reopened.naturalVariation, natural)
        XCTAssertTrue(reopened.usefulReceipts.isEmpty)
        XCTAssertTrue(reopened.reviewedPractices.isEmpty)
    }

    @MainActor
    func testParticleAppearanceCacheAndAccessibleLabelDistinguishEquipmentAndGuideLight() {
        let plain = CompanionVisualAsset.appearanceID(form: .particle, family: nil, treatment: .original)
        let guide = CompanionVisualAsset.appearanceID(form: .light, family: nil, treatment: .original)
        let staff = CompanionEquipment(hand: .focusStaff)
        let equipped = CompanionVisualAsset.appearanceID(form: .particle, family: nil,
            treatment: .original, equipment: staff)
        XCTAssertNotEqual(plain, guide)
        XCTAssertNotEqual(equipped, plain)
        XCTAssertEqual(plain, CompanionVisualAsset.appearanceID(form: .particle, family: nil, treatment: .pearlStudy))
        XCTAssertEqual(equipped, CompanionVisualAsset.appearanceID(form: .particle, family: nil,
            treatment: .original, equipment: staff))
        let label = CompanionVisualAsset.label(form: .particle, family: nil, treatment: .original, equipment: staff)
        XCTAssertTrue(label.contains("Particle light"))
        XCTAssertTrue(label.contains("Focus Staff"))
        XCTAssertFalse(label.contains("Guide light"))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("archi-particle-state-\(UUID().uuidString)")
    }
}

@MainActor
private final class ParticleStateAssistant: AssistantClient {
    var connectCount = 0
    var replyCount = 0
    var disconnectCount = 0
    func connect() async throws { connectCount += 1 }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        replyCount += 1
    }
    func disconnect() { disconnectCount += 1 }
}
