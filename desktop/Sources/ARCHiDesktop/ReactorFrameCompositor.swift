import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Geometric and chroma checks only. Passing a frame does not identify a character,
/// establish motion quality, or change the companion's state or placement.
struct ReactorFrameDiagnostics: Equatable, Sendable {
    let foregroundPixels: Int
    let referencePixels: Int
    let outsideSupportPixels: Int
    let referenceCoverage: Double
    let referenceComponentCount: Int
    let outputWidth: Int
    let outputHeight: Int
}

struct ReactorCompositedFrame: Sendable {
    let pngData: Data
    let diagnostics: ReactorFrameDiagnostics
}

enum ReactorFrameError: Error, Equatable, LocalizedError {
    case invalidPNG
    case byteLimit
    case invalidDimensions
    case invalidReference
    case unsupportedBackground
    case missingBody
    case clippedBody
    case unexpectedSupport
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidPNG: "Expression frame is not a single valid PNG. Using local artwork."
        case .byteLimit: "Expression frame exceeds the image byte limit. Using local artwork."
        case .invalidDimensions: "Expression frame has unsupported dimensions. Using local artwork."
        case .invalidReference: "The approved reference needs a bounded transparent silhouette. Using local artwork."
        case .unsupportedBackground: "Expression frame does not have the expected green background. Using local artwork."
        case .missingBody: "Expression frame lost too much of the approved silhouette. Using local artwork."
        case .clippedBody: "Expression frame touches its crop boundary. Using local artwork."
        case .unexpectedSupport: "Expression frame extends beyond the approved motion area. Using local artwork."
        case .encodingFailed: "Expression frame could not be rendered. Using local artwork."
        }
    }
}

/// A presentation-only adapter for the fixed RGB provider canvas. Expected support
/// comes from owned alpha, including detached satellites, never a generated mask.
/// All dimensions are checked before ImageIO decompresses the input.
enum ReactorFrameCompositor {
    static let providerWidth = 640
    static let providerHeight = 384
    static let outputSize = 512
    static let maximumPNGBytes = 4_000_000
    static let bodyRect = CGRect(x: 160, y: 32, width: 320, height: 320)
    private static let supportTolerance = 10
    private static var colorSpace: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }
    private static let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

    static func makeProviderReference(approvedReferencePNG: Data) throws -> Data {
        let reference = try approvedReference(approvedReferencePNG)
        return try renderProvider(reference.image, phase: nil)
    }

    /// A deterministic local presentation rehearsal, with no provider or inference.
    static func makeLocalPreviewFrame(approvedReferencePNG: Data, phase: Double) throws -> Data {
        guard phase.isFinite else { throw ReactorFrameError.invalidReference }
        let reference = try approvedReference(approvedReferencePNG)
        return try renderProvider(reference.image, phase: phase)
    }

    static func composite(candidatePNG: Data, approvedReferencePNG: Data) throws -> ReactorCompositedFrame {
        let reference = try approvedReference(approvedReferencePNG)
        let candidate = try decode(candidatePNG, width: providerWidth, height: providerHeight)
        var pixels = try rgba(candidate)
        let count = providerWidth * providerHeight
        let expected = reference.support
        let allowed = dilate(expected, radius: supportTolerance)
        var candidateSupport = [UInt8](repeating: 0, count: count)
        var foreground = 0
        var outside = 0
        for index in 0..<count {
            let p = index * 4
            let r = Double(pixels[p]), g = Double(pixels[p + 1]), b = Double(pixels[p + 2])
            // The SDK output must be opaque RGB. Arbitrary transparent input must
            // not evade background or occupancy verification.
            guard pixels[p + 3] >= 250 else { throw ReactorFrameError.unsupportedBackground }
            let x = index % providerWidth, y = index / providerWidth
            if x < 2 || x >= providerWidth - 2 || y < 2 || y >= providerHeight - 2 {
                guard r <= 60, b <= 60, g >= 190, g - max(r, b) >= 140 else {
                    throw ReactorFrameError.unsupportedBackground
                }
            }
            let excess = g - max(r, b)
            let alpha = min(1, max(0, (200 - excess) / 165))
            if alpha >= 0.125 {
                candidateSupport[index] = 1
                foreground += 1
                if x <= 162 || x >= 477 || y <= 34 || y >= 349 {
                    throw ReactorFrameError.clippedBody
                }
                if allowed[index] == 0 { outside += 1 }
            }
            // Remove green spill while retaining premultiplied RGBA. Small key
            // noise outside the owned tolerance is transparent in the result.
            let outputAlpha = allowed[index] == 1 ? alpha : 0
            pixels[p] = UInt8(min(255 * outputAlpha, max(0, r)))
            pixels[p + 1] = UInt8(min(255 * outputAlpha, max(0, g - 255 * (1 - alpha))))
            pixels[p + 2] = UInt8(min(255 * outputAlpha, max(0, b)))
            pixels[p + 3] = UInt8(outputAlpha * 255)
        }
        let referencePixels = expected.reduce(0) { $0 + Int($1) }
        guard foreground >= max(200, referencePixels * 55 / 100) else { throw ReactorFrameError.missingBody }
        guard outside <= max(6, foreground / 1_000), foreground <= referencePixels * 165 / 100 else {
            throw ReactorFrameError.unexpectedSupport
        }
        let nearCandidate = dilate(candidateSupport, radius: 8)
        let covered = expected.indices.reduce(0) { $0 + (expected[$1] == 1 && nearCandidate[$1] == 1 ? 1 : 0) }
        let coverage = Double(covered) / Double(referencePixels)
        guard coverage >= 0.82 else { throw ReactorFrameError.missingBody }
        // Verify each significant expected island independently. Multiple islands
        // are legitimate; a missing main body cannot be replaced by satellites.
        let components = connectedComponents(expected)
        for component in components where component.count >= 16 {
            let present = component.reduce(0) { $0 + Int(nearCandidate[$1]) }
            guard Double(present) / Double(component.count) >= 0.55 else { throw ReactorFrameError.missingBody }
        }
        let keyed = try image(pixels, width: providerWidth, height: providerHeight)
        guard let cropped = keyed.cropping(to: bodyRect), let context = context(width: outputSize, height: outputSize) else {
            throw ReactorFrameError.encodingFailed
        }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
        guard let output = context.makeImage() else { throw ReactorFrameError.encodingFailed }
        return ReactorCompositedFrame(pngData: try png(output), diagnostics: ReactorFrameDiagnostics(
            foregroundPixels: foreground, referencePixels: referencePixels,
            outsideSupportPixels: outside, referenceCoverage: coverage,
            referenceComponentCount: components.filter { $0.count >= 16 }.count,
            outputWidth: outputSize, outputHeight: outputSize))
    }

    private static func approvedReference(_ data: Data) throws -> (image: CGImage, support: [UInt8]) {
        let reference = try decode(data, width: outputSize, height: outputSize)
        let source = try rgba(reference)
        let opaque = stride(from: 3, to: source.count, by: 4).filter { source[$0] >= 16 }.count
        guard opaque > 512, opaque < outputSize * outputSize * 85 / 100 else { throw ReactorFrameError.invalidReference }
        for y in 0..<outputSize {
            for x in 0..<outputSize where x < 2 || x >= outputSize - 2 || y < 2 || y >= outputSize - 2 {
                guard source[(y * outputSize + x) * 4 + 3] < 16 else { throw ReactorFrameError.invalidReference }
            }
        }
        guard let fitted = context(width: providerWidth, height: providerHeight) else { throw ReactorFrameError.encodingFailed }
        fitted.interpolationQuality = .high
        fitted.draw(reference, in: bodyRect)
        guard let fittedImage = fitted.makeImage() else { throw ReactorFrameError.encodingFailed }
        let pixels = try rgba(fittedImage)
        let support = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] >= 16 ? UInt8(1) : 0 }
        return (reference, support)
    }

    private static func renderProvider(_ reference: CGImage, phase: Double?) throws -> Data {
        guard let target = context(width: providerWidth, height: providerHeight, opaque: true) else { throw ReactorFrameError.encodingFailed }
        target.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 1, 0, 1])!)
        target.fill(CGRect(x: 0, y: 0, width: providerWidth, height: providerHeight))
        let breath = phase.map { sin($0) } ?? 0
        let scale = 1 + 0.01 * breath
        let rect = CGRect(x: bodyRect.midX - bodyRect.width * scale / 2,
                          y: bodyRect.midY - bodyRect.height * scale / 2 + 3 * breath,
                          width: bodyRect.width * scale, height: bodyRect.height * scale)
        target.interpolationQuality = .high
        target.draw(reference, in: rect)
        guard let result = target.makeImage() else { throw ReactorFrameError.encodingFailed }
        return try png(result)
    }

    private static func decode(_ data: Data, width: Int, height: Int) throws -> CGImage {
        guard data.count <= maximumPNGBytes else { throw ReactorFrameError.byteLimit }
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw ReactorFrameError.invalidPNG
        }
        guard properties[kCGImagePropertyPixelWidth] as? Int == width,
              properties[kCGImagePropertyPixelHeight] as? Int == height,
              (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1 else { throw ReactorFrameError.invalidDimensions }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              image.width == width, image.height == height else { throw ReactorFrameError.invalidPNG }
        return image
    }

    private static func context(width: Int, height: Int, opaque: Bool = false) -> CGContext? {
        let info = opaque ? CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue : bitmapInfo
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                         space: colorSpace, bitmapInfo: info)
    }

    private static func rgba(_ image: CGImage) throws -> [UInt8] {
        guard let target = context(width: image.width, height: image.height), let bytes = target.data else { throw ReactorFrameError.encodingFailed }
        target.setBlendMode(.copy)
        target.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    private static func image(_ bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw ReactorFrameError.encodingFailed
        }
        return image
    }

    private static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw ReactorFrameError.encodingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ReactorFrameError.encodingFailed }
        return data as Data
    }

    private static func dilate(_ input: [UInt8], radius: Int) -> [UInt8] {
        let stride = providerWidth + 1
        var integral = [Int](repeating: 0, count: stride * (providerHeight + 1))
        for y in 0..<providerHeight {
            var row = 0
            for x in 0..<providerWidth {
                row += Int(input[y * providerWidth + x])
                integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + row
            }
        }
        var result = [UInt8](repeating: 0, count: input.count)
        for y in 0..<providerHeight {
            let top = max(0, y - radius), bottom = min(providerHeight, y + radius + 1)
            for x in 0..<providerWidth {
                let left = max(0, x - radius), right = min(providerWidth, x + radius + 1)
                let sum = integral[bottom * stride + right] - integral[top * stride + right]
                    - integral[bottom * stride + left] + integral[top * stride + left]
                result[y * providerWidth + x] = sum > 0 ? 1 : 0
            }
        }
        return result
    }

    private static func connectedComponents(_ mask: [UInt8]) -> [[Int]] {
        var visited = [Bool](repeating: false, count: mask.count)
        var components: [[Int]] = []
        for start in mask.indices where mask[start] == 1 && !visited[start] {
            var queue = [start], cursor = 0
            visited[start] = true
            while cursor < queue.count {
                let index = queue[cursor]; cursor += 1
                let x = index % providerWidth, y = index / providerWidth
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < providerWidth, ny >= 0, ny < providerHeight else { continue }
                    let next = ny * providerWidth + nx
                    if mask[next] == 1 && !visited[next] { visited[next] = true; queue.append(next) }
                }
            }
            components.append(queue)
        }
        return components
    }
}
