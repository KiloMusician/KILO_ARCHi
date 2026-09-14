import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class KinLightRenderingTests: XCTestCase {
    @MainActor
    func testRestingAndExportKeepTheAuthoredCoreSeedUnchanged() throws {
        let url = try XCTUnwrap(CompanionVisualAsset.resourceURL(named: CompanionVisualAsset.kinSeedFilename))
        let source = try Data(contentsOf: url)
        XCTAssertEqual(SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined(), CompanionVisualAsset.kinSeedDigest)
        let exported = try XCTUnwrap(CompanionPresenceArt.png(form: .kinSeed, family: nil))
        let originalPath = try render(KinArt(form: .kinSeed, size: 256, reduceMotion: true))
        let explicitRest = try render(CompanionPresenceArt(form: .kinSeed, family: nil, size: 256,
            reduceMotion: true, lightExpression: .resting))
        for actual in [originalPath, explicitRest] {
            XCTAssertTrue(try NaturalPresentationComparison.compare(exported, actual).withinAlphaPresentationBound)
        }
        let after = try XCTUnwrap(CompanionPresenceArt.png(form: .kinSeed, family: nil))
        XCTAssertEqual(exported, after)
    }

    @MainActor
    func testLightActivationsKeepCentralCoreAndFrameWhileEffectsChange() throws {
        let resting = try render(CompanionPresenceArt(form: .kinSeed, family: nil, size: 256, reduceMotion: true))
        let original = try XCTUnwrap(NSBitmapImageRep(data: resting))
        let output = ProcessInfo.processInfo.environment["ARCHI_KIN_LIGHT_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for mode in KinLightMode.allCases where mode != .rest {
            let expression = KinLightExpression(mode: mode)
            let data = try render(CompanionPresenceArt(form: .kinSeed, family: nil, size: 256,
                reduceMotion: true, lightExpression: expression))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(bitmap.pixelsWide, 512)
            XCTAssertEqual(bitmap.pixelsHigh, 512)
            XCTAssertTrue(bitmap.hasAlpha)
            XCTAssertLessThan(data.count, CompanionVisualAsset.maximumBytes)
            XCTAssertNotEqual(data, resting, "An active expression must have a visible effect")
            try assertProtectedCore(bitmap, original: original, mode: mode)
            for i in 0..<512 {
                for (x, y) in [(i, 0), (i, 511), (0, i), (511, i)] {
                    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0)
                }
            }
            let repeated = try render(CompanionPresenceArt(form: .kinSeed, family: nil, size: 256,
                reduceMotion: true, lightExpression: expression))
            let comparison = try NaturalPresentationComparison.compare(data, repeated)
            XCTAssertTrue(comparison.withinAlphaPresentationBound,
                "Repeated static \(mode.rawValue): \(comparison.receipt)")
            if let output {
                try data.write(to: output.appendingPathComponent("kin-\(mode.rawValue).png"))
                try repeated.write(to: output.appendingPathComponent("kin-\(mode.rawValue)-repeat.png"))
                try JSONSerialization.data(withJSONObject: comparison.receipt, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("kin-\(mode.rawValue)-repeat.json"))
                if [.orbit, .focus, .delight].contains(mode) {
                    for size in [64.0, 96, 192] {
                        for (name, background) in [("dark", Color(red: 0.07, green: 0.08, blue: 0.09)),
                                                    ("light", Color(red: 0.96, green: 0.95, blue: 0.93))] {
                            let proof = try render(CompanionPresenceArt(form: .kinSeed, family: nil, size: size,
                                reduceMotion: true, lightExpression: expression).background(background))
                            try proof.write(to: output.appendingPathComponent("kin-\(mode.rawValue)-\(Int(size))pt-\(name).png"))
                        }
                    }
                }
            }
        }
        if let output { try resting.write(to: output.appendingPathComponent("kin-rest.png")) }
        let finalExport = try XCTUnwrap(CompanionPresenceArt.png(form: .kinSeed, family: nil))
        XCTAssertTrue(try NaturalPresentationComparison.compare(resting, finalExport).withinAlphaPresentationBound,
            "The hosted appearance export remains the resting Core Seed")
    }

    @MainActor
    func testActivationDoesNotChangeOtherStarterBodies() throws {
        for form in [CompanionForm.companion, .particle, .lightForm] {
            let base = try render(CompanionPresenceArt(form: form, family: nil, size: 256, reduceMotion: true))
            let withExpression = try render(CompanionPresenceArt(form: form, family: nil, size: 256,
                reduceMotion: true, lightExpression: .init(mode: .focus)))
            let comparison = try NaturalPresentationComparison.compare(base, withExpression)
            XCTAssertTrue(comparison.withinAlphaPresentationBound, "\(form.rawValue): \(comparison.receipt)")
            if !comparison.withinAlphaPresentationBound,
               let path = ProcessInfo.processInfo.environment["ARCHI_KIN_LIGHT_RENDER_DIR"] {
                let directory = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try base.write(to: directory.appendingPathComponent("other-\(form.rawValue)-base.png"))
                try withExpression.write(to: directory.appendingPathComponent("other-\(form.rawValue)-expression.png"))
                let repeatedBase = try render(CompanionPresenceArt(form: form, family: nil, size: 256, reduceMotion: true))
                let control = try NaturalPresentationComparison.compare(base, repeatedBase)
                try JSONSerialization.data(withJSONObject: ["activation": comparison.receipt,
                    "unchangedBaseControl": control.receipt], options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("other-\(form.rawValue)-comparison.json"))
            }
        }
    }

    func testExpressionClockRespectsBothReduceMotionInputsAndRejectsInvalidTime() {
        for time in [0.0, 100, 1e12, .nan, .infinity, -.infinity] {
            XCTAssertEqual(KinLightEffectsGeometry.phase(at: time, reduceMotion: true, systemReduceMotion: false), 0)
            XCTAssertEqual(KinLightEffectsGeometry.phase(at: time, reduceMotion: false, systemReduceMotion: true), 0)
        }
        XCTAssertEqual(KinLightEffectsGeometry.phase(at: .nan, reduceMotion: false, systemReduceMotion: false), 0)
        XCTAssertEqual(KinLightEffectsGeometry.phase(at: .infinity, reduceMotion: false, systemReduceMotion: false), 0)
        let running = KinLightEffectsGeometry.phase(at: 100, reduceMotion: false, systemReduceMotion: false)
        XCTAssertTrue(running.isFinite)
        XCTAssertNotEqual(running, 0)
    }

    func testKinOrbitMotesRemainOnTheirProjectedPathsOutsideTheProtectedCore() {
        for nested in [false, true] {
            let tracks = KinOrbitGeometry.tracks(nested: nested)
            for phase in [0.0, 0.7, .pi, 2 * .pi, -1.2, 1e12] {
                let motes = KinOrbitGeometry.motes(phase: phase, nested: nested)
                XCTAssertEqual(motes.count, nested ? 9 : 5)
                for mote in motes {
                    let track = tracks[mote.trackIndex]
                    // Undo the projection's in-plane rotation and verify the
                    // ellipse equation, independently of Track.point(at:).
                    let x = mote.position.x * cos(track.rotation) + mote.position.y * sin(track.rotation)
                    let y = -mote.position.x * sin(track.rotation) + mote.position.y * cos(track.rotation)
                    XCTAssertEqual(pow(x / track.radiusX, 2) + pow(y / track.radiusY, 2), 1, accuracy: 1e-12)
                    let radius = hypot(mote.position.x, mote.position.y)
                    XCTAssertGreaterThan(radius - mote.radius * 4, KinLightEffectsGeometry.protectedCoreRadius)
                    XCTAssertLessThan(radius + mote.radius * 4, 0.445, "The entire glow stays within the portrait")
                    XCTAssertTrue((0.30...0.85).contains(mote.opacity))
                    XCTAssertTrue((0.0018...0.0034).contains(mote.radius))
                    XCTAssertEqual(mote.depth, sin(mote.angle), accuracy: 1e-12)
                }
                for pair in zip(motes, motes.dropFirst()) {
                    XCTAssertLessThanOrEqual(pair.0.depth, pair.1.depth)
                    XCTAssertLessThanOrEqual(pair.0.opacity, pair.1.opacity)
                    XCTAssertLessThanOrEqual(pair.0.radius, pair.1.radius)
                }
            }
        }
    }

    func testKinOrbitPathsKeepFourOpenGapsAndFiniteStableGeometry() {
        for nested in [false, true] {
            let tracks = KinOrbitGeometry.tracks(nested: nested)
            let arcs = KinOrbitGeometry.arcs(nested: nested)
            XCTAssertEqual(arcs.count, nested ? 8 : 4)
            for trackIndex in tracks.indices {
                let trackArcs = arcs.filter { $0.trackIndex == trackIndex }.sorted { $0.startAngle < $1.startAngle }
                XCTAssertEqual(trackArcs.count, 4)
                for (index, arc) in trackArcs.enumerated() {
                    XCTAssertEqual(arc.points.count, 21)
                    XCTAssertNotEqual(arc.points.first, arc.points.last, "Each light path remains interrupted")
                    let nextStart = index == 3 ? trackArcs[0].startAngle + .pi * 2 : trackArcs[index + 1].startAngle
                    XCTAssertEqual(nextStart - arc.endAngle, 0.24, accuracy: 1e-12)
                    for point in arc.points {
                        XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                        XCTAssertGreaterThan(hypot(point.x, point.y), KinLightEffectsGeometry.protectedCoreRadius)
                        XCTAssertLessThan(hypot(point.x, point.y), 0.4)
                    }
                }
            }
        }
    }

    func testKinOrbitTravelIsContinuousAtWrappedPhaseAndRejectsInvalidPhase() {
        func keyed(_ phase: Double) -> [String: KinOrbitGeometry.Mote] {
            Dictionary(uniqueKeysWithValues: KinOrbitGeometry.motes(phase: phase, nested: true)
                .map { ("\($0.trackIndex)-\($0.index)", $0) })
        }
        let initial = keyed(0)
        for phase in [Double.nan, .infinity, -.infinity, .pi * 2] {
            let actual = keyed(phase)
            for (key, expected) in initial {
                XCTAssertEqual(actual[key]?.position, expected.position)
                XCTAssertEqual(actual[key]?.opacity, expected.opacity)
            }
        }
        let epsilon = 1e-7
        let before = keyed(.pi * 2 - epsilon), after = keyed(epsilon)
        let moved = keyed(0.8)
        for (key, first) in before {
            let last = after[key]!
            XCTAssertLessThan(hypot(last.position.x - first.position.x, last.position.y - first.position.y), epsilon)
            XCTAssertLessThan(abs(last.opacity - first.opacity), epsilon)
            XCTAssertNotEqual(initial[key]?.position, moved[key]?.position)
        }
    }

    @MainActor
    func testKinOrbitMotionChangesTheEffectFrameAndReducedMotionFreezesIt() throws {
        let expression = KinLightExpression(mode: .orbit)
        // The native acceptance surface is the composited character, including
        // its preserved body and protected-core mask.
        func frame(_ phase: Double) throws -> Data {
            try render(KinArt(form: .kinSeed, size: 256, reduceMotion: true).overlay {
                KinLightEffectsFrame(expression: expression, phase: phase)
            })
        }
        let first = try frame(0)
        let moved = try frame(0.8)
        XCTAssertNotEqual(first, moved, "Traveling motes must produce visible native motion")
        var previousFrozen: Data?
        for time in [100.0, 200] {
            let phase = KinLightEffectsGeometry.phase(at: time, reduceMotion: true, systemReduceMotion: false)
            XCTAssertEqual(phase, 0)
            let frozen = try frame(phase)
            if let previousFrozen {
                let comparison = try NaturalPresentationComparison.compare(previousFrozen, frozen)
                XCTAssertTrue(comparison.withinAlphaPresentationBound, "Static orbital frame: \(comparison.receipt)")
            }
            previousFrozen = frozen
        }
        if let directory = ProcessInfo.processInfo.environment["ARCHI_KIN_LIGHT_RENDER_DIR"] {
            let output = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try first.write(to: output.appendingPathComponent("kin-orbit-phase-0.png"))
            try moved.write(to: output.appendingPathComponent("kin-orbit-phase-08.png"))
        }
    }

    @MainActor private func assertProtectedCore(_ bitmap: NSBitmapImageRep, original: NSBitmapImageRep,
                                                mode: KinLightMode) throws {
        var samples = 0, changedAlpha = 0, opaqueSamples = 0
        var maximumDifference = 0.0, totalDifference = 0.0, opaqueMaximumDifference = 0.0
        for y in 0..<512 {
            for x in 0..<512 {
                let dx = Double(x) / 512 - 0.5, dy = Double(y) / 512 - 0.5
                guard dx * dx + dy * dy < 0.16 * 0.16 else { continue }
                let a = try XCTUnwrap(original.colorAt(x: x, y: y))
                let b = try XCTUnwrap(bitmap.colorAt(x: x, y: y))
                samples += 1
                if a.alphaComponent != b.alphaComponent { changedAlpha += 1 }
                let aChannels = [a.redComponent, a.greenComponent, a.blueComponent]
                let bChannels = [b.redComponent, b.greenComponent, b.blueComponent]
                for channel in 0..<3 {
                    // A transparent compositing pass quantizes premultiplied
                    // channels. Raw RGB can vary widely when alpha is 2/255;
                    // compare its visible contribution in 8-bit units instead.
                    let difference = abs(Double(aChannels[channel] * a.alphaComponent
                        - bChannels[channel] * b.alphaComponent)) * 255
                    maximumDifference = max(maximumDifference, difference)
                    totalDifference += difference
                    if a.alphaComponent == 1 {
                        opaqueMaximumDifference = max(opaqueMaximumDifference,
                            abs(Double(aChannels[channel] - bChannels[channel])) * 255)
                    }
                }
                if a.alphaComponent == 1 { opaqueSamples += 1 }
            }
        }
        XCTAssertGreaterThan(samples, 20_000)
        XCTAssertGreaterThan(opaqueSamples, 3_000, "The authored opaque core must remain present")
        XCTAssertEqual(changedAlpha, 0, "The protected core's full alpha channel must stay exact for \(mode)")
        XCTAssertLessThanOrEqual(maximumDifference, 1.000001,
            "The protected core permits at most one premultiplied quantization step")
        XCTAssertLessThanOrEqual(totalDifference / Double(samples * 3), 0.25,
            "Mean protected-core error must remain below one quarter of an 8-bit step")
        XCTAssertEqual(opaqueMaximumDifference, 0,
            "The fully opaque central pearl must keep its exact original RGB")
    }

    @MainActor private func render<V: View>(_ view: V) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let tiff = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }
}
