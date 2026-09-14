import AppKit
import XCTest
@testable import ARCHiDesktop

final class CompanionEquipmentRenderingTests: XCTestCase {
    private let staff = CompanionEquipment(hand: .focusStaff)

    @MainActor
    func testEquipmentCacheBindsFullBodyAndFallbackWhileEmptyPreservesExistingIdentity() throws {
        let natural = try XCTUnwrap(CompanionNaturalVariation.make(originDigest: String(repeating: "a", count: 64)))
        let other = try XCTUnwrap(CompanionNaturalVariation.make(originDigest: String(repeating: "b", count: 64)))
        let available = CompanionVisualAsset.appearanceID(form: .companion, family: nil, treatment: .pearlStudy,
            naturalVariation: natural, equipment: staff, assetAvailable: true)
        XCTAssertEqual(available.count, 67)
        XCTAssertTrue(available.hasPrefix("e1-"))
        XCTAssertLessThanOrEqual("\(available)-expression-\(UInt64.max)".count, 100)
        XCTAssertNotEqual(available, CompanionVisualAsset.appearanceID(form: .companion, family: nil,
            treatment: .pearlStudy, naturalVariation: natural, equipment: staff, assetAvailable: false))
        XCTAssertNotEqual(available, CompanionVisualAsset.appearanceID(form: .companion, family: nil,
            treatment: .pearlStudy, naturalVariation: other, equipment: staff, assetAvailable: true))
        for family in [nil] + EvolutionFamily.allCases.map(Optional.some) {
            for treatment in CompanionVisualTreatment.allCases {
                let base = CompanionVisualAsset.appearanceID(form: .companion, family: family,
                    treatment: treatment, naturalVariation: natural)
                XCTAssertEqual(base, CompanionVisualAsset.appearanceID(form: .companion, family: family,
                    treatment: treatment, naturalVariation: natural, equipment: .empty))
                XCTAssertEqual(CompanionVisualAsset.label(form: .companion, family: family,
                    treatment: treatment, naturalVariation: natural),
                    CompanionVisualAsset.label(form: .companion, family: family,
                        treatment: treatment, naturalVariation: natural, equipment: .empty))
                XCTAssertNotEqual(base, CompanionVisualAsset.appearanceID(form: .companion, family: family,
                    treatment: treatment, naturalVariation: natural, equipment: staff))
            }
        }
        for family in EvolutionFamily.allCases {
            for role in EvolutionRole.allCases {
                for style in EvolutionHelpStyle.allCases {
                    let recipe = try XCTUnwrap(CompanionAppearanceRecipe.make(originDigest: natural.originDigest,
                        family: family, role: role, helpStyle: style, basisKind: .usefulWork))
                    let label = CompanionVisualAsset.label(form: .companion, family: family,
                        treatment: .pearlStudy, recipe: recipe, equipment: staff)
                    XCTAssertTrue(label.contains("Focus Staff"))
                    XCTAssertTrue(label.contains(String(recipe.fingerprint.prefix(8))))
                    XCTAssertLessThanOrEqual(label.count, 80, "Equipment labels must fit the unchanged hosted contract")
                }
            }
        }
    }

    @MainActor
    func testStaticEquipmentAddsVisiblePixelsInsideTheExistingFrame() throws {
        let natural = try XCTUnwrap(CompanionNaturalVariation.make(originDigest: String(repeating: "c", count: 64)))
        let bodies: [(CompanionForm, EvolutionFamily?)] = CompanionForm.allCases.map { ($0, nil) }
            + EvolutionFamily.allCases.map { (.companion, Optional.some($0)) }
        for (form, family) in bodies {
            let base = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: family,
                treatment: .pearlStudy, naturalVariation: natural))
            let equipped = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: family,
                treatment: .pearlStudy, naturalVariation: natural, equipment: staff))
            let restored = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: family,
                treatment: .pearlStudy, naturalVariation: natural, equipment: .empty))
            XCTAssertNotEqual(base, equipped, "The staff must be visible for \(form), \(String(describing: family))")
            // Baseline renderer repeatability is covered by its existing suites.
            // This item check verifies the added drawing and original frame;
            // removal uses the exact unmodified body path and cache identity.
            XCTAssertNotEqual(equipped, restored, "Removing equipment must remove the visible staff")
            let baseline = try XCTUnwrap(NSBitmapImageRep(data: base))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: equipped))
            XCTAssertEqual(bitmap.pixelsWide, 512)
            XCTAssertEqual(bitmap.pixelsHigh, 512)
            XCTAssertTrue(bitmap.hasAlpha)
            XCTAssertLessThan(equipped.count, CompanionVisualAsset.maximumBytes)
            for offset in 0..<512 {
                for point in [(offset, 0), (offset, 511), (0, offset), (511, offset)] {
                    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1)).alphaComponent,
                        try XCTUnwrap(baseline.colorAt(x: point.0, y: point.1)).alphaComponent,
                        "The staff must leave the existing body shadow at every edge exactly unchanged")
                }
            }
            let changes = try XCTUnwrap(alphaChangeBounds(before: baseline, after: bitmap),
                "The staff must add visible silhouette detail")
            let interiorStaffRegion = CGRect(x: 384, y: 96, width: 104, height: 326)
            XCTAssertTrue(interiorStaffRegion.contains(changes),
                "Every staff alpha change must stay in its interior region, away from all frame edges: \(changes)")
            if let output = ProcessInfo.processInfo.environment["ARCHI_EQUIPMENT_RENDER_DIR"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let name = "\(form.rawValue)-\(family?.rawValue ?? "starter")".lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                try base.write(to: directory.appendingPathComponent("\(name)-without-staff.png"))
                try equipped.write(to: directory.appendingPathComponent("\(name)-focus-staff.png"))
                try restored.write(to: directory.appendingPathComponent("\(name)-removed-staff.png"))
            }
        }
    }

    func testEquipmentFrameCheckRejectsAnAddedEdgePixelEvenWithAnExistingBodyShadow() throws {
        func fixture(addedEdge: Bool) throws -> NSBitmapImageRep {
            var pixels = [UInt8](repeating: 0, count: 20 * 20 * 4)
            // A pre-existing faint body shadow is legitimate baseline content.
            pixels[(8 * 20) * 4 + 3] = 11
            if addedEdge { pixels[19 * 4 + 3] = 1 }
            let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let image = try XCTUnwrap(CGImage(width: 20, height: 20, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 20 * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            return NSBitmapImageRep(cgImage: image)
        }
        let baseline = try fixture(addedEdge: false)
        let safe = try fixture(addedEdge: false)
        var addedPixel = [255, 255, 255, 255]
        safe.setPixel(&addedPixel, atX: 16, y: 10)
        let interior = CGRect(x: 14, y: 5, width: 4, height: 10)
        XCTAssertTrue(interior.contains(try XCTUnwrap(alphaChangeBounds(before: baseline, after: safe))))
        let clipped = try fixture(addedEdge: true)
        clipped.setPixel(&addedPixel, atX: 16, y: 10)
        XCTAssertFalse(interior.contains(try XCTUnwrap(alphaChangeBounds(before: baseline, after: clipped))),
            "Even one newly occupied edge pixel must fail the same interior check used on the real artwork")
    }

    /// Compare decoded alpha samples, rather than PNG encoding or a guessed
    /// background opacity. Existing artwork can intentionally have a faint shadow.
    private func alphaChangeBounds(before: NSBitmapImageRep, after: NSBitmapImageRep) throws -> CGRect? {
        XCTAssertEqual(before.pixelsWide, after.pixelsWide)
        XCTAssertEqual(before.pixelsHigh, after.pixelsHigh)
        XCTAssertTrue(before.hasAlpha && after.hasAlpha)
        var oldPixel = [Int](repeating: 0, count: before.samplesPerPixel)
        var newPixel = [Int](repeating: 0, count: after.samplesPerPixel)
        let oldAlpha = before.bitmapFormat.contains(.alphaFirst) ? 0 : before.samplesPerPixel - 1
        let newAlpha = after.bitmapFormat.contains(.alphaFirst) ? 0 : after.samplesPerPixel - 1
        var minX = before.pixelsWide, minY = before.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<before.pixelsHigh {
            for x in 0..<before.pixelsWide {
                before.getPixel(&oldPixel, atX: x, y: y)
                after.getPixel(&newPixel, atX: x, y: y)
                if oldPixel[oldAlpha] != newPixel[newAlpha] {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @MainActor
    func testEquipmentReplacesTheReactorReferenceAndRejectsAnOldBodyReference() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-equipment-reference-\(UUID())")
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"))
        store.preferences.form = .companion
        store.evolution.observeJourneyOrigin(String(repeating: "d", count: 64))
        let natural = try XCTUnwrap(store.evolution.naturalVariation)
        let previousID = store.reactor.appearanceID
        let previousPNG = try XCTUnwrap(store.reactor.referencePNG)
        store.preferences.equipment = staff
        let equippedID = store.reactor.appearanceID
        XCTAssertNotEqual(equippedID, previousID)
        XCTAssertTrue(store.reactorReferenceMatchesCurrentAppearance)
        XCTAssertNotEqual(store.reactor.referencePNG, previousPNG)
        XCTAssertTrue(store.reactor.referenceLabel.contains("Focus Staff"))
        XCTAssertEqual(store.evolution.naturalVariation, natural)
        store.reactor.updateReference(id: previousID, label: "Earlier unequipped reference", png: previousPNG,
            motionAllowed: false, visible: false)
        XCTAssertFalse(store.reactorReferenceMatchesCurrentAppearance,
            "A still-present old frame/reference must not be presented as current equipment")
        store.refreshReactorReference()
        XCTAssertEqual(store.reactor.appearanceID, equippedID)
        XCTAssertTrue(store.reactorReferenceMatchesCurrentAppearance)
        store.preferences.equipment = .empty
        XCTAssertEqual(store.reactor.appearanceID, previousID)
        XCTAssertEqual(store.evolution.naturalVariation, natural)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "This check must not write user preferences")
    }
}
