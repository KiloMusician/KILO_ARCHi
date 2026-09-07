import AppKit
import ImageIO
import CryptoKit

enum CompanionVisualTreatment: String, CaseIterable, Identifiable, Codable {
    case original = "Original"
    case pearlStudy = "Pearl study"
    var id: String { rawValue }
}

/// Reviewed bundled studies, rendered through the same native image path.
/// This is not an arbitrary-file importer or another appearance store.
@MainActor
enum CompanionVisualAsset {
    static let revision = "pearl-study-v1-12c4b760"
    static let digest = "698cac349f8d2c2eb184fee0b6d08761cce310f05e5cbafd7cc461bc5a6d4c03"
    static let filename = "archi-pearl-study-v1"
    static let lumenRevision = "lumen-pearl-v1-e8430e51"
    static let lumenDigest = "55faaa664fc7e0dfdbc466c50ae1936157d3fe6ec5882e3006c938819c0fabff"
    static let lumenFilename = "archi-lumen-pearl-v1"
    static let maximumBytes = 1_400_000
    static var resourceURL: URL? {
        resourceURL(named: filename)
    }
    static func resourceURL(named name: String) -> URL? {
        // Packaged apps must not silently load an asset from a developer's .build
        // directory. SwiftPM's module bundle remains the resource owner in tests.
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.resourceURL?.appendingPathComponent("CompanionArt/\(name).png")
        }
        return Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "CompanionArt")
    }
    static let image = load(name: filename, digest: digest)
    static let lumenImage = load(name: lumenFilename, digest: lumenDigest)
    private static func load(name: String, digest: String) -> NSImage? {
        guard let url = resourceURL(named: name),
              let byteCount = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              byteCount > 0, byteCount < maximumBytes,
              let data = try? Data(contentsOf: url),
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == digest else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> NSImage? {
        guard data.count < maximumBytes,
              data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? Int) == 512,
              (properties[kCGImagePropertyPixelHeight] as? Int) == 512,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 512, height: 512))
    }

    static func applies(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment) -> Bool {
        form == .companion && (family == nil || family == .lumen) && treatment == .pearlStudy
    }

    static func resolvedImage(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment) -> NSImage? {
        guard applies(form: form, family: family, treatment: treatment) else { return nil }
        return family == .lumen ? lumenImage : image
    }

    static func label(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment,
                      recipe: CompanionAppearanceRecipe? = nil, naturalVariation: CompanionNaturalVariation? = nil) -> String {
        let base: String
        if resolvedImage(form: form, family: family, treatment: treatment) != nil {
            base = "\(family?.title ?? form.rawValue) · \(treatment.rawValue)"
        } else {
            base = family?.title ?? form.rawValue
        }
        if let family, let recipe, recipe.family == family {
            return "\(base) · \(recipe.fingerprint.prefix(8)) · \(recipe.role.title), \(recipe.helpStyle.title)"
        }
        guard let variation = effectiveNaturalVariation(form: form, family: family, recipe: recipe,
            naturalVariation: naturalVariation) else { return base }
        return "\(base) · Individual \(variation.fingerprint.prefix(8))"
    }

    /// Keep presentation support and cache identity in agreement. Authored forms
    /// without a natural drawing path remain unchanged, as do kept legacy recipes.
    static func effectiveNaturalVariation(form: CompanionForm, family: EvolutionFamily?, recipe: CompanionAppearanceRecipe?,
                                          naturalVariation: CompanionNaturalVariation?) -> CompanionNaturalVariation? {
        guard form == .companion, family == nil || family == .lumen,
              !(family != nil && recipe?.family == family) else { return nil }
        return naturalVariation
    }

    static func appearanceID(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment,
                             recipe: CompanionAppearanceRecipe? = nil, naturalVariation: CompanionNaturalVariation? = nil,
                             assetAvailable: Bool? = nil) -> String {
        let base = "\(form.rawValue):\(family?.rawValue ?? "origin")"
        let available = assetAvailable ?? (resolvedImage(form: form, family: family, treatment: treatment) != nil)
        let selectedRevision = family == .lumen ? lumenRevision : revision
        let appearance = applies(form: form, family: family, treatment: treatment) && available ? "\(base):\(selectedRevision)" : base
        if let family, let recipe, recipe.family == family {
            // Habitat limits IDs to 100 characters, including a possible expression
            // suffix. Hash the complete inputs; neither the recipe nor asset identity
            // is truncated. The 67-character ID leaves room for UInt64.max revisions.
            let canonical = "archi-individual-appearance/v1\nappearance=\(appearance)\nrecipe=\(recipe.fingerprint)\n"
            let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
            return "i1-\(digest)"
        }
        guard let variation = effectiveNaturalVariation(form: form, family: family, recipe: recipe,
            naturalVariation: naturalVariation) else { return appearance }
        let canonical = "archi-natural-appearance/v1\nappearance=\(appearance)\nnatural=\(variation.fingerprint)\n"
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return "n1-\(digest)"
    }
}
