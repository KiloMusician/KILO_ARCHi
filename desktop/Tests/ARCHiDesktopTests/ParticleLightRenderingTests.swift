import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class ParticleLightRenderingTests: XCTestCase {
    func testParticleMotionIsBoundedAndDoesNotAccumulateGeometry() {
        let source = ParticleLightGeometry.points
        XCTAssertEqual(source.count, 72)
        XCTAssertLessThanOrEqual(ParticleLightGeometry.edges.count, 216)
        XCTAssertFalse(ParticleLightGeometry.edges.isEmpty)
        for phase in [0.0, 1.4, 10_000_000.0] {
            let frame = ParticleLightGeometry.project(phase: phase)
            XCTAssertEqual(frame.count, source.count)
            for (point, original) in zip(frame, source) {
                let norm = point.x * point.x + point.y * point.y + point.z * point.z
                let oldNorm = original.x * original.x + original.y * original.y + original.z * original.z
                XCTAssertTrue(norm.isFinite)
                XCTAssertLessThanOrEqual(norm, 1)
                XCTAssertEqual(norm, oldNorm, accuracy: 1e-12)
            }
        }
        XCTAssertEqual(ParticleLightGeometry.points, source)
        XCTAssertNotEqual(ParticleLightGeometry.project(phase: 0), ParticleLightGeometry.project(phase: 1.4))
    }

    @MainActor
    func testStaticExportAndReducedMotionHaveTheSameTransparentBody() throws {
        let baseline = try XCTUnwrap(CompanionPresenceArt.png(form: .particle, family: nil))
        let reduced = try render(CompanionArt(form: .particle, size: 256, reduceMotion: true), scale: 2)
        let comparison = try NaturalPresentationComparison.compare(baseline, reduced)
        XCTAssertTrue(comparison.dimensionsEqual && comparison.alphaEqual)
        XCTAssertTrue(comparison.withinAlphaPresentationBound,
            "Reduce Motion must choose the same fixed frame as the shared export")
        XCTAssertNotEqual(baseline, CompanionPresenceArt.png(form: .light, family: nil))
        try inspectFrame(baseline, pixels: 512)
        let small = try render(CompanionArt(form: .particle, size: 64, reduceMotion: true), scale: 1)
        try inspectFrame(small, pixels: 64)
        if let output = ProcessInfo.processInfo.environment["ARCHI_PARTICLE_RENDER_DIR"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try baseline.write(to: directory.appendingPathComponent("particle-light.png"))
            try small.write(to: directory.appendingPathComponent("particle-light-64.png"))
            let sheet = HStack(spacing: 0) {
                sample.background(Color(red: 0.035, green: 0.07, blue: 0.065))
                sample.background(Color(red: 0.98, green: 0.97, blue: 0.95))
            }
            try render(sheet, scale: 2).write(to: directory.appendingPathComponent("particle-light-review.png"))
        }
    }

    @MainActor
    func testOnlyInternalParticlesChangeWithAnimationPhase() throws {
        let first = try render(ParticleLightFrame(phase: 0).frame(width: 256, height: 256), scale: 2)
        let later = try render(ParticleLightFrame(phase: 1.4).frame(width: 256, height: 256), scale: 2)
        XCTAssertNotEqual(first, later, "An enabled timeline must actually move the light points")
        let old = try XCTUnwrap(NSBitmapImageRep(data: first))
        let new = try XCTUnwrap(NSBitmapImageRep(data: later))
        for y in 0..<512 {
            for x in 0..<512 {
                let dx = Double(x) - 256, dy = Double(y) - 512 * 0.465
                if dx * dx + dy * dy > pow(512 * 0.32, 2) {
                    XCTAssertEqual(old.colorAt(x: x, y: y), new.colorAt(x: x, y: y),
                        "Motion must stay inside the existing stationary body and hit frame")
                }
            }
        }
    }

    @MainActor private var sample: some View {
        VStack(spacing: 8) {
            CompanionArt(form: .particle, size: 256, reduceMotion: true)
            HStack(spacing: 12) {
                CompanionArt(form: .particle, size: 64, reduceMotion: true)
                CompanionPresenceArt(form: .particle, family: nil, size: 112, reduceMotion: true,
                    equipment: CompanionEquipment(hand: .focusStaff))
            }
        }.padding(24)
    }

    @MainActor private func inspectFrame(_ data: Data, pixels: Int) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, pixels)
        XCTAssertEqual(bitmap.pixelsHigh, pixels)
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertLessThan(data.count, CompanionVisualAsset.maximumBytes)
        for i in 0..<pixels {
            for (x, y) in [(i, 0), (i, pixels - 1), (0, i), (pixels - 1, i)] {
                XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0)
            }
        }
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: pixels / 2, y: Int(Double(pixels) * 0.465))).alphaComponent, 0.9,
            "The central light must remain visible at floating-companion sizes")
    }

    @MainActor private func render<V: View>(_ view: V, scale: CGFloat) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let tiff = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }
}
