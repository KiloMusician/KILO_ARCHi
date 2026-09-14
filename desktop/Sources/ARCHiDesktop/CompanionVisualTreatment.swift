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
    struct BundledBody: Equatable {
        let filename: String
        let digest: String
        // Complete digest participates in the cache key, independently of the
        // human-facing version and the older Original/Pearl finish preference.
        var canonicalIdentity: String { "\(filename)\nsha256=\(digest)" }
    }

    static func tealBody(for form: CompanionForm) -> BundledBody? {
        switch form {
        case .constellation:
            BundledBody(filename: "archi-teal-constellation-v1", digest: "43c6d8239a4b13d85d54e33e21475c4dc6dd982158bc038d6e3e0271adf54aaf")
        case .sprout:
            BundledBody(filename: "archi-teal-sprout-v1", digest: "9c62aa7904d6e58c1c8b3902697c1ae3fad949782a8326497b52b11da47d8de8")
        case .ribbonSpirit:
            BundledBody(filename: "archi-teal-ribbon-spirit-v1", digest: "3d914e0df829ab991b37acbea58e44c5a0128c56154269c8af2f9155f15da456")
        case .geode:
            BundledBody(filename: "archi-teal-geode-v1", digest: "d5021e29cc0ccc9705069897026db2783253e1a522f7d371a1ecd8f8ea4ada11")
        default: nil
        }
    }

    static let revision = "pearl-study-v1-698cac34"
    static let digest = "698cac349f8d2c2eb184fee0b6d08761cce310f05e5cbafd7cc461bc5a6d4c03"
    static let filename = "archi-pearl-study-v1"
    static let lumenRevision = "lumen-pearl-v1-55faaa66"
    static let lumenDigest = "55faaa664fc7e0dfdbc466c50ae1936157d3fe6ec5882e3006c938819c0fabff"
    static let lumenFilename = "archi-lumen-pearl-v1"
    static let maximumBytes = 1_400_000
    static let kinSeedFilename = "kin-core-seed-blender-v2"
    static let kinSeedDigest = "d88ba7b233a09142b8353b6cdc646100d0da0fcbe2789b8b2071e828ba481707"
    static let kinSeedImage = load(name: kinSeedFilename, digest: kinSeedDigest)
    static let kinFirstLightFilename = "kin-first-light-blender-v1"
    // Replaced only after the final Blender portrait passes source review.
    static let kinFirstLightDigest = "ba5d05407117740796bf3bc6b949a4ffca3178a6b6f8598c5bbcd24b4f82eba0"
    static let kinFirstLightImage = load(name: kinFirstLightFilename, digest: kinFirstLightDigest)
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
    private static let tealImages: [CompanionForm: NSImage] = {
        var images: [CompanionForm: NSImage] = [:]
        for form in CompanionForm.allCases {
            if let body = tealBody(for: form), let image = load(name: body.filename, digest: body.digest) {
                images[form] = image
            }
        }
        return images
    }()
    private static func load(name: String, digest: String) -> NSImage? {
        guard let url = resourceURL(named: name),
              let byteCount = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              byteCount > 0, byteCount < maximumBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return verifiedImage(data, expectedDigest: digest)
    }

    static func verifiedImage(_ data: Data, expectedDigest: String) -> NSImage? {
        guard data.count > 0, data.count < maximumBytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expectedDigest else { return nil }
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
        (family == nil && tealBody(for: form) != nil)
            || (form == .companion && (family == nil || family == .lumen) && treatment == .pearlStudy)
    }

    static func resolvedImage(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment) -> NSImage? {
        if family == nil, tealBody(for: form) != nil { return tealImages[form] }
        guard applies(form: form, family: family, treatment: treatment) else { return nil }
        return family == .lumen ? lumenImage : image
    }

    static func label(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment,
                      recipe: CompanionAppearanceRecipe? = nil, naturalVariation: CompanionNaturalVariation? = nil,
                      equipment: CompanionEquipment = .empty) -> String {
        let label = baseLabel(form: form, family: family, treatment: treatment, recipe: recipe, naturalVariation: naturalVariation)
        guard let item = equipment.item else { return label }
        return "\(label) · \(item.title)"
    }

    private static func baseLabel(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment,
                                  recipe: CompanionAppearanceRecipe?, naturalVariation: CompanionNaturalVariation?) -> String {
        if family == nil, tealBody(for: form) != nil { return form.rawValue }
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
                             equipment: CompanionEquipment = .empty,
                             assetAvailable: Bool? = nil) -> String {
        let base = baseAppearanceID(form: form, family: family, treatment: treatment, recipe: recipe,
            naturalVariation: naturalVariation, assetAvailable: assetAvailable)
        guard !equipment.isEmpty else { return base }
        // Include the complete resolved body and equipment inputs, while leaving
        // room for the hosted bridge's expression revision within 100 characters.
        let canonical = "archi-equipped-appearance/v1\nappearance=\(base)\n\(equipment.canonicalIdentity)"
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return "e1-\(digest)"
    }

    private static func baseAppearanceID(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment,
                                         recipe: CompanionAppearanceRecipe?, naturalVariation: CompanionNaturalVariation?,
                                         assetAvailable: Bool?) -> String {
        if family == nil, form.isOpticalLight {
            // Native geometry has a revision just like bundled artwork. The same
            // fixed frame supplies desktop previews and the retained image bridge.
            return "optical-light-v1:\(form.rawValue)"
        }
        if family == nil, form == .kinSeed {
            return (assetAvailable ?? (kinSeedImage != nil)) ? "k2-\(kinSeedDigest)" : "kin-core-seed-native-fallback-v1"
        }
        if family == nil, form == .kin {
            // Both paths stay inside KinFirstLightPortrait, preserving the same
            // attention clock and core-anchored light. Only the resting body is
            // cached; a missing or unverified asset uses the retained drawing.
            return (assetAvailable ?? (kinFirstLightImage != nil))
                ? "kf1-\(kinFirstLightDigest)" : "kin-first-light-native-v2"
        }
        if family == nil, let body = tealBody(for: form) {
            let available = assetAvailable ?? (tealImages[form] != nil)
            let presentation = available ? body.canonicalIdentity : "local-fallback/v1\nform=\(form.rawValue)"
            let canonical = "archi-teal-body/v1\n\(presentation)\n"
            let hash = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
            return "t1-\(hash)"
        }
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
