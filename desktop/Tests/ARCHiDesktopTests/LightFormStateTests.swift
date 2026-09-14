import AppKit
import XCTest
@testable import ARCHiDesktop

final class LightFormStateTests: XCTestCase {
    private let forms: [CompanionForm] = [.corePearl, .orbitField, .lightForm]

    func testLightFormsRoundTripWithoutReplacingExistingStarterIdentifiers() throws {
        let expected: [CompanionForm: String] = [
            .corePearl: "Core pearl", .orbitField: "Orbit field", .lightForm: "Light Form",
            .light: "Guide light", .particle: "Particle light", .companion: "Companion"
        ]
        for (form, identifier) in expected {
            XCTAssertEqual(form.rawValue, identifier)
            XCTAssertTrue(CompanionForm.starterChoices.contains(form))
            XCTAssertEqual(try JSONDecoder().decode(CompanionForm.self,
                from: JSONEncoder().encode(form)), form)
            var preferences = CompanionPreferences()
            preferences.form = form
            let saved = try NativePreferenceDocument(preferences: preferences).encoded()
            XCTAssertEqual(try NativePreferenceDocument.decode(saved).preferences, preferences)
        }
        XCTAssertEqual(CompanionPreferences().form, .companion)
        XCTAssertFalse(CompanionForm.starterChoices.contains(where: \.isKin))
        XCTAssertThrowsError(try JSONDecoder().decode(CompanionForm.self, from: Data(#""light form""#.utf8)))
    }

    @MainActor
    func testChangingLightFormPreservesPlacementContextIndividualAndProviderActivity() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assistant = LightFormStateAssistant()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"), assistant: assistant)
        store.placed(at: CGPoint(x: 381, y: 93))
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        store.preferences.visualTreatment = .pearlStudy
        store.preferences.quiet = true
        store.evolution.observeJourneyOrigin(String(repeating: "a", count: 64))
        store.evolution.confirmRole(.muse)
        store.evolution.confirmHelpStyle(.reflective)
        let panel = CompanionPanelController(store: store)
        defer { panel.window.orderOut(nil) }
        // AppKit establishes and records the initial native frame when the
        // panel is created. Appearance changes must preserve that live frame.
        let frame = panel.window.frame
        let originalPreferences = store.preferences
        let position = store.position, placement = store.placementRevision
        let context = store.contextTicket(), settings = store.nextReplySettings
        let natural = store.evolution.naturalVariation, origin = store.evolution.origin
        let history = store.evolution.history, preferences = store.evolution.preferences
        let receipts = store.evolution.usefulReceipts, practices = store.evolution.reviewedPractices
        for form in forms + [.particle, .light, .companion] {
            if form.isOpticalLight { store.chooseLightForm(form) }
            else { store.chooseStartingForm(form) }
            var expected = originalPreferences
            expected.form = form
            XCTAssertEqual(store.preferences, expected)
            XCTAssertEqual(store.presentationForm, form)
            XCTAssertEqual(store.position, position)
            XCTAssertEqual(store.placementRevision, placement)
            XCTAssertEqual(panel.window.frame, frame)
            XCTAssertEqual(panel.window.contentView?.accessibilityValue() as? String, store.assistantAccessibilityValue)
            XCTAssertEqual(store.contextTicket(), context)
            XCTAssertEqual(store.nextReplySettings, settings)
            XCTAssertEqual(store.evolution.origin, origin)
            XCTAssertEqual(store.evolution.naturalVariation, natural)
            XCTAssertEqual(store.evolution.history, history)
            XCTAssertEqual(store.evolution.preferences, preferences)
            XCTAssertEqual(store.evolution.usefulReceipts, receipts)
            XCTAssertEqual(store.evolution.reviewedPractices, practices)
            XCTAssertEqual(store.assistantActivity, .idle)
            XCTAssertEqual(store.reactor.state, .idle)
            XCTAssertFalse(store.isWorking)
            XCTAssertNil(store.keptQiMon)
        }
        XCTAssertEqual(assistant.connectCount, 0)
        XCTAssertEqual(assistant.replyCount, 0)
        XCTAssertEqual(assistant.disconnectCount, 0)
    }

    @MainActor
    func testEachLightFormUsesExistingExplicitSaveAndReopen() throws {
        for form in forms {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("preferences.json")
            let store = CompanionStore(preferenceURL: url, assistant: LightFormStateAssistant())
            store.chooseLightForm(form)
            store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
            store.preferences.tone = "Direct"
            store.preferences.reduceMotion = true
            store.savePreferences()
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            store.rememberPreferences = true
            store.savePreferences()
            let reopened = CompanionStore(preferenceURL: url, assistant: LightFormStateAssistant())
            XCTAssertEqual(reopened.preferences, store.preferences)
            XCTAssertEqual(reopened.presentationForm, form)
            XCTAssertEqual(reopened.evolution.origin, form)
            XCTAssertNil(reopened.evolution.activeFamily)
            XCTAssertNil(reopened.keptQiMon)
            XCTAssertTrue(reopened.evolution.history.isEmpty)
            XCTAssertTrue(reopened.rememberPreferences)
        }
    }

    @MainActor
    func testNewOriginSurvivesEvolutionPersistenceAndReturnToStarter() throws {
        for form in forms {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("evolution.json")
            let evolution = EvolutionStore(origin: form, saveURL: url)
            let digest = String(repeating: "b", count: 64)
            evolution.observeJourneyOrigin(digest)
            XCTAssertTrue(evolution.bindPracticeJourney(digest))
            evolution.confirmFamily(.lumen)
            XCTAssertTrue(evolution.keepEvolution(try XCTUnwrap(evolution.proposeEvolution())))
            let natural = evolution.naturalVariation, history = evolution.history
            XCTAssertTrue(evolution.save())
            let reopened = EvolutionStore(saveURL: url)
            XCTAssertTrue(reopened.load())
            XCTAssertEqual(reopened.origin, form)
            XCTAssertEqual(reopened.activeFamily, .lumen)
            XCTAssertEqual(reopened.history, history)
            XCTAssertEqual(reopened.naturalVariation, natural)
            reopened.returnToStarter()
            XCTAssertEqual(reopened.origin, form)
            XCTAssertNil(reopened.activeFamily)
            XCTAssertEqual(reopened.history.last?.kind, .returned)
            XCTAssertEqual(reopened.naturalVariation, natural)
        }
    }

    @MainActor
    func testEarlierLightPreferencesKeepTheSameQiMonAndNowPresentCoreSeed() throws {
        for form in forms {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("preferences.json")
            let individual = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64),
                welcomedAt: Date(timeIntervalSince1970: 1_789_000_000))
            var preferences = CompanionPreferences()
            preferences.form = form
            preferences.equipment = CompanionEquipment(hand: .focusStaff)
            preferences.tone = "Direct"
            let oldDocument = NativePreferenceDocument(preferences: preferences, qiMon: individual)
            let bytes = try oldDocument.encoded()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bytes.write(to: url)
            let store = CompanionStore(preferenceURL: url, assistant: LightFormStateAssistant())
            XCTAssertEqual(store.preferences, preferences, "Legacy preference decoding must not silently rewrite a save")
            store.observeQiMonJourney(qiMonProjection())
            let context = store.contextTicket(), placement = store.placementRevision
            let history = store.evolution.history
            XCTAssertEqual(store.activeQiMon, individual)
            XCTAssertEqual(store.activeQiMon?.currentBody, .kinSeed)
            XCTAssertEqual(store.presentationForm, .kinSeed)
            XCTAssertEqual(store.presentationTitle, "KIN")
            XCTAssertNil(store.presentationFamily)
            for attempted in forms + [.kinSeed, .particle] {
                store.chooseStartingForm(attempted)
                store.chooseLightForm(attempted)
                XCTAssertEqual(store.activeQiMon, individual)
                XCTAssertEqual(store.presentationForm, .kinSeed)
                XCTAssertEqual(store.preferences, preferences)
                XCTAssertEqual(store.contextTicket(), context)
                XCTAssertEqual(store.placementRevision, placement)
                XCTAssertEqual(store.evolution.history, history)
                XCTAssertEqual(try Data(contentsOf: url), bytes)
            }
            store.observeQiMonJourney(nil)
            XCTAssertNil(store.activeQiMon, "No saved preference may claim a QiMon without its verified Journey")
            XCTAssertEqual(store.keptQiMon, individual)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            store.observeQiMonJourney(qiMonProjection())
            XCTAssertEqual(store.presentationForm, .kinSeed)
            store.savePreferences()
            let reopened = CompanionStore(preferenceURL: url, assistant: LightFormStateAssistant())
            reopened.observeQiMonJourney(qiMonProjection())
            XCTAssertEqual(reopened.activeQiMon, individual)
            XCTAssertEqual(reopened.presentationForm, .kinSeed)
            XCTAssertEqual(reopened.preferences, preferences)
        }
    }

    private func qiMonProjection() -> HostedPlayProjection {
        HostedPlayProjection(version: 3, host: "archi-desktop", sessionId: UUID().uuidString,
            sequence: 1, kind: "journey-projection", readiness: .ready, storage: .localBrowser, mode: .habitat,
            journeyId: "ARCHI-AAAAAAAA", revision: "saved-revision", eventCount: 4, visible: false,
            originDigest: String(repeating: "a", count: 64), practices: [], arena: nil)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("archi-light-form-state-\(UUID().uuidString)")
    }
}

@MainActor
private final class LightFormStateAssistant: AssistantClient {
    var connectCount = 0
    var replyCount = 0
    var disconnectCount = 0
    func connect() async throws { connectCount += 1 }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        replyCount += 1
    }
    func disconnect() { disconnectCount += 1 }
}
