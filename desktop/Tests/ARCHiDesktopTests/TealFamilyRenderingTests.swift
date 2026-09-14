import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class TealFamilyRenderingTests: XCTestCase {
    private let forms: [CompanionForm] = [.constellation, .sprout, .ribbonSpirit, .geode]

    @MainActor
    func testReviewedBodiesLoadOnlyTheirExactBundledBytes() throws {
        var digests = Set<String>()
        for form in forms {
            let body = try XCTUnwrap(CompanionVisualAsset.tealBody(for: form))
            let url = try XCTUnwrap(CompanionVisualAsset.resourceURL(named: body.filename))
            let data = try Data(contentsOf: url)
            XCTAssertTrue(digests.insert(body.digest).inserted)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), body.digest)
            XCTAssertNotNil(CompanionVisualAsset.verifiedImage(data, expectedDigest: body.digest))
            XCTAssertNotNil(CompanionVisualAsset.resolvedImage(form: form, family: nil, treatment: .original))
            XCTAssertNil(CompanionVisualAsset.verifiedImage(data, expectedDigest: String(repeating: "0", count: 64)))
            var corrupt = data
            corrupt[corrupt.count / 2] ^= 1
            XCTAssertNil(CompanionVisualAsset.verifiedImage(corrupt, expectedDigest: body.digest))
            try inspectFrame(data, pixels: 512)
        }
        XCTAssertNil(CompanionVisualAsset.tealBody(for: .particle), "The native animated light has no new asset dependency")
    }

    @MainActor
    func testChosenStarterAndLabelIgnorePearlAndUnappliedRecipeSettings() throws {
        let natural = try XCTUnwrap(CompanionNaturalVariation.make(originDigest: String(repeating: "a", count: 64)))
        let recipe = try XCTUnwrap(CompanionAppearanceRecipe.make(originDigest: natural.originDigest,
            family: .lumen, role: .muse, helpStyle: .reflective, basisKind: .usefulWork))
        for form in forms {
            let baseline = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil))
            let baselineID = CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original)
            for treatment in CompanionVisualTreatment.allCases {
                XCTAssertEqual(CompanionVisualAsset.label(form: form, family: nil, treatment: treatment), form.rawValue)
                XCTAssertEqual(CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: treatment), baselineID)
                let rendered = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil, treatment: treatment))
                let comparison = try NaturalPresentationComparison.compare(baseline, rendered)
                XCTAssertTrue(comparison.alphaEqual && comparison.withinAlphaPresentationBound,
                    "A legacy treatment must not replace, tint or relabel the selected \(form.rawValue)")
            }
            let historicalInputs = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil,
                treatment: .pearlStudy, recipe: recipe, naturalVariation: natural))
            let comparison = try NaturalPresentationComparison.compare(baseline, historicalInputs)
            XCTAssertTrue(comparison.alphaEqual && comparison.withinAlphaPresentationBound)
            XCTAssertEqual(CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .pearlStudy,
                recipe: recipe, naturalVariation: natural), baselineID)
            XCTAssertEqual(CompanionVisualAsset.label(form: form, family: nil, treatment: .pearlStudy,
                recipe: recipe, naturalVariation: natural), form.rawValue)
        }
    }

    @MainActor
    func testActiveEvolutionStillChangesTheNewStarterBodyLabelAndCache() throws {
        for form in forms {
            let starter = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil))
            var identities: Set<String> = [CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original)]
            for family in EvolutionFamily.allCases {
                let recipe = try XCTUnwrap(CompanionAppearanceRecipe.make(originDigest: String(repeating: "b", count: 64),
                    family: family, role: .muse, helpStyle: .reflective, basisKind: .usefulWork))
                XCTAssertNil(CompanionVisualAsset.resolvedImage(form: form, family: family, treatment: .pearlStudy),
                    "An active family must pass through the existing evolved renderer")
                let evolved = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: family, recipe: recipe))
                XCTAssertNotEqual(starter, evolved)
                let existingPath = try XCTUnwrap(CompanionPresenceArt.png(form: .ink, family: family, recipe: recipe))
                let comparison = try NaturalPresentationComparison.compare(evolved, existingPath)
                XCTAssertTrue(comparison.alphaEqual && comparison.withinAlphaPresentationBound)
                XCTAssertTrue(CompanionVisualAsset.label(form: form, family: family, treatment: .original,
                    recipe: recipe).hasPrefix(family.title))
                XCTAssertTrue(identities.insert(CompanionVisualAsset.appearanceID(form: form, family: family,
                    treatment: .original, recipe: recipe)).inserted)
            }
        }
    }

    @MainActor
    func testAssetFallbackAndEquipmentEachHaveDistinctBoundedCacheIdentity() throws {
        var bodyIDs = Set<String>()
        let staff = CompanionEquipment(hand: .focusStaff)
        for form in forms {
            let body = try XCTUnwrap(CompanionVisualAsset.tealBody(for: form))
            let availableID = CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original, assetAvailable: true)
            let canonical = "archi-teal-body/v1\n\(body.filename)\nsha256=\(body.digest)\n"
            let expectedHash = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(availableID, "t1-\(expectedHash)", "The complete asset digest belongs in the cache key")
            let fallbackID = CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original, assetAvailable: false)
            let equippedID = CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original, equipment: staff)
            for id in [availableID, fallbackID, equippedID] {
                XCTAssertTrue(bodyIDs.insert(id).inserted)
                XCTAssertLessThanOrEqual("\(id)-expression-\(UInt64.max)".count, 100)
            }
            XCTAssertEqual(CompanionVisualAsset.label(form: form, family: nil, treatment: .pearlStudy, equipment: staff),
                "\(form.rawValue) · Focus Staff")
            let base = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil))
            let equipped = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil, equipment: staff))
            XCTAssertNotEqual(base, equipped)
            try inspectFrame(equipped, pixels: 512)
        }
    }

    @MainActor
    func testFallbackBodiesStayVisibleDistinctAndInsideTheOriginalFrame() throws {
        var fallbackHashes = Set<String>()
        for form in forms {
            for pixels in [64, 180, 512] {
                let data = try render(CompanionArt(form: form, size: CGFloat(pixels), reduceMotion: true))
                try inspectFrame(data, pixels: pixels)
                if pixels == 512 {
                    XCTAssertTrue(fallbackHashes.insert(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()).inserted)
                    XCTAssertNotEqual(data, CompanionPresenceArt.png(form: form, family: nil),
                        "A fallback must remain a safe local substitute, not be mistaken for the reviewed asset")
                }
            }
        }
    }

    @MainActor
    func testSharedStaticBodiesHaveTransparentEdgesAtDesktopAndHostedSizes() throws {
        let output = ProcessInfo.processInfo.environment["ARCHI_TEAL_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for form in forms {
            let name = try XCTUnwrap(CompanionVisualAsset.tealBody(for: form)).filename
            for pixels in [64, 180, 512] {
                let data = try render(CompanionPresenceArt(form: form, family: nil, size: CGFloat(pixels), reduceMotion: true))
                try inspectFrame(data, pixels: pixels)
                if let output { try data.write(to: output.appendingPathComponent("\(name)-\(pixels).png")) }
                // New static bodies do not manufacture a motion path. Compare
                // the app preference directly; the read-only system setting
                // reaches this same static branch without creating a timeline.
                let enabled = try render(CompanionPresenceArt(form: form, family: nil, size: CGFloat(pixels), reduceMotion: false))
                let comparison = try NaturalPresentationComparison.compare(data, enabled)
                XCTAssertTrue(comparison.alphaEqual && comparison.withinAlphaPresentationBound)
            }
            if let output {
                let sheet = HStack(spacing: 0) {
                    sample(form).background(Color(red: 0.07, green: 0.09, blue: 0.09))
                    sample(form).background(Color(red: 0.96, green: 0.97, blue: 0.95))
                }
                try render(sheet).write(to: output.appendingPathComponent("\(name)-review.png"))
            }
        }
    }

    @MainActor private func sample(_ form: CompanionForm) -> some View {
        VStack(spacing: 12) {
            CompanionPresenceArt(form: form, family: nil, size: 512, reduceMotion: true)
            HStack(spacing: 28) {
                CompanionPresenceArt(form: form, family: nil, size: 64, reduceMotion: true)
                CompanionPresenceArt(form: form, family: nil, size: 180, reduceMotion: true,
                    equipment: CompanionEquipment(hand: .focusStaff))
            }
        }.padding(24)
    }

    @MainActor private func render<V: View>(_ view: V) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let tiff = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    @MainActor private func inspectFrame(_ data: Data, pixels: Int) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, pixels)
        XCTAssertEqual(bitmap.pixelsHigh, pixels)
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertLessThan(data.count, CompanionVisualAsset.maximumBytes)
        for i in 0..<pixels {
            for (x, y) in [(i, 0), (i, pixels - 1), (0, i), (pixels - 1, i)] {
                XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0,
                    "The body must leave a transparent margin in its unchanged frame")
            }
        }
        var visibleSamples = 0
        for y in stride(from: 0, to: pixels, by: max(1, pixels / 32)) {
            for x in stride(from: 0, to: pixels, by: max(1, pixels / 32)) {
                if try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent > 0.1 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 20, "A decoded but empty or nearly invisible body is not a usable fallback")
    }
}
