import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class CompanionCreatorEquipmentTests: XCTestCase {
    func testLegacyEquipmentJSONAndCanonicalIdentityRemainUnchanged() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        XCTAssertEqual(String(decoding: try encoder.encode(CompanionEquipment.empty), as: UTF8.self), "{}")
        let staff = CompanionEquipment(hand: .focusStaff)
        XCTAssertEqual(String(decoding: try encoder.encode(staff), as: UTF8.self), #"{"hand":"focus-staff/v1"}"#)
        XCTAssertEqual(staff.canonicalIdentity, "archi-companion-equipment/v1\nhand=focus-staff/v1\n")
        XCTAssertEqual(CompanionEquipment.empty.canonicalIdentity, "archi-companion-equipment/v1\nhand=none\n")
        XCTAssertTrue(staff.isValid && staff.supportsPointing)
        XCTAssertFalse(CompanionEquipment.empty.supportsPointing)
        XCTAssertNil(try JSONDecoder().decode(CompanionEquipment.self, from: Data(#"{"hand":"focus-staff/v1"}"#.utf8)).design)
    }

    func testCreatorDesignRoundTripsAndBindsNamePaletteAndBehaviorToIdentity() throws {
        let design = fixture()
        let staff = CompanionEquipment(hand: .focusStaff, design: design)
        XCTAssertTrue(staff.isValid && staff.supportsPointing)
        XCTAssertEqual(staff.canonicalIdentity, "archi-companion-equipment/v2\nhand=focus-staff/v1\ndesign=\(design.id)\n")
        XCTAssertEqual(try JSONDecoder().decode(CompanionEquipment.self, from: JSONEncoder().encode(staff)), staff)
        var renamed = design; renamed.title = "Another local staff"
        var recolored = design; recolored.palette = .ice
        var decorative = design; decorative.action = .decoration
        for changed in [renamed, recolored, decorative] {
            XCTAssertNotEqual(staff.canonicalIdentity, CompanionEquipment(hand: .focusStaff, design: changed).canonicalIdentity)
        }
        let descriptor = try XCTUnwrap(staff.item)
        XCTAssertEqual(descriptor.title, design.title)
        XCTAssertEqual(descriptor.creator, design.creator)
        XCTAssertTrue(descriptor.provenanceLabel.contains("claimed"))
        let registered = CompanionEquipment(hand: .focusStaff, design: CompanionItemCatalog.designs[0])
        XCTAssertEqual(registered.item?.provenanceLabel, ItemRegistrationDecision.registered.label)
        XCTAssertEqual(CompanionItemID.allCases, [.focusStaff], "Creator variants do not create executable item kinds")
    }

    func testDesignWithoutCompatibleHandAndUnknownEquipmentFieldsAreRejected() throws {
        let package = fixture()
        let malformed = CompanionEquipment(design: package)
        XCTAssertFalse(malformed.isValid)
        XCTAssertFalse(malformed.supportsPointing)
        XCTAssertNil(malformed.item)
        XCTAssertThrowsError(try JSONEncoder().encode(malformed))
        let packageJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(package))
        let malformedObjects: [[String: Any]] = [
            ["design": packageJSON],
            ["hand": NSNull(), "design": packageJSON],
            ["hand": "focus-staff/v1", "design": packageJSON, "script": "do-something"],
            ["hand": "different-tool/v1", "design": packageJSON],
        ]
        for fields in malformedObjects {
            XCTAssertThrowsError(try JSONDecoder().decode(CompanionEquipment.self,
                from: JSONSerialization.data(withJSONObject: fields)))
        }
        var invalid = package; invalid.title = ""
        XCTAssertFalse(CompanionEquipment(hand: .focusStaff, design: invalid).isValid)
    }

    @MainActor
    func testDecorativeDesignCannotActivatePointing() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-creator-equipment-\(UUID())")
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"))
        let decoration = CompanionEquipment(hand: .focusStaff, design: fixture(action: .decoration))
        store.preferences.equipment = decoration
        XCTAssertFalse(decoration.supportsPointing)
        XCTAssertFalse(store.activateEquippedItem())
        XCTAssertNil(store.focusGesturePlayback)
        XCTAssertNil(store.spatialPreview)
        XCTAssertTrue(store.compareResults.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor
    func testPalettesAndCrownsRenderDistinctLocalPixelsWithinTheExistingInterior() throws {
        let baseline = try rendered(CompanionEquipment(hand: .focusStaff))
        var renderDigests = Set<String>()
        for palette in CompanionItemPackage.Palette.allCases {
            for crown in CompanionItemPackage.Crown.allCases {
                let design = fixture(palette: palette, crown: crown)
                let bitmap = try rendered(CompanionEquipment(hand: .focusStaff, design: design))
                XCTAssertEqual(bitmap.width, 512)
                XCTAssertEqual(bitmap.height, 512)
                let digest = SHA256.hash(data: Data(bitmap.pixels)).map { String(format: "%02x", $0) }.joined()
                XCTAssertTrue(renderDigests.insert(digest).inserted, "\(palette), \(crown) must produce distinct pixels")
                var visible = 0, changedRGB = 0
                var staysInsideStaffRegion = true, edgeAlphaUnchanged = true
                for y in 0..<512 {
                    for x in 0..<512 {
                        let offset = (y * 512 + x) * 4
                        if bitmap.pixels[offset + 3] > 0 {
                            visible += 1
                            staysInsideStaffRegion = staysInsideStaffRegion && x >= 384 && x < 488 && y >= 96 && y < 422
                        }
                        if bitmap.pixels[offset] != baseline.pixels[offset]
                            || bitmap.pixels[offset + 1] != baseline.pixels[offset + 1]
                            || bitmap.pixels[offset + 2] != baseline.pixels[offset + 2] { changedRGB += 1 }
                        if x == 0 || y == 0 || x == 511 || y == 511 {
                            edgeAlphaUnchanged = edgeAlphaUnchanged && bitmap.pixels[offset + 3] == baseline.pixels[offset + 3]
                        }
                    }
                }
                XCTAssertTrue(staysInsideStaffRegion, "\(palette), \(crown) must stay inside the existing staff region")
                XCTAssertTrue(edgeAlphaUnchanged, "Creator shapes and colors must not expand frame-edge alpha")
                XCTAssertGreaterThan(visible, 200)
                if palette != .lilac || crown != .pearl { XCTAssertGreaterThan(changedRGB, 100) }
            }
        }
        XCTAssertEqual(renderDigests.count, CompanionItemPackage.Palette.allCases.count * CompanionItemPackage.Crown.allCases.count)
    }

    @MainActor
    func testExplicitOriginalPaletteAndCrownPreserveLegacyStaticDrawing() throws {
        let baseline = try rendered(CompanionEquipment(hand: .focusStaff))
        let explicit = try rendered(CompanionEquipment(hand: .focusStaff, design: fixture(palette: .lilac, crown: .pearl)))
        var changedPixels = 0, changedAlpha = 0, maximumDifference = 0
        var sameAlphaSupport = true, differencesStayInsideHead = true
        for y in 0..<512 {
            for x in 0..<512 {
                let offset = (y * 512 + x) * 4
                sameAlphaSupport = sameAlphaSupport && (baseline.pixels[offset + 3] == 0) == (explicit.pixels[offset + 3] == 0)
                var changed = false
                for channel in 0..<4 {
                    let delta = abs(Int(baseline.pixels[offset + channel]) - Int(explicit.pixels[offset + channel]))
                    maximumDifference = max(maximumDifference, delta)
                    if delta > 0 { changed = true }
                }
                if baseline.pixels[offset + 3] != explicit.pixels[offset + 3] { changedAlpha += 1 }
                if changed {
                    changedPixels += 1
                    differencesStayInsideHead = differencesStayInsideHead && x >= 400 && x < 475 && y >= 109 && y < 184
                }
            }
        }
        // The pre-existing cold-process control allows only these tiny head-local
        // native raster differences. Creator support does not widen that bound.
        XCTAssertTrue(sameAlphaSupport)
        XCTAssertTrue(differencesStayInsideHead)
        XCTAssertLessThanOrEqual(maximumDifference, 1)
        XCTAssertLessThanOrEqual(changedAlpha, 4)
        XCTAssertLessThanOrEqual(changedPixels, 41)
    }

    private func fixture(palette: CompanionItemPackage.Palette = .mint,
                         crown: CompanionItemPackage.Crown = .pearl,
                         action: CompanionItemPackage.Action = .pointSelection) -> CompanionItemPackage {
        CompanionItemPackage(title: "Local test staff", creator: "Synthetic Creator",
            summary: "A synthetic local equipment design.", palette: palette, crown: crown, action: action,
            defaultGesture: FocusGestureConfiguration(pace: .quick, sparkle: .none, hold: .brief))
    }

    private struct Bitmap { let width: Int; let height: Int; let pixels: [UInt8] }

    @MainActor
    private func rendered(_ equipment: CompanionEquipment) throws -> Bitmap {
        let renderer = ImageRenderer(content: CompanionEquipmentArt(equipment: equipment, size: 512,
            activated: false, reduceMotion: true))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let cgImage = try XCTUnwrap(bitmap.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Bitmap(width: width, height: height, pixels: pixels)
    }
}
