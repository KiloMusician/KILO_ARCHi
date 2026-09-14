import XCTest
@testable import ARCHiDesktop

final class CompanionHarmonyPreferenceTests: XCTestCase {
    func testEarlierPreferencesRemainSilentAndDecodeThroughExistingDocument() throws {
        let old = Data(#"{"form":"Companion","tone":"Calm","replyLength":0.35,"size":1,"adaptive":true,"reduceMotion":false,"quiet":false}"#.utf8)
        let preferences = try XCTUnwrap(NativePreferenceDocument.decode(old).preferences)
        XCTAssertFalse(preferences.musicalCues)
        XCTAssertEqual(preferences.musicalVolume, 0.35)
        XCTAssertTrue(preferences.isValid)
    }

    func testMusicUsesExistingPreferenceRoundTripWithoutChangingFormOrHelpStyle() throws {
        var preferences = CompanionPreferences()
        preferences.form = .kinSeed
        preferences.tone = "Warm"
        preferences.musicalCues = true
        preferences.musicalVolume = 0.42
        let original = NativePreferenceDocument(preferences: preferences)
        let decoded = try NativePreferenceDocument.decode(original.encoded())
        XCTAssertEqual(decoded.preferences, preferences)
        XCTAssertEqual(decoded.lessons, original.lessons)
        XCTAssertEqual(decoded.qiMon, original.qiMon)
    }

    func testVolumeRejectsNonfiniteAndOutOfBoundsValues() {
        for volume in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
            var preferences = CompanionPreferences()
            preferences.musicalVolume = volume
            XCTAssertFalse(preferences.isValid)
            XCTAssertThrowsError(try NativePreferenceDocument(preferences: preferences).encoded())
        }
        for volume in [0.0, 0.35, 1] {
            var preferences = CompanionPreferences()
            preferences.musicalVolume = volume
            XCTAssertTrue(preferences.isValid)
        }
    }
}
