import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class CompanionAppearanceRenderingTests: XCTestCase {
    private func recipe(_ origin: String = "a", family: EvolutionFamily = .lumen,
                        role: EvolutionRole = .muse, style: EvolutionHelpStyle = .exploratory) throws -> CompanionAppearanceRecipe {
        try XCTUnwrap(CompanionAppearanceRecipe.make(originDigest: String(repeating: origin, count: 64),
            family: family, role: role, helpStyle: style, basisKind: .usefulWork))
    }

    @MainActor
    func testSavedRecipeProducesStablePixelsAndAnotherOriginProducesDifferentPixels() throws {
        for family in EvolutionFamily.allCases {
            let firstRecipe = try recipe(family: family)
            let restoredRecipe = try JSONDecoder().decode(CompanionAppearanceRecipe.self,
                from: JSONEncoder().encode(firstRecipe))
            let first = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: family, recipe: firstRecipe))
            let restored = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: family, recipe: restoredRecipe))
            let different = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: family,
                recipe: recipe("b", family: family)))
            XCTAssertEqual(first, restored, "Restoring the recipe must restore the same static art for \(family)")
            XCTAssertNotEqual(first, different, "Different synthetic origins must produce visible differences for \(family)")
            let defaultArt = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: family))
            XCTAssertNotEqual(first, defaultArt)
            try assertTransparentFrame(first)
            try assertTransparentFrame(different)
        }
    }

    @MainActor
    func testReviewedLumenKeepsItsAssetAndReceivesDeterministicIndividualDetails() throws {
        XCTAssertNotNil(CompanionVisualAsset.lumenImage)
        let saved = try recipe()
        let baseline = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: .lumen, treatment: .pearlStudy))
        let first = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: .lumen, treatment: .pearlStudy, recipe: saved))
        let again = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: .lumen, treatment: .pearlStudy, recipe: saved))
        let different = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: .lumen, treatment: .pearlStudy,
            recipe: recipe("b")))
        XCTAssertNotEqual(first, baseline)
        XCTAssertEqual(first, again)
        XCTAssertNotEqual(first, different)
        try assertTransparentFrame(first)
        try assertTransparentFrame(different)
    }

    @MainActor
    func testRecipeCannotChangeAnyStarterOrAnUnrelatedFamily() throws {
        let saved = try recipe()
        for form in CompanionForm.allCases {
            for treatment in CompanionVisualTreatment.allCases {
                XCTAssertEqual(CompanionPresenceArt.png(form: form, family: nil, treatment: treatment),
                    CompanionPresenceArt.png(form: form, family: nil, treatment: treatment, recipe: saved))
                XCTAssertEqual(CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: treatment),
                    CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: treatment, recipe: saved))
                XCTAssertEqual(CompanionVisualAsset.label(form: form, family: nil, treatment: treatment),
                    CompanionVisualAsset.label(form: form, family: nil, treatment: treatment, recipe: saved))
            }
        }
        XCTAssertEqual(CompanionPresenceArt.png(form: .companion, family: .fen),
            CompanionPresenceArt.png(form: .companion, family: .fen, recipe: saved))
        XCTAssertEqual(CompanionVisualAsset.appearanceID(form: .companion, family: .fen, treatment: .original),
            CompanionVisualAsset.appearanceID(form: .companion, family: .fen, treatment: .original, recipe: saved))
        XCTAssertEqual(CompanionVisualAsset.label(form: .companion, family: .fen, treatment: .original),
            CompanionVisualAsset.label(form: .companion, family: .fen, treatment: .original, recipe: saved))
    }

    @MainActor
    func testCacheIdentityAndLabelsDescribeCapturedChoicesIncludingFallback() throws {
        let saved = try recipe(role: .keeper, style: .reflective)
        let changed = try recipe(role: .guardian, style: .concise)
        for available in [true, false] {
            let id = CompanionVisualAsset.appearanceID(form: .companion, family: .lumen, treatment: .pearlStudy,
                recipe: saved, assetAvailable: available)
            XCTAssertEqual(id.count, 67, "The full-digest ID must fit the existing native-to-Habitat contract")
            XCTAssertTrue(id.hasPrefix("i1-"))
            XCTAssertLessThanOrEqual("\(id)-expression-\(UInt64.max)".count, 100)
            XCTAssertNotEqual(id, CompanionVisualAsset.appearanceID(form: .companion, family: .lumen, treatment: .pearlStudy,
                recipe: changed, assetAvailable: available))
        }
        XCTAssertNotEqual(
            CompanionVisualAsset.appearanceID(form: .companion, family: .lumen, treatment: .pearlStudy,
                recipe: saved, assetAvailable: true),
            CompanionVisualAsset.appearanceID(form: .companion, family: .lumen, treatment: .pearlStudy,
                recipe: saved, assetAvailable: false),
            "A missing reviewed asset must invalidate the reference even for the same saved recipe")
        let label = CompanionVisualAsset.label(form: .companion, family: .lumen, treatment: .pearlStudy, recipe: saved)
        XCTAssertTrue(label.contains(String(saved.fingerprint.prefix(8))))
        XCTAssertTrue(label.contains("Keeper"))
        XCTAssertTrue(label.contains("Reflective"))
        XCTAssertFalse(label.contains("Guardian"))
    }

    @MainActor
    func testAllChosenRecipeLabelsAndIDsFitTheExistingHabitatContract() throws {
        var identifiers = Set<String>()
        for family in EvolutionFamily.allCases {
            for role in EvolutionRole.allCases {
                for style in EvolutionHelpStyle.allCases {
                    let saved = try recipe(family: family, role: role, style: style)
                    let id = CompanionVisualAsset.appearanceID(form: .companion, family: family,
                        treatment: .pearlStudy, recipe: saved)
                    XCTAssertTrue(identifiers.insert(id).inserted, "Each captured recipe must bind a distinct cache identity")
                    XCTAssertEqual(id.count, 67)
                    XCTAssertLessThanOrEqual("\(id)-expression-\(UInt64.max)".count, 100)
                    for treatment in CompanionVisualTreatment.allCases {
                        let label = CompanionVisualAsset.label(form: .companion, family: family,
                            treatment: treatment, recipe: saved)
                        XCTAssertLessThanOrEqual(label.count, 80, "Full saved-choice labels must fit without truncating meaningful details")
                    }
                }
            }
        }
    }

    @MainActor
    private func assertTransparentFrame(_ png: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png), file: file, line: line)
        XCTAssertEqual(bitmap.pixelsWide, 512, file: file, line: line)
        XCTAssertEqual(bitmap.pixelsHigh, 512, file: file, line: line)
        XCTAssertTrue(bitmap.hasAlpha, file: file, line: line)
        XCTAssertLessThan(png.count, CompanionVisualAsset.maximumBytes, file: file, line: line)
        for offset in 0..<512 {
            for point in [(offset, 0), (offset, 511), (0, offset), (511, offset)] {
                XCTAssertLessThanOrEqual(try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1), file: file, line: line).alphaComponent,
                    1.0 / 255.0, "Individual art must retain a transparent border within the unchanged frame", file: file, line: line)
            }
        }
    }
}
