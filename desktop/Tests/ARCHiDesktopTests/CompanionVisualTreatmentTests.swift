import AppKit
import XCTest
@testable import ARCHiDesktop

final class CompanionVisualTreatmentTests: XCTestCase {
    func testHistoricalPreferencesKeepValuesAndDefaultToOriginal() throws {
        let old = Data(#"{"form":"Companion","tone":"Warm","replyLength":0.6,"size":1.2,"adaptive":false,"reduceMotion":true,"quiet":true}"#.utf8)
        let decoded = try JSONDecoder().decode(CompanionPreferences.self, from: old)
        XCTAssertEqual(decoded.visualTreatment, .original)
        XCTAssertEqual(decoded.tone, "Warm")
        XCTAssertEqual(decoded.size, 1.2)
        XCTAssertEqual(decoded.replyLength, 0.6)
        XCTAssertFalse(decoded.adaptive)
        XCTAssertTrue(decoded.reduceMotion && decoded.quiet)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        object["visualTreatment"] = "unsupported future treatment"
        XCTAssertThrowsError(try JSONDecoder().decode(CompanionPreferences.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    @MainActor
    func testPearlUsesExistingExplicitPreferenceSaveAndReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let store = CompanionStore(preferenceURL: url)
        store.preferences.visualTreatment = .pearlStudy
        store.savePreferences()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        store.rememberPreferences = true
        store.savePreferences()
        let reopened = CompanionStore(preferenceURL: url)
        XCTAssertEqual(reopened.preferences.visualTreatment, .pearlStudy)
        XCTAssertEqual(reopened.preferences.form, .companion)
        reopened.preferences.visualTreatment = .original
        reopened.savePreferences()
        XCTAssertEqual(CompanionStore(preferenceURL: url).preferences.visualTreatment, .original)
    }

    @MainActor
    func testTreatmentDoesNotMoveOrReturnAnEvolvedCompanion() throws {
        let store = CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"))
        store.placed(at: CGPoint(x: 421, y: 83))
        store.evolution.confirmRole(.muse)
        store.evolution.confirmHelpStyle(.exploratory)
        store.evolution.confirmFamily(.fen)
        let digest = String(repeating: "a", count: 64)
        for _ in 0..<2 {
            let receipt = AssistantLaneReceipt(requestID: UUID().uuidString, route: .local, provider: .qwen,
                context: store.contextTicket(), inputDigest: digest, sourceDigest: digest,
                inputContract: "synthetic-treatment-test/v1", deadline: .distantFuture, modelIdentity: nil, state: .complete)
            XCTAssertTrue(store.evolution.markUseful(receipt: receipt, sourceDigest: digest))
        }
        XCTAssertNotNil(store.evolution.proposeEvolution())
        XCTAssertTrue(store.evolution.keepEvolution())
        let history = store.evolution.history, revision = store.evolution.revision, placement = store.placementRevision
        store.preferences.visualTreatment = .pearlStudy
        XCTAssertEqual(store.position, CGPoint(x: 421, y: 83))
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.preferences.form, .companion)
        XCTAssertEqual(store.evolution.origin, .companion)
        XCTAssertEqual(store.evolution.activeFamily, .fen)
        XCTAssertEqual(store.evolution.history, history)
        XCTAssertEqual(store.evolution.revision, revision)
    }

    @MainActor
    func testReviewedAssetRendersThroughNativeSnapshotAndRetainsFallbackIdentity() throws {
        XCTAssertNotNil(CompanionVisualAsset.image, "The real bundled asset must load, not silently fall back")
        let original = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: nil))
        let pearl = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: nil, treatment: .pearlStudy))
        XCTAssertNotEqual(original, pearl)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: pearl))
        XCTAssertEqual(bitmap.pixelsWide, 512)
        XCTAssertEqual(bitmap.pixelsHigh, 512)
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertLessThan(pearl.count, CompanionVisualAsset.maximumBytes)
        XCTAssertEqual(CompanionVisualAsset.appearanceID(form: .companion, family: nil, treatment: .pearlStudy, assetAvailable: false), "Companion:origin")
        for form in CompanionForm.allCases where form != .companion {
            XCTAssertEqual(CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original),
                           CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .pearlStudy))
        }
        XCTAssertEqual(CompanionVisualAsset.appearanceID(form: .companion, family: .fen, treatment: .original),
                       CompanionVisualAsset.appearanceID(form: .companion, family: .fen, treatment: .pearlStudy))
    }

    @MainActor
    func testLumenUsesItsReviewedAssetAndTheSameSnapshotBridge() throws {
        XCTAssertNotNil(CompanionVisualAsset.lumenImage)
        let original = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: .lumen, treatment: .original))
        let lumen = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: .lumen, treatment: .pearlStudy))
        XCTAssertNotEqual(original, lumen)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: lumen))
        XCTAssertEqual(bitmap.pixelsWide, 512)
        XCTAssertEqual(bitmap.pixelsHigh, 512)
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertLessThan(lumen.count, CompanionVisualAsset.maximumBytes)
        XCTAssertTrue(CompanionVisualAsset.appearanceID(form: .companion, family: .lumen, treatment: .pearlStudy).contains(CompanionVisualAsset.lumenRevision))
        XCTAssertEqual(CompanionVisualAsset.appearanceID(form: .companion, family: .lumen, treatment: .pearlStudy, assetAvailable: false), "Companion:lumen")
        XCTAssertEqual(CompanionVisualAsset.label(form: .companion, family: .lumen, treatment: .pearlStudy), "Lumen · Pearl study")
    }

    @MainActor
    func testMalformedOversizeAndWrongDimensionArtAreRejected() throws {
        XCTAssertNil(CompanionVisualAsset.decode(Data("not a PNG".utf8)))
        XCTAssertNil(CompanionVisualAsset.decode(Data(repeating: 0, count: CompanionVisualAsset.maximumBytes)))
        let small = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(small.representation(using: .png, properties: [:]))
        XCTAssertNil(CompanionVisualAsset.decode(png))
    }
}
