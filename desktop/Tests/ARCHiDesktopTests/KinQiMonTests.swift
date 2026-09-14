import AppKit
import XCTest
@testable import ARCHiDesktop

final class KinQiMonTests: XCTestCase {
    private let origin = String(repeating: "a", count: 64)
    private let otherOrigin = String(repeating: "b", count: 64)

    private func projection(_ origin: String?, storage: HostedPlayProjection.Storage = .localBrowser) -> HostedPlayProjection {
        HostedPlayProjection(version: 3, host: "archi-desktop", sessionId: UUID().uuidString,
            sequence: 1, kind: "journey-projection", readiness: .ready, storage: storage, mode: .habitat,
            journeyId: "ARCHI-AAAAAAAA", revision: "saved-revision", eventCount: 4, visible: false,
            originDigest: origin, practices: [], arena: nil)
    }

    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kin-tests-\(UUID().uuidString)/preferences.json")
    }

    @MainActor
    func testPersonalQiMonCannotBeReplacedByAStarterChoiceAndSurvivesReopen() throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let store = CompanionStore(preferenceURL: url, wallClock: { now })
        store.preferences.tone = "Warm"
        store.preferences.size = 1.2
        store.observeQiMonJourney(projection(origin))
        let placement = store.placementRevision
        XCTAssertTrue(store.welcomeKin())
        XCTAssertEqual(store.activeQiMon?.originDigest, origin)
        XCTAssertEqual(store.activeQiMon?.welcomedAt, now)
        XCTAssertEqual(store.activeQiMon?.name, "KIN")
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.preferences.form, .companion)
        XCTAssertEqual(store.presentationForm, .kinSeed)
        XCTAssertFalse(store.canChooseStartingForm)
        XCTAssertEqual(store.preferences.tone, "Warm")
        XCTAssertEqual(store.preferences.size, 1.2)
        let original = store.keptQiMon
        for form in [CompanionForm.kinSpark, .kin, .kinSimple, .light, .kinSeed] {
            store.chooseStartingForm(form)
            store.savePreferences()
            let reopened = CompanionStore(preferenceURL: url)
            XCTAssertNil(reopened.activeQiMon, "The current Journey must be observed before assigning a name.")
            reopened.observeQiMonJourney(projection(origin))
            XCTAssertEqual(reopened.activeQiMon, original)
            XCTAssertEqual(reopened.preferences.form, .companion)
            XCTAssertEqual(reopened.presentationForm, .kinSeed)
            XCTAssertNil(reopened.presentationFamily)
        }
        let bytes = try Data(contentsOf: url)
        XCTAssertFalse(store.welcomeKin(), "Welcoming twice must not replace the first record.")
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(store.keptQiMon, original)
    }

    @MainActor
    func testLegacyKinSkinPreferencesResolveOnlyThroughTheSavedIndividual() throws {
        for legacy in [CompanionForm.kinSpark, .kinSimple, .kin, .kinSeed] {
            let url = location()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let kin = LocalQiMon(character: .kin, originDigest: origin, welcomedAt: Date(timeIntervalSince1970: 1))
            var preferences = CompanionPreferences(); preferences.form = legacy
            let document = NativePreferenceDocument(preferences: preferences, qiMon: kin)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = try document.encoded(); try bytes.write(to: url)
            let store = CompanionStore(preferenceURL: url)
            XCTAssertEqual(store.presentationForm, .companion, "A skin preference cannot assign KIN before his Journey is verified")
            store.observeQiMonJourney(projection(origin))
            XCTAssertEqual(store.activeQiMon, kin)
            XCTAssertEqual(store.presentationForm, .kinSeed)
            XCTAssertTrue(store.reactorReferenceMatchesCurrentAppearance)
            store.evolution.confirmFamily(.fen)
            XCTAssertTrue(store.evolution.keepEvolution(try XCTUnwrap(store.evolution.proposeEvolution())))
            XCTAssertNil(store.presentationFamily, "A generic family choice cannot turn the personal QiMon into another body")
            XCTAssertNil(store.presentationRecipe)
            let history = store.evolution.history
            store.returnEvolutionToStarter()
            XCTAssertEqual(store.evolution.history, history)
            XCTAssertEqual(store.presentationForm, .kinSeed)
            store.observeQiMonJourney(projection(otherOrigin))
            XCTAssertNil(store.activeQiMon)
            XCTAssertEqual(store.presentationForm, .companion)
            XCTAssertTrue(store.reactorReferenceMatchesCurrentAppearance)
            XCTAssertEqual(try Data(contentsOf: url), bytes, "Correcting presentation must not rewrite the saved individual or legacy preference")
        }
    }

    @MainActor
    func testUnnamedStarterCatalogueContainsNoPersonalKinAndCannotChooseOne() {
        XCTAssertFalse(CompanionForm.starterChoices.contains(where: \.isKin))
        let store = CompanionStore(preferenceURL: location())
        for form in CompanionForm.allCases.filter(\.isKin) {
            store.chooseStartingForm(form)
            XCTAssertEqual(store.preferences.form, .companion)
            XCTAssertNil(store.keptQiMon)
            XCTAssertFalse(store.evolution.hasUnsavedChanges)
        }
    }

    @MainActor
    func testOtherOrMissingJourneyRetiresNameWithoutRewritingSavedKin() throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = CompanionStore(preferenceURL: url)
        for invalid in [projection(origin, storage: .sessionOnly), projection(origin, storage: .qaEphemeral),
                        projection("short"), projection(nil)] {
            store.observeQiMonJourney(invalid)
            XCTAssertFalse(store.canWelcomeKin)
            XCTAssertFalse(store.welcomeKin())
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
        store.observeQiMonJourney(projection(origin))
        XCTAssertTrue(store.welcomeKin())
        let bytes = try Data(contentsOf: url)
        let ticket = store.contextTicket()
        store.observeQiMonJourney(projection(otherOrigin))
        XCTAssertNil(store.activeQiMon)
        XCTAssertFalse(store.canWelcomeKin)
        XCTAssertNotEqual(store.contextTicket(), ticket, "Retire replies captured for another companion.")
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        store.observeQiMonJourney(projection(origin))
        XCTAssertNotNil(store.activeQiMon)
        store.observeQiMonJourney(nil)
        XCTAssertNil(store.activeQiMon)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    @MainActor
    func testConflictCannotPublishNameOrChangeFormAndExportsExcludeIdentity() throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = CompanionStore(preferenceURL: url)
        let stale = CompanionStore(preferenceURL: url)
        first.observeQiMonJourney(projection(origin)); stale.observeQiMonJourney(projection(otherOrigin))
        XCTAssertTrue(first.welcomeKin())
        let bytes = try Data(contentsOf: url)
        XCTAssertFalse(stale.welcomeKin())
        XCTAssertNil(stale.keptQiMon)
        XCTAssertEqual(stale.preferences.form, .companion)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertNil(try NativePreferenceDocument.decode(first.lessonExportData()).qiMon)
        first.forgetPreferences()
        XCTAssertEqual(try NativePreferencePersistence.read(url).document.qiMon, first.keptQiMon)
    }

    func testKnownSchemaMigrationAndStrictIdentityFields() throws {
        for schema in ["archi-native-preferences/v2", "archi-native-preferences/v3"] {
            let bytes = Data("{\"schema\":\"\(schema)\",\"revision\":7,\"lessons\":[]}".utf8)
            let result = try NativePreferenceDocument.decode(bytes)
            XCTAssertEqual(result.revision, 7)
            XCTAssertNil(result.qiMon)
            XCTAssertEqual(result.schema, NativePreferenceDocument.currentSchema)
        }
        let record = LocalQiMon(character: .kin, originDigest: origin, welcomedAt: Date(timeIntervalSince1970: 1))
        let valid = try NativePreferenceDocument(qiMon: record).encoded()
        XCTAssertEqual(try NativePreferenceDocument.decode(valid).qiMon, record)
        for change in ["originDigest": "short", "character": "someone-else", "authority": "admin"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
            var kin = try XCTUnwrap(object["qiMon"] as? [String: Any])
            kin[change.key] = change.value; object["qiMon"] = kin
            XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)))
        }
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        old["schema"] = "archi-native-preferences/v3"
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: old)))
    }

    func testBothProvidersGetOnlyDisplayNameAndKeepTheirBoundaries() throws {
        let request = AssistantRequest(prompt: "Who are you?", sourceName: nil, sourceText: "",
            sourceRevision: 0, placementRevision: 0, tone: "Warm", replyLength: 0.35, companion: .kin)
        for input in [request.input, request.codexInput, request.localInput] {
            let json = try JSONDecoder().decode(JSONValue.self, from: Data(input.utf8))
            XCTAssertEqual(json["companion"], .object(["displayName": .string("KIN")]))
            for privateValue in [origin, "Hampton", "welcomedAt", "1988", "Maine"] {
                XCTAssertFalse(input.contains(privateValue))
            }
        }
        let local = LocalRoleRequest(id: "kin-test", role: .reasoning, input: .object([:]), outputSchema: .object([:]))
        for instructions in [local.systemInstruction, AssistantInstructions.groundedText, AssistantInstructions.passageRevisionText] {
            XCTAssertTrue(instructions.contains(AssistantInstructions.companionIdentityText))
        }
    }

    @MainActor
    func testThreeNativeFormsHaveDifferentTransparentStableSnapshots() throws {
        var outputs: [Data] = []
        for form in [CompanionForm.kinSpark, .kinSimple, .kin] {
            let bytes = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: bytes))
            XCTAssertEqual(bitmap.pixelsWide, 512)
            XCTAssertEqual(bitmap.pixelsHigh, 512)
            XCTAssertTrue(bitmap.hasAlpha)
            XCTAssertLessThan(bytes.count, CompanionVisualAsset.maximumBytes)
            for (x, y) in [(0, 0), (511, 0), (0, 511), (511, 511)] {
                XCTAssertEqual(bitmap.colorAt(x: x, y: y)?.alphaComponent, 0)
            }
            XCTAssertGreaterThan(bitmap.colorAt(x: 266, y: 307)?.alphaComponent ?? 0, 0.9)
            XCTAssertEqual(bytes, CompanionPresenceArt.png(form: form, family: nil))
            outputs.append(bytes)
            if let directory = ProcessInfo.processInfo.environment["ARCHI_KIN_RENDER_DIR"] {
                let target = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                let name = form == .kinSpark ? "kin-spark.png" : form == .kinSimple ? "kin-simple.png" : "kin-first-light-native.png"
                try bytes.write(to: target.appendingPathComponent(name))
            }
        }
        XCTAssertEqual(Set(outputs).count, 3)
    }
}
