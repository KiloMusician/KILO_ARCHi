import Foundation
import XCTest
@testable import ARCHiDesktop

final class FocusGesturePersistenceTests: XCTestCase {
    func testGestureIsBoundedAndPlaybackCapturesItsOwnConfiguration() throws {
        let standard = FocusGestureConfiguration()
        XCTAssertEqual(standard.pace, .gentle)
        XCTAssertEqual(standard.sparkle, .soft)
        XCTAssertEqual(standard.hold, .brief)
        for pace in FocusGestureConfiguration.Pace.allCases {
            for sparkle in FocusGestureConfiguration.Sparkle.allCases {
                for hold in FocusGestureConfiguration.Hold.allCases {
                    let configuration = FocusGestureConfiguration(pace: pace, sparkle: sparkle, hold: hold)
                    XCTAssertGreaterThan(configuration.duration, 0)
                    XCTAssertLessThanOrEqual(configuration.duration, 4)
                    let data = try JSONEncoder().encode(configuration)
                    XCTAssertEqual(try JSONDecoder().decode(FocusGestureConfiguration.self, from: data), configuration)
                    XCTAssertFalse(configuration.summary.isEmpty)
                }
            }
        }
        var draft = standard
        let previewID = UUID()
        let playback = FocusGesturePlayback(configuration: draft, startedAt: 20,
            purpose: .pointing, spatialPreviewID: previewID)
        draft.pace = .quick
        draft.sparkle = .none
        XCTAssertEqual(playback.configuration, standard)
        XCTAssertNotEqual(playback.configuration, draft)
        XCTAssertEqual(playback.spatialPreviewID, previewID)
        XCTAssertEqual(playback.purpose, .pointing)
    }

    func testPlaybackCannotBeFreshBeforeStartAtExpiryOrWithNonfiniteTime() {
        let playback = FocusGesturePlayback(startedAt: 10)
        XCTAssertTrue(playback.isFresh(at: 10))
        XCTAssertTrue(playback.isFresh(at: 10 + playback.configuration.duration - 0.001))
        XCTAssertFalse(playback.isFresh(at: 10 + playback.configuration.duration))
        XCTAssertFalse(playback.isFresh(at: 9.999))
        for invalid in [TimeInterval.nan, .infinity, -.infinity] {
            XCTAssertFalse(playback.isFresh(at: invalid))
            XCTAssertFalse(FocusGesturePlayback(startedAt: invalid).isFresh(at: 10))
        }
        XCTAssertFalse(FocusGesturePlayback(startedAt: -1).isFresh(at: 0))
    }

    func testVersionTwoMigrationPreservesAppearanceLessonsAndRevisionWithoutWriting() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        var preferences = CompanionPreferences()
        preferences.form = .particle
        preferences.tone = "Warm"
        preferences.replyLength = 0.8
        preferences.size = 1.4
        preferences.adaptive = false
        preferences.reduceMotion = true
        preferences.quiet = true
        let original = NativePreferenceDocument(revision: 8, preferences: preferences, lessons: [lesson()])
        var object = try dictionary(original)
        object["schema"] = "archi-native-preferences/v2"
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try bytes.write(to: url)

        let result = try NativePreferencePersistence.read(url)
        XCTAssertEqual(result.document.schema, "archi-native-preferences/v4")
        XCTAssertEqual(result.document.revision, original.revision)
        XCTAssertEqual(result.document.preferences, original.preferences)
        XCTAssertEqual(result.document.lessons, original.lessons)
        XCTAssertNil(result.document.focusGesture)
        XCTAssertEqual(result.baseline, bytes)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let reencoded = try dictionary(result.document)
        XCTAssertEqual(reencoded["schema"] as? String, "archi-native-preferences/v4")
        XCTAssertNil(reencoded["focusGesture"])
    }

    func testLegacyBarePreferencesAndAbsentGestureStayAbsent() throws {
        let legacy = Data("""
        {"form":"Guide light","tone":"Direct","replyLength":0.2,"size":1.1,"adaptive":true,"reduceMotion":true,"quiet":false}
        """.utf8)
        let migrated = try NativePreferenceDocument.decode(legacy)
        XCTAssertEqual(migrated.schema, "archi-native-preferences/v4")
        XCTAssertEqual(migrated.preferences?.form, .light)
        XCTAssertEqual(migrated.preferences?.tone, "Direct")
        XCTAssertEqual(migrated.preferences?.visualTreatment, .original)
        XCTAssertEqual(migrated.revision, 0)
        XCTAssertTrue(migrated.lessons.isEmpty)
        XCTAssertNil(migrated.focusGesture)

        var nullGesture = try dictionary(migrated)
        nullGesture["focusGesture"] = NSNull()
        XCTAssertNil(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: nullGesture)).focusGesture)
        var unknownLegacy = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        unknownLegacy["focusGesture"] = ["pace": "Gentle", "sparkle": "Soft", "hold": "Brief"]
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: unknownLegacy)))
    }

    func testGesturePersistsIndependentlyAndForgettingOtherDataCannotDeleteIt() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let gesture = FocusGestureConfiguration(pace: .unhurried, sparkle: .none, hold: .lingering)
        var document = NativePreferenceDocument(revision: 2, preferences: CompanionPreferences(),
            lessons: [lesson()], focusGesture: gesture)
        var bytes = try NativePreferencePersistence.write(document: document, to: url, expected: nil)
        XCTAssertEqual(try NativePreferencePersistence.read(url).document, document)

        document.preferences = nil
        document.revision += 1
        bytes = try NativePreferencePersistence.write(document: document, to: url, expected: bytes)
        XCTAssertEqual(try NativePreferencePersistence.read(url).document.focusGesture, gesture)
        XCTAssertEqual(try NativePreferencePersistence.read(url).document.lessons, document.lessons)
        document.lessons = []
        document.revision += 1
        bytes = try NativePreferencePersistence.write(document: document, to: url, expected: bytes)
        XCTAssertNotNil(bytes, "A gesture-only save must remain on disk.")
        XCTAssertEqual(try NativePreferencePersistence.read(url).document.focusGesture, gesture)
        XCTAssertNil(try NativePreferencePersistence.read(url).document.preferences)

        document.focusGesture = nil
        document.revision += 1
        XCTAssertNil(try NativePreferencePersistence.write(document: document, to: url, expected: bytes))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testUnknownMissingDuplicateOrInvalidGestureFieldsAreRejected() throws {
        let valid = try dictionary(NativePreferenceDocument(focusGesture: .init()))
        let invalidGestures: [Any] = [
            ["pace": "Gentle", "sparkle": "Soft", "hold": "Brief", "authority": true],
            ["pace": "Gentle", "sparkle": "Soft"],
            ["pace": "Ultra fast", "sparkle": "Soft", "hold": "Brief"],
            ["pace": "Gentle", "sparkle": "Explosive", "hold": "Brief"],
            ["pace": "Gentle", "sparkle": "Soft", "hold": "Forever"],
            ["pace": 1.2, "sparkle": "Soft", "hold": "Brief"],
            ["pace": "Gentle", "sparkle": NSNull(), "hold": "Brief"],
            [], "Gentle"
        ]
        for invalid in invalidGestures {
            var object = valid
            object["focusGesture"] = invalid
            XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)))
        }
        let duplicate = Data("""
        {"schema":"archi-native-preferences/v3","revision":1,"lessons":[],"focusGesture":{"pace":"Quick","p\\u0061ce":"Gentle","sparkle":"Soft","hold":"Brief"}}
        """.utf8)
        XCTAssertThrowsError(try NativePreferenceDocument.decode(duplicate))
        let extraStandalone = Data("""
        {"pace":"Gentle","sparkle":"Soft","hold":"Brief","duration":100}
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(FocusGestureConfiguration.self, from: extraStandalone))
    }

    func testVersionTwoCannotCarryTheNewFieldEvenWhenNull() throws {
        var object = try dictionary(NativePreferenceDocument(focusGesture: .init()))
        object["schema"] = "archi-native-preferences/v2"
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)))
        object["focusGesture"] = NSNull()
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)))
        object["schema"] = "archi-native-preferences/v999"
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)))
    }

    func testCorruptExternalSaveAndSizeLimitsPreserveConflictProtection() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let document = NativePreferenceDocument(revision: 1, lessons: [lesson()], focusGesture: .init())
        let baseline = try NativePreferencePersistence.write(document: document, to: url, expected: nil)
        var object = try dictionary(document)
        object["focusGesture"] = ["pace": "Gentle", "sparkle": "Soft", "hold": "Forever"]
        let corruptBytes = try JSONSerialization.data(withJSONObject: object)
        try corruptBytes.write(to: url)
        XCTAssertThrowsError(try NativePreferencePersistence.read(url))
        XCTAssertThrowsError(try NativePreferencePersistence.write(document: document, to: url, expected: baseline))
        XCTAssertEqual(try Data(contentsOf: url), corruptBytes)

        var tooLarge = try document.encoded()
        tooLarge.append(Data(repeating: 32, count: NativePreferenceDocument.maximumBytes + 1 - tooLarge.count))
        XCTAssertThrowsError(try NativePreferenceDocument.decode(tooLarge))
        let overfull = NativePreferenceDocument(lessons: (0...NativePreferenceDocument.maximumLessons).map { _ in lesson() },
            focusGesture: .init())
        XCTAssertThrowsError(try overfull.encoded())
    }

    private func dictionary(_ document: NativePreferenceDocument) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: document.encoded()) as? [String: Any])
    }

    private func lesson() -> KeptLesson {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return KeptLesson(topic: "drawing", text: "Start with a simple outline.", reason: "A useful practice habit.",
            source: LessonSource(name: "Practice.txt", digest: LessonSource.digest(of: "A sketch.")),
            origin: LessonOrigin(requestID: UUID().uuidString, inputDigest: LessonSource.digest(of: "Help with drawing")),
            createdAt: date, updatedAt: date.addingTimeInterval(30), expiresAt: date.addingTimeInterval(3600))
    }

    private func fixtureDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archi-focus-gesture-persistence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
