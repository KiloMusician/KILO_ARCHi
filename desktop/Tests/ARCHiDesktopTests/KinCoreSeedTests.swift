import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class KinCoreSeedTests: XCTestCase {
    func testParticleFieldIsBoundedPeriodicAndFrozenForReducedMotion() {
        let original = KinCoreSeedGeometry.points
        XCTAssertEqual(original.count, 288)
        let still = KinCoreSeedGeometry.project(phase: 0)
        XCTAssertNotEqual(still, KinCoreSeedGeometry.project(phase: 1.2))
        XCTAssertEqual(still, KinCoreSeedGeometry.project(phase: .infinity))
        XCTAssertEqual(still, KinCoreSeedGeometry.project(phase: .nan))
        for phase in [0.0, 1.2, 1_000_000, .pi * 2] {
            let projected = KinCoreSeedGeometry.project(phase: phase)
            for (point, source) in zip(projected, original) {
                let norm = point.x * point.x + point.y * point.y + point.z * point.z
                let oldNorm = source.x * source.x + source.y * source.y + source.z * source.z
                XCTAssertEqual(norm, oldNorm, accuracy: 1e-12)
                XCTAssertLessThanOrEqual(norm, 1)
            }
            for ring in 0..<4 {
                let thread = KinCoreSeedGeometry.thread(ring: ring, phase: phase)
                XCTAssertEqual(thread.count, 121)
                XCTAssertTrue(thread.allSatisfy { $0.x * $0.x + $0.y * $0.y + $0.z * $0.z <= 1 })
            }
        }
        let loop = KinCoreSeedGeometry.project(phase: .pi * 2)
        for (a, b) in zip(still, loop) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-12)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-12)
        }
        XCTAssertEqual(KinCoreSeedGeometry.phase(at: 100, reduceMotion: true), 0)
        XCTAssertEqual(KinCoreSeedGeometry.phase(at: 100, reduceMotion: false, systemReduceMotion: true), 0)
        XCTAssertEqual(KinCoreSeedGeometry.phase(at: .infinity, reduceMotion: false), 0)
        XCTAssertNotEqual(KinCoreSeedGeometry.phase(at: 100, reduceMotion: false), 0)
        XCTAssertEqual(KinCoreSeedGeometry.points, original)
    }

    @MainActor
    func testSeedIsDistinctAndOldKinFormNamesRemainCompatible() throws {
        for form in [CompanionForm.kinSeed, .kinSpark, .kinSimple, .kin] {
            XCTAssertTrue(form.isKin)
            XCTAssertEqual(try JSONDecoder().decode(CompanionForm.self,
                from: JSONEncoder().encode(form)), form)
        }
        XCTAssertEqual(CompanionForm.kinSpark.rawValue, "KIN · Spark")
        XCTAssertEqual(CompanionForm.kinSimple.rawValue, "Simple KIN")
        XCTAssertEqual(CompanionForm.kin.rawValue, "KIN · First Light")
        let id = CompanionVisualAsset.appearanceID(form: .kinSeed, family: nil, treatment: .original)
        XCTAssertEqual(id, "k2-\(CompanionVisualAsset.kinSeedDigest)")
        XCTAssertNotNil(CompanionVisualAsset.kinSeedImage)
        XCTAssertNotEqual(id, CompanionVisualAsset.appearanceID(form: .kinSeed, family: nil,
            treatment: .original, assetAvailable: false))
        XCTAssertEqual(id, CompanionVisualAsset.appearanceID(form: .kinSeed, family: nil, treatment: .pearlStudy))
        XCTAssertNotEqual(id, CompanionVisualAsset.appearanceID(form: .kinSpark, family: nil, treatment: .original))
        XCTAssertNotEqual(id, CompanionVisualAsset.appearanceID(form: .kinSeed, family: nil,
            treatment: .original, equipment: CompanionEquipment(hand: .focusStaff)))
        XCTAssertNil(CompanionVisualAsset.resolvedImage(form: .kinSeed, family: nil, treatment: .original))
    }

    @MainActor
    func testSeedExportIsTransparentOpenAndMatchesReducedMotion() throws {
        let exported = try XCTUnwrap(CompanionPresenceArt.png(form: .kinSeed, family: nil))
        let reduced = try render(KinArt(form: .kinSeed, size: 256, reduceMotion: true), scale: 2)
        let comparison = try NaturalPresentationComparison.compare(exported, reduced)
        XCTAssertTrue(comparison.dimensionsEqual && comparison.alphaEqual)
        XCTAssertTrue(comparison.withinAlphaPresentationBound)
        try inspect(exported, pixels: 512)
        let small = try render(KinArt(form: .kinSeed, size: 64, reduceMotion: true), scale: 1)
        try inspect(small, pixels: 64)
        XCTAssertNotEqual(exported, CompanionPresenceArt.png(form: .kinSpark, family: nil))
        XCTAssertNotEqual(exported, CompanionPresenceArt.png(form: .particle, family: nil))
        if let output = ProcessInfo.processInfo.environment["ARCHI_KIN_SEED_RENDER_DIR"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try exported.write(to: directory.appendingPathComponent("kin-core-seed.png"))
            try small.write(to: directory.appendingPathComponent("kin-core-seed-64.png"))
            let sheet = HStack(spacing: 0) {
                sample.background(Color(red: 0.045, green: 0.03, blue: 0.025))
                sample.background(Color(red: 0.98, green: 0.97, blue: 0.95))
            }
            try render(sheet, scale: 2).write(to: directory.appendingPathComponent("kin-core-seed-review.png"))
        }
    }

    @MainActor
    func testMotionChangesParticlesWhileIvoryCoreStaysFixed() throws {
        let a = try render(KinCoreSeedFrame(phase: 0).frame(width: 256, height: 256), scale: 2)
        let b = try render(KinCoreSeedFrame(phase: 1.2).frame(width: 256, height: 256), scale: 2)
        XCTAssertNotEqual(a, b)
        let first = try XCTUnwrap(NSBitmapImageRep(data: a)), later = try XCTUnwrap(NSBitmapImageRep(data: b))
        for y in 230..<245 {
            for x in 250..<262 {
                XCTAssertEqual(first.colorAt(x: x, y: y), later.colorAt(x: x, y: y))
            }
        }
        if let output = ProcessInfo.processInfo.environment["ARCHI_KIN_SEED_RENDER_DIR"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try b.write(to: directory.appendingPathComponent("kin-core-seed-phase-1.png"))
        }
    }

    @MainActor private var sample: some View {
        VStack(spacing: 8) {
            KinArt(form: .kinSeed, size: 256, reduceMotion: true)
            HStack(spacing: 16) {
                KinArt(form: .kinSeed, size: 64, reduceMotion: true)
                KinArt(form: .kinSeed, size: 112, reduceMotion: true)
            }
        }.padding(24)
    }

    @MainActor private func inspect(_ data: Data, pixels: Int) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, pixels); XCTAssertEqual(bitmap.pixelsHigh, pixels)
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertLessThan(data.count, CompanionVisualAsset.maximumBytes)
        for i in 0..<pixels {
            for (x, y) in [(i, 0), (i, pixels - 1), (0, i), (pixels - 1, i)] {
                XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0)
            }
        }
        let core = try XCTUnwrap(bitmap.colorAt(x: pixels / 2, y: Int(Double(pixels) * 0.465)))
        XCTAssertGreaterThan(core.alphaComponent, 0.95)
        XCTAssertGreaterThan(core.redComponent, 0.9)
        XCTAssertGreaterThan(core.greenComponent, 0.8)
        var clear = 0, samples = 0
        for y in 0..<pixels {
            for x in 0..<pixels {
                let dx = Double(x) / Double(pixels) - 0.5, dy = Double(y) / Double(pixels) - 0.465
                let distance = sqrt(dx * dx + dy * dy)
                if distance > 0.16 && distance < 0.32 {
                    samples += 1
                    if try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent < 0.05 { clear += 1 }
                }
            }
        }
        XCTAssertGreaterThan(Double(clear) / Double(samples), 0.5, "Most of the particle field must remain open, without an opaque orb shell")
    }

    @MainActor private func render<V: View>(_ view: V, scale: CGFloat) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let tiff = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }
}
