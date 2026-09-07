import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class CompanionNaturalRenderingTests: XCTestCase {
    private func variation(_ origin: String = "a") throws -> CompanionNaturalVariation {
        try XCTUnwrap(CompanionNaturalVariation.make(originDigest: String(repeating: origin, count: 64)))
    }

    @MainActor
    func testNaturalVisibleBodySurvivesMixedScaleAndOriginRendering() throws {
        let first = try variation("1")
        let others = try [variation("2"), variation("3")]
        let baseline = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: nil,
            treatment: .pearlStudy, naturalVariation: first))
        for scale in [1.5, 1, 2] {
            for other in others {
                _ = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: nil,
                    treatment: .pearlStudy, naturalVariation: other))
            }
            let renderer = ImageRenderer(content: HStack {
                ForEach([first] + others, id: \.fingerprint) { natural in
                    CompanionPresenceArt(form: .companion, family: nil, size: 190, reduceMotion: true,
                        treatment: .pearlStudy, naturalVariation: natural)
                }
            }.environment(\.colorScheme, .light))
            renderer.scale = scale
            let preview = try XCTUnwrap(renderer.nsImage)
            _ = try XCTUnwrap(preview.tiffRepresentation)
            let repeated = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: nil,
                treatment: .pearlStudy, naturalVariation: try variation("1")))
            let comparison = try NaturalPresentationComparison.compare(baseline, repeated)
            XCTAssertEqual(first, try variation("1"), "Rendering never changes the origin-derived traits")
            XCTAssertTrue(comparison.dimensionsEqual)
            XCTAssertTrue(comparison.alphaEqual, "Every silhouette and transparency sample must remain exact")
            XCTAssertLessThanOrEqual(comparison.maximumRGBDifference, 2)
            XCTAssertLessThanOrEqual(comparison.meanRGBDifference, 0.1)
            XCTAssertTrue(comparison.withinAlphaPresentationBound)
        }
    }

    func testPresentationBoundRejectsGeometryPeakColorAndWidespreadColorChanges() throws {
        let baseline = try comparisonFixture()
        let allowedRounding = try NaturalPresentationComparison.compare(baseline, comparisonFixture(redDelta: 2))
        XCTAssertTrue(allowedRounding.withinAlphaPresentationBound)
        XCTAssertFalse(allowedRounding.exactPNGBytes, "Visible acceptance must not claim byte identity")
        XCTAssertFalse(try NaturalPresentationComparison.compare(baseline, comparisonFixture(redDelta: 3)).withinAlphaPresentationBound)
        XCTAssertFalse(try NaturalPresentationComparison.compare(baseline,
            comparisonFixture(redDelta: 1, changedPixels: 100)).withinAlphaPresentationBound)
        XCTAssertFalse(try NaturalPresentationComparison.compare(baseline, comparisonFixture(alpha: 254)).withinAlphaPresentationBound)
        XCTAssertFalse(try NaturalPresentationComparison.compare(baseline, comparisonFixture(width: 99)).withinAlphaPresentationBound)
        XCTAssertThrowsError(try NaturalPresentationComparison.compare(baseline, Data("invalid".utf8)))
    }

    private func comparisonFixture(width: Int = 100, redDelta: Int = 0, changedPixels: Int = 1, alpha: UInt8 = 255) throws -> Data {
        let bytes = (0..<width).flatMap { index -> [UInt8] in
            [UInt8(120 + (index < changedPixels ? redDelta : 0)), 130, 140, alpha]
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try XCTUnwrap(CGImage(width: width, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    @MainActor
    func testNaturalIndividualIsVisibleFromTheStarterAndContinuesIntoLumen() throws {
        let first = try variation()
        let recreated = try variation()
        let other = try variation("b")
        for family in [nil, EvolutionFamily.lumen] {
            for treatment in CompanionVisualTreatment.allCases {
                let plain = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: family, treatment: treatment))
                let personalized = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: family,
                    treatment: treatment, naturalVariation: first))
                let restored = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: family,
                    treatment: treatment, naturalVariation: recreated))
                let different = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: family,
                    treatment: treatment, naturalVariation: other))
                XCTAssertEqual(personalized, restored, "The same Journey origin must recover the same static appearance")
                XCTAssertNotEqual(personalized, different, "Different synthetic origins must produce individual variation")
                XCTAssertNotEqual(personalized, plain)
                try assertTransparentFrame(personalized, baseline: plain)
                try assertTransparentFrame(different, baseline: plain)
            }
        }
    }

    @MainActor
    func testKeptLegacyRecipeWinsWithoutChangingPixelsLabelsOrCacheIdentity() throws {
        let natural = try variation("b")
        for family in EvolutionFamily.allCases {
            let legacy = try XCTUnwrap(CompanionAppearanceRecipe.make(originDigest: String(repeating: "a", count: 64),
                family: family, role: .keeper, helpStyle: .reflective, basisKind: .usefulWork))
            for treatment in CompanionVisualTreatment.allCases {
                XCTAssertEqual(CompanionPresenceArt.png(form: .companion, family: family, treatment: treatment, recipe: legacy),
                    CompanionPresenceArt.png(form: .companion, family: family, treatment: treatment, recipe: legacy,
                        naturalVariation: natural))
                XCTAssertEqual(CompanionVisualAsset.label(form: .companion, family: family, treatment: treatment, recipe: legacy),
                    CompanionVisualAsset.label(form: .companion, family: family, treatment: treatment, recipe: legacy,
                        naturalVariation: natural))
                XCTAssertEqual(CompanionVisualAsset.appearanceID(form: .companion, family: family, treatment: treatment, recipe: legacy),
                    CompanionVisualAsset.appearanceID(form: .companion, family: family, treatment: treatment, recipe: legacy,
                        naturalVariation: natural))
            }
        }
    }

    @MainActor
    func testUnsupportedStartersAndFamiliesKeepTheirExistingDrawingAndCacheContract() throws {
        let natural = try variation()
        for form in CompanionForm.allCases {
            for family in [nil] + EvolutionFamily.allCases.map(Optional.some) {
                guard form != .companion || (family != nil && family != .lumen) else { continue }
                for treatment in CompanionVisualTreatment.allCases {
                    XCTAssertEqual(CompanionPresenceArt.png(form: form, family: family, treatment: treatment),
                        CompanionPresenceArt.png(form: form, family: family, treatment: treatment, naturalVariation: natural))
                    XCTAssertEqual(CompanionVisualAsset.label(form: form, family: family, treatment: treatment),
                        CompanionVisualAsset.label(form: form, family: family, treatment: treatment, naturalVariation: natural))
                    XCTAssertEqual(CompanionVisualAsset.appearanceID(form: form, family: family, treatment: treatment),
                        CompanionVisualAsset.appearanceID(form: form, family: family, treatment: treatment, naturalVariation: natural))
                }
            }
        }
    }

    @MainActor
    func testNaturalCacheBindsOriginFormAndAssetFallbackWithinExistingBridgeLimits() throws {
        let first = try variation()
        let other = try variation("b")
        var ids = Set<String>()
        for family in [nil, EvolutionFamily.lumen] {
            for available in [true, false] {
                let id = CompanionVisualAsset.appearanceID(form: .companion, family: family, treatment: .pearlStudy,
                    naturalVariation: first, assetAvailable: available)
                XCTAssertTrue(ids.insert(id).inserted, "Both body family and actual asset fallback belong in the cache identity")
                XCTAssertTrue(id.hasPrefix("n1-"))
                XCTAssertEqual(id.count, 67)
                XCTAssertLessThanOrEqual("\(id)-expression-\(UInt64.max)".count, 100)
                XCTAssertNotEqual(id, CompanionVisualAsset.appearanceID(form: .companion, family: family, treatment: .pearlStudy,
                    naturalVariation: other, assetAvailable: available))
                XCTAssertEqual(CompanionVisualAsset.appearanceID(form: .companion, family: family, treatment: .pearlStudy,
                    naturalVariation: first, assetAvailable: false),
                    CompanionVisualAsset.appearanceID(form: .companion, family: family, treatment: .original,
                        naturalVariation: first), "A missing asset uses the actual original drawing's identity")
            }
            let label = CompanionVisualAsset.label(form: .companion, family: family, treatment: .pearlStudy, naturalVariation: first)
            XCTAssertLessThanOrEqual(label.count, 80)
            XCTAssertTrue(label.contains("Individual"))
            XCTAssertTrue(label.contains(String(first.fingerprint.prefix(8))))
            XCTAssertFalse(label.contains("role"))
            XCTAssertFalse(label.contains("help style"))
        }
    }

    @MainActor
    private func assertTransparentFrame(_ png: Data, baseline: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png), file: file, line: line)
        let original = try XCTUnwrap(NSBitmapImageRep(data: baseline), file: file, line: line)
        XCTAssertEqual(bitmap.pixelsWide, 512, file: file, line: line)
        XCTAssertEqual(bitmap.pixelsHigh, 512, file: file, line: line)
        XCTAssertTrue(bitmap.hasAlpha, file: file, line: line)
        XCTAssertLessThan(png.count, CompanionVisualAsset.maximumBytes, file: file, line: line)
        var edgeAlpha: CGFloat = 0, originalEdgeAlpha: CGFloat = 0
        for offset in 0..<512 {
            for point in [(offset, 0), (offset, 511), (0, offset), (511, offset)] {
                edgeAlpha = max(edgeAlpha, try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1), file: file, line: line).alphaComponent)
                originalEdgeAlpha = max(originalEdgeAlpha, try XCTUnwrap(original.colorAt(x: point.0, y: point.1), file: file, line: line).alphaComponent)
            }
        }
        // The original body's blurred ground shadow reaches the frame at very
        // low opacity. Bound against that actual baseline, plus one byte of
        // raster rounding, instead of requiring the old art to be fully clear.
        XCTAssertLessThanOrEqual(edgeAlpha, originalEdgeAlpha + 1.0 / 255.0,
            "Natural details must not add opaque content at the original frame boundary", file: file, line: line)
    }
}
