import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ARCHiDesktop

@MainActor
final class ReactorFrameCompositorTests: XCTestCase {
    func testOwnedDetachedSatellitesSurviveProviderCanvasAndTransparentOutput() throws {
        let reference = try referencePNG()
        let candidate = try ReactorFrameCompositor.makeProviderReference(approvedReferencePNG: reference)
        let candidateSource = try XCTUnwrap(CGImageSourceCreateWithData(candidate as CFData, nil))
        let candidateImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(candidateSource, 0, nil))
        XCTAssertTrue([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(candidateImage.alphaInfo), "Provider input is RGB; owned alpha was composited onto green.")
        let result = try ReactorFrameCompositor.composite(candidatePNG: candidate, approvedReferencePNG: reference)
        XCTAssertEqual(result.diagnostics.referenceComponentCount, 4)
        XCTAssertEqual(result.diagnostics.outputWidth, 512)
        XCTAssertEqual(result.diagnostics.outputHeight, 512)
        XCTAssertEqual(result.diagnostics.outsideSupportPixels, 0)
        XCTAssertGreaterThan(result.diagnostics.referenceCoverage, 0.99)
        let pixels = try pixels(result.pngData)
        XCTAssertEqual(pixels[3], 0)
        XCTAssertGreaterThan(pixels[(256 * 512 + 256) * 4 + 3], 240)
        // Reference and output use the same centered square transform; no 640:384
        // aspect distortion or removal of separate owned satellite components.
        let referencePixels = try self.pixels(reference)
        let outputCount = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] >= 32 }.count
        let expectedCount = stride(from: 3, to: referencePixels.count, by: 4).filter { referencePixels[$0] >= 32 }.count
        XCTAssertEqual(Double(outputCount) / Double(expectedCount), 1, accuracy: 0.04)
    }

    func testSmallLocalBreathingAndTranslationPassAndChangeTheFrame() throws {
        let reference = try referencePNG()
        let first = try ReactorFrameCompositor.makeLocalPreviewFrame(approvedReferencePNG: reference, phase: 0)
        let second = try ReactorFrameCompositor.makeLocalPreviewFrame(approvedReferencePNG: reference, phase: .pi / 2)
        XCTAssertNotEqual(first, second)
        for phase in [0.0, .pi / 2, .pi, 3 * .pi / 2] {
            let candidate = try ReactorFrameCompositor.makeLocalPreviewFrame(approvedReferencePNG: reference, phase: phase)
            let result = try ReactorFrameCompositor.composite(candidatePNG: candidate, approvedReferencePNG: reference)
            XCTAssertGreaterThan(result.diagnostics.referenceCoverage, 0.97)
        }
    }

    func testUnexpectedSubjectOutsideOwnedSupportIsRejected() throws {
        let reference = try referencePNG()
        let candidate = try alteredCandidate(reference) { context in
            context.setFillColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 180, y: 150, width: 25, height: 25))
        }
        XCTAssertThrowsError(try ReactorFrameCompositor.composite(candidatePNG: candidate, approvedReferencePNG: reference)) {
            XCTAssertEqual($0 as? ReactorFrameError, .unexpectedSupport)
        }
    }

    func testMissingBodyWithOnlySatellitesIsRejected() throws {
        let reference = try referencePNG()
        let noBody = try referencePNG(body: false)
        let candidate = try ReactorFrameCompositor.makeProviderReference(approvedReferencePNG: noBody)
        XCTAssertThrowsError(try ReactorFrameCompositor.composite(candidatePNG: candidate, approvedReferencePNG: reference)) {
            XCTAssertEqual($0 as? ReactorFrameError, .missingBody)
        }
    }

    func testMissingOwnedSatelliteFailsEvenWhenMainBodyRemains() throws {
        let reference = try referencePNG()
        let candidate = try alteredCandidate(reference) { context in
            context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            context.fill(CGRect(x: 210, y: 175, width: 28, height: 34))
        }
        XCTAssertThrowsError(try ReactorFrameCompositor.composite(candidatePNG: candidate, approvedReferencePNG: reference)) {
            XCTAssertEqual($0 as? ReactorFrameError, .missingBody)
        }
    }

    func testVanishedFrameIsRejected() throws {
        let reference = try referencePNG()
        let candidate = try png(width: 640, height: 384) { context in
            context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 384))
        }
        XCTAssertThrowsError(try ReactorFrameCompositor.composite(candidatePNG: candidate, approvedReferencePNG: reference)) {
            XCTAssertEqual($0 as? ReactorFrameError, .missingBody)
        }
    }

    func testBodyTouchingCropBoundaryFailsInsteadOfBeingSilentlyCropped() throws {
        let reference = try referencePNG()
        let candidate = try alteredCandidate(reference) { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 160, y: 130, width: 4, height: 15))
        }
        XCTAssertThrowsError(try ReactorFrameCompositor.composite(candidatePNG: candidate, approvedReferencePNG: reference)) {
            XCTAssertEqual($0 as? ReactorFrameError, .clippedBody)
        }
    }

    func testNonGreenAndTransparentBackgroundsAreRejected() throws {
        let reference = try referencePNG()
        for alpha: CGFloat in [0, 1] {
            let candidate = try png(width: 640, height: 384) { context in
                context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.8, alpha: alpha))
                context.fill(CGRect(x: 0, y: 0, width: 640, height: 384))
            }
            XCTAssertThrowsError(try ReactorFrameCompositor.composite(candidatePNG: candidate, approvedReferencePNG: reference)) {
                XCTAssertEqual($0 as? ReactorFrameError, .unsupportedBackground)
            }
        }
    }

    func testByteFormatAndDimensionBoundsAreChecked() throws {
        let reference = try referencePNG()
        for (candidate, expected) in [
            (Data("not a png".utf8), ReactorFrameError.invalidPNG),
            (Data(repeating: 0, count: ReactorFrameCompositor.maximumPNGBytes + 1), .byteLimit),
            (try png(width: 641, height: 384) { _ in }, .invalidDimensions)
        ] {
            XCTAssertThrowsError(try ReactorFrameCompositor.composite(candidatePNG: candidate, approvedReferencePNG: reference)) {
                XCTAssertEqual($0 as? ReactorFrameError, expected)
            }
        }
    }

    func testOpaqueBlankAndBorderTouchingReferencesAreRejected() throws {
        let blank = try png(width: 512, height: 512) { _ in }
        let opaque = try png(width: 512, height: 512) { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        }
        let edge = try png(width: 512, height: 512) { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 100, width: 200, height: 200))
        }
        for reference in [blank, opaque, edge] {
            XCTAssertThrowsError(try ReactorFrameCompositor.makeProviderReference(approvedReferencePNG: reference)) {
                XCTAssertEqual($0 as? ReactorFrameError, .invalidReference)
            }
        }
        XCTAssertThrowsError(try ReactorFrameCompositor.makeLocalPreviewFrame(approvedReferencePNG: referencePNG(), phase: .nan))
    }

    func testRealOwnedPearlAndLumenReferencesAcceptTheirLocalRehearsal() throws {
        for family: EvolutionFamily? in [nil, .lumen] {
            let reference = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: family, treatment: .pearlStudy))
            let candidate = try ReactorFrameCompositor.makeLocalPreviewFrame(approvedReferencePNG: reference, phase: .pi / 2)
            let result = try ReactorFrameCompositor.composite(candidatePNG: candidate, approvedReferencePNG: reference)
            XCTAssertGreaterThan(result.diagnostics.foregroundPixels, 1_000)
            XCTAssertGreaterThan(result.diagnostics.referenceCoverage, 0.9)
        }
    }

    private func referencePNG(body: Bool = true) throws -> Data {
        try png(width: 512, height: 512) { context in
            context.setFillColor(CGColor(red: 0.78, green: 0.69, blue: 0.96, alpha: 1))
            if body { context.fillEllipse(in: CGRect(x: 160, y: 135, width: 190, height: 255)) }
            context.setFillColor(CGColor(red: 0.5, green: 0.85, blue: 1, alpha: 1))
            for rect in [CGRect(x: 88, y: 240, width: 25, height: 25), CGRect(x: 398, y: 240, width: 25, height: 25), CGRect(x: 245, y: 70, width: 25, height: 25)] {
                context.fillEllipse(in: rect)
            }
        }
    }

    private func alteredCandidate(_ reference: Data, draw: (CGContext) -> Void) throws -> Data {
        let baseline = try ReactorFrameCompositor.makeProviderReference(approvedReferencePNG: reference)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(baseline as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try png(width: 640, height: 384) { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: 640, height: 384))
            draw(context)
        }
    }

    private func png(width: Int, height: Int, draw: (CGContext) -> Void) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        draw(context)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixels(_ data: Data) throws -> [UInt8] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: space,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }
}
