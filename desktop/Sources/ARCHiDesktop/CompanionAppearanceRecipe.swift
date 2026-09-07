import CryptoKit
import Foundation

/// A reproducible cosmetic recipe bound to an existing Journey origin. It is
/// neither a new identity nor evidence of ownership, intelligence, or ability.
/// The six stored inputs are the complete recipe; documents, request IDs, time,
/// device identifiers, and runtime settings never participate in its derivation.
struct CompanionAppearanceRecipe: Codable, Equatable, Sendable {
    let version: Int
    let originDigest: String
    let family: EvolutionFamily
    let role: EvolutionRole
    let helpStyle: EvolutionHelpStyle
    let basisKind: EvolutionProposalBasis.Kind

    struct TraitExplanation: Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let value: String
        let reason: String
    }

    private init(originDigest: String, family: EvolutionFamily, role: EvolutionRole,
                 helpStyle: EvolutionHelpStyle, basisKind: EvolutionProposalBasis.Kind) {
        self.version = 1
        self.originDigest = originDigest
        self.family = family
        self.role = role
        self.helpStyle = helpStyle
        self.basisKind = basisKind
    }

    static func make(originDigest: String, family: EvolutionFamily, role: EvolutionRole,
                     helpStyle: EvolutionHelpStyle, basisKind: EvolutionProposalBasis.Kind) -> Self? {
        guard isOriginDigest(originDigest), basisKind != .appearanceChoice else { return nil }
        return Self(originDigest: originDigest, family: family, role: role,
                    helpStyle: helpStyle, basisKind: basisKind)
    }

    /// This identifies the exact saved recipe, not an exclusive asset or owner.
    var fingerprint: String {
        let canonical = "archi-companion-appearance-recipe/v1\n"
            + "origin=\(originDigest)\nfamily=\(family.rawValue)\nrole=\(role.rawValue)\n"
            + "helpStyle=\(helpStyle.rawValue)\nbasis=\(basisKind.rawValue)\n"
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Hue is origin-derived variation plus a stable accent offset for the
    /// explicitly chosen role. It does not infer personality from the origin.
    var accentHue: Double {
        (unit(at: 0) + Double(roleIndex) / 6).truncatingRemainder(dividingBy: 1)
    }

    var horizontalScale: Double { min(1.04, max(0.94, 0.94 + 0.10 * unit(at: 2))) }
    var markingCount: Int { 2 + Int(variationBytes[4]) % 4 }
    /// Radians in [0, 2π), so a full turn has only one representation.
    var markingRotation: Double {
        let bytes = variationBytes
        return Double(Int(bytes[5]) * 256 + Int(bytes[6])) / 65_536 * 2 * .pi
    }

    /// A cosmetic movement multiplier. Quiet and Reduce Motion remain runtime
    /// overrides in the renderer and do not alter the saved recipe or fingerprint.
    var motionSpeed: Double {
        switch helpStyle {
        case .concise: 0.85
        case .exploratory: 1.15
        case .stepByStep: 1.0
        case .reflective: 0.7
        }
    }

    var roleSymbol: String {
        switch role {
        case .hearth: "flame"
        case .muse: "sparkles"
        case .scout: "magnifyingglass"
        case .beacon: "location.north"
        case .keeper: "bookmark"
        case .guardian: "shield"
        }
    }

    var traitExplanations: [TraitExplanation] {
        [
            .init(id: "family", title: "Visual family", value: family.title,
                  reason: "You confirmed \(family.title) when this recipe was proposed. This chooses its visual family."),
            .init(id: "role", title: "Role accent", value: role.title,
                  reason: "Your confirmed \(role.title) role selects an accent offset. It does not grant abilities."),
            .init(id: "help-style", title: "Movement rhythm", value: helpStyle.title,
                  reason: "Your confirmed \(helpStyle.title) help style selects a cosmetic movement rhythm. Quiet and Reduce Motion can keep it still."),
            .init(id: "origin", title: "Personal variation", value: "\(markingCount) markings · \(originDigest.prefix(8))",
                  reason: "Your existing Journey origin and chosen family deterministically vary the tint, width, marking count, and marking angle. These details do not measure personality or guarantee exclusive artwork."),
            .init(id: "basis", title: "Proposal basis", value: basisTitle,
                  reason: basisKind == .usefulWork
                      ? "Two requests you marked useful qualified this proposal under the existing product rule. Their text and request IDs are absent from this recipe."
                      : "A completed practice you reviewed qualified this proposal under the existing product rule. Its outcome does not increase visual power or establish mastery.")
        ]
    }

    private var basisTitle: String {
        basisKind == .usefulWork ? "Two useful work requests" : "First completed practice"
    }

    private var variationBytes: [UInt8] {
        let canonical = "archi-companion-appearance-variation/v1\norigin=\(originDigest)\nfamily=\(family.rawValue)\n"
        return Array(SHA256.hash(data: Data(canonical.utf8)))
    }

    private func unit(at offset: Int) -> Double {
        let bytes = variationBytes
        return Double(Int(bytes[offset]) * 256 + Int(bytes[offset + 1])) / 65_535
    }

    private var roleIndex: Int {
        switch role {
        case .hearth: 0
        case .muse: 1
        case .scout: 2
        case .beacon: 3
        case .keeper: 4
        case .guardian: 5
        }
    }

    private static func isOriginDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, originDigest, family, role, helpStyle, basisKind
    }

    /// A dynamic key container makes unknown input keys visible. A container
    /// keyed only by CodingKeys silently drops them before validation.
    private struct InputKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: InputKey.self)
        guard Set(all.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "An appearance recipe must contain exactly its six supported keys."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .version) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: values,
                debugDescription: "Unsupported appearance recipe version.")
        }
        let originDigest = try values.decode(String.self, forKey: .originDigest)
        guard Self.isOriginDigest(originDigest) else {
            throw DecodingError.dataCorruptedError(forKey: .originDigest, in: values,
                debugDescription: "Journey origin must be exactly 64 lowercase hexadecimal characters.")
        }
        let basisKind = try values.decode(EvolutionProposalBasis.Kind.self, forKey: .basisKind)
        guard basisKind != .appearanceChoice else {
            throw DecodingError.dataCorruptedError(forKey: .basisKind, in: values,
                debugDescription: "Version one recipes only describe historical work or practice rules.")
        }
        self.init(originDigest: originDigest,
                  family: try values.decode(EvolutionFamily.self, forKey: .family),
                  role: try values.decode(EvolutionRole.self, forKey: .role),
                  helpStyle: try values.decode(EvolutionHelpStyle.self, forKey: .helpStyle),
                  basisKind: basisKind)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(originDigest, forKey: .originDigest)
        try values.encode(family, forKey: .family)
        try values.encode(role, forKey: .role)
        try values.encode(helpStyle, forKey: .helpStyle)
        try values.encode(basisKind, forKey: .basisKind)
    }
}


/// Small inherited-looking differences within the existing Pearl family. The
/// Journey owns the individual; this is a pure projection, never a second ID or
/// a saved personality model. It is present before any task or preference gate.
struct CompanionNaturalVariation: Equatable, Sendable {
    let originDigest: String
    private init(originDigest: String) { self.originDigest = originDigest }

    static func make(originDigest: String) -> Self? {
        guard PracticeEvolutionReference.isDigest(originDigest) else { return nil }
        return Self(originDigest: originDigest)
    }

    private var bytes: [UInt8] {
        Array(SHA256.hash(data: Data(("archi-natural-individual/v1\n" + originDigest).utf8)))
    }
    var fingerprint: String { bytes.map { String(format: "%02x", $0) }.joined() }
    private func unit(_ offset: Int) -> Double {
        let data = bytes
        return Double(Int(data[offset]) * 256 + Int(data[offset + 1])) / 65_535
    }
    var horizontalScale: Double { 0.97 + unit(0) * 0.06 }
    var hueDegrees: Double { -4 + unit(2) * 8 }
    var markingCount: Int { 1 + Int(bytes[4]) % 3 }
    var markingRotation: Double { unit(5) * 2 * .pi }
}
