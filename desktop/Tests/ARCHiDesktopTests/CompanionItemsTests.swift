import XCTest
@testable import ARCHiDesktop

final class CompanionItemsTests: XCTestCase {
    private let historicalPreferences = Data(#"{"form":"Ink","tone":"Warm","replyLength":0.6,"size":1.2,"adaptive":false,"reduceMotion":true,"quiet":true}"#.utf8)

    func testBundledStaffDescribesTheDesignWithoutIssuingAnItem() {
        let staff = CompanionItemID.focusStaff.item
        XCTAssertEqual(CompanionItemID.allCases, [.focusStaff])
        XCTAssertEqual(staff.id, .focusStaff)
        XCTAssertEqual(staff.title, "Focus Staff")
        XCTAssertEqual(staff.creator, "Hampton")
        XCTAssertEqual(staff.provenanceLabel, "Bundled design")
        XCTAssertFalse(staff.summary.isEmpty)
        XCTAssertFalse(staff.effectDescription.isEmpty)
        XCTAssertEqual(CompanionEquipment(hand: .focusStaff).item, staff)
        XCTAssertNil(CompanionEquipment.empty.item)
    }

    func testEquipmentIsEmptyByDefaultAndHasStableDesignOnlyIdentity() throws {
        let empty = CompanionEquipment.empty
        let staff = CompanionEquipment(hand: .focusStaff)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(staff.isEmpty)
        XCTAssertEqual(empty.canonicalIdentity, "archi-companion-equipment/v1\nhand=none\n")
        XCTAssertEqual(staff.canonicalIdentity, "archi-companion-equipment/v1\nhand=focus-staff/v1\n")
        XCTAssertEqual(try JSONDecoder().decode(CompanionEquipment.self, from: JSONEncoder().encode(staff)), staff)
        XCTAssertEqual(try JSONDecoder().decode(CompanionEquipment.self, from: Data("{}".utf8)), empty)
        XCTAssertEqual(try JSONDecoder().decode(CompanionEquipment.self, from: Data(#"{"hand":null}"#.utf8)), empty)
        var preferences = CompanionPreferences()
        preferences.equipment = staff
        let identity = preferences.equipment.canonicalIdentity
        preferences.form = .ribbon
        preferences.visualTreatment = .pearlStudy
        preferences.tone = "Direct"
        preferences.quiet = true
        XCTAssertEqual(preferences.equipment.canonicalIdentity, identity)
    }

    func testHistoricalBareAndEnvelopePreferencesDoNotEquipAnything() throws {
        let decoded = try JSONDecoder().decode(CompanionPreferences.self, from: historicalPreferences)
        XCTAssertEqual(decoded.equipment, .empty)
        XCTAssertEqual(decoded.form, .ink)
        XCTAssertEqual(decoded.visualTreatment, .original)
        XCTAssertEqual(decoded.tone, "Warm")
        XCTAssertEqual(decoded.replyLength, 0.6)
        XCTAssertEqual(decoded.size, 1.2)
        XCTAssertFalse(decoded.adaptive)
        XCTAssertTrue(decoded.reduceMotion && decoded.quiet)
        XCTAssertEqual(try NativePreferenceDocument.decode(historicalPreferences).preferences, decoded)
        let fields = try JSONSerialization.jsonObject(with: historicalPreferences)
        let envelope = try JSONSerialization.data(withJSONObject: [
            "schema": NativePreferenceDocument.currentSchema, "revision": 4,
            "preferences": fields, "lessons": []
        ])
        XCTAssertEqual(try NativePreferenceDocument.decode(envelope).preferences, decoded)
    }

    func testMalformedEquipmentCannotSilentlyBecomeEmpty() throws {
        for value in [
            #"{"hand":"unknown-item/v1"}"#, #"{"hand":"FOCUS-STAFF/V1"}"#,
            #"{"hand":17}"#, #"{"hand":{}}"#, #"{"back":"focus-staff/v1"}"#,
            #"{"hand":"focus-staff/v1","power":100}"#, #"[]"#, #""focus-staff/v1""#
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(CompanionEquipment.self, from: Data(value.utf8)), value)
            var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: historicalPreferences) as? [String: Any])
            fields["equipment"] = try JSONSerialization.jsonObject(with: Data(value.utf8), options: .fragmentsAllowed)
            let preferences = try JSONSerialization.data(withJSONObject: fields)
            XCTAssertThrowsError(try JSONDecoder().decode(CompanionPreferences.self, from: preferences), value)
            XCTAssertThrowsError(try NativePreferenceDocument.decode(preferences), value)
        }
    }

    func testPreferenceDocumentRetainsEquipmentAndRejectsDuplicateItemKeys() throws {
        var preferences = CompanionPreferences()
        preferences.equipment = CompanionEquipment(hand: .focusStaff)
        let document = NativePreferenceDocument(revision: 9, preferences: preferences)
        let data = try document.encoded()
        XCTAssertEqual(try NativePreferenceDocument.decode(data), document)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let duplicate = text.replacingOccurrences(of: #""equipment":{"#,
            with: #""equipment":{"hand":null,"#)
        XCTAssertNotEqual(duplicate, text)
        XCTAssertThrowsError(try NativePreferenceDocument.decode(Data(duplicate.utf8)))
    }

    @MainActor
    func testExistingPreferenceSaveReloadAndUnequipRetainOtherChoices() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let store = CompanionStore(preferenceURL: url)
        XCTAssertEqual(store.preferences.equipment, .empty)
        store.preferences.form = .ink
        store.preferences.tone = "Warm"
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        store.savePreferences()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        store.rememberPreferences = true
        store.savePreferences()
        let reopened = CompanionStore(preferenceURL: url)
        XCTAssertEqual(reopened.preferences.equipment.hand, .focusStaff)
        XCTAssertEqual(reopened.preferences.form, .ink)
        XCTAssertEqual(reopened.preferences.tone, "Warm")
        XCTAssertTrue(reopened.rememberPreferences)
        reopened.preferences.equipment = .empty
        reopened.savePreferences()
        let unequipped = CompanionStore(preferenceURL: url)
        XCTAssertEqual(unequipped.preferences.equipment, .empty)
        XCTAssertEqual(unequipped.preferences.form, .ink)
        XCTAssertEqual(unequipped.preferences.tone, "Warm")
    }

    @MainActor
    func testUnknownSavedItemPreservesFileAndDoesNotEquipOnOpen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: historicalPreferences) as? [String: Any])
        fields["equipment"] = ["hand": "unknown-item/v1"]
        let original = try JSONSerialization.data(withJSONObject: fields)
        try original.write(to: url)
        let store = CompanionStore(preferenceURL: url)
        XCTAssertEqual(store.preferences.equipment, .empty)
        XCTAssertFalse(store.rememberPreferences)
        store.rememberPreferences = true
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        store.savePreferences()
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
