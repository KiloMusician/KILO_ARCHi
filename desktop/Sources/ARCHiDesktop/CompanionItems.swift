import Foundation

/// Bundled, data-only designs. An item ID identifies a design, not ownership,
/// an issued collectible, a permission, or learned knowledge.
enum CompanionItemID: String, Codable, CaseIterable, Identifiable, Sendable {
    case focusStaff = "focus-staff/v1"

    var id: String { rawValue }
    var item: CompanionItemDescriptor { CompanionItemDescriptor.item(for: self) }
}

struct CompanionItemDescriptor: Equatable, Identifiable, Sendable {
    let id: CompanionItemID
    let title: String
    let creator: String
    let provenanceLabel: String
    let summary: String
    let effectDescription: String

    static func item(for id: CompanionItemID) -> Self {
        switch id {
        case .focusStaff:
            Self(id: id, title: "Focus Staff", creator: "Hampton", provenanceLabel: "Bundled design",
                 summary: "A small light-bearing staff for your companion.",
                 effectDescription: "A gentle sparkle and a shortcut to the selected-passage placement preview.")
        }
    }
}

/// A selection in the existing appearance preferences. The starter has no
/// equipment, and a selection contains no private context or executable effect.
struct CompanionEquipment: Codable, Equatable, Sendable {
    var hand: CompanionItemID?
    var design: CompanionItemPackage?

    init(hand: CompanionItemID? = nil, design: CompanionItemPackage? = nil) {
        self.hand = hand
        self.design = design
    }

    static let empty = Self()
    var isEmpty: Bool { hand == nil }
    var isValid: Bool { design == nil || (hand == .focusStaff && design?.isValid == true) }
    var supportsPointing: Bool { isValid && hand == .focusStaff && (design == nil || design?.action == .pointSelection) }

    var item: CompanionItemDescriptor? {
        guard isValid, let hand else { return nil }
        guard let design else { return hand.item }
        let registration = CompanionItemCatalog.registeredDesign(for: design)
        return CompanionItemDescriptor(id: hand, title: Self.boundedLabel(design.title, limit: 24),
            creator: Self.boundedLabel(design.creator, limit: 48),
            provenanceLabel: registration.isRegistered ? registration.label : "Creator design · claimed attribution",
            summary: design.summary,
            effectDescription: supportsPointing
                ? "A local staff variation with a shortcut to the selected-passage placement preview."
                : "A decorative staff variation. It does not activate pointing or assistant requests.")
    }

    /// Explicit, stable inputs for the shared artwork's cache identity.
    var canonicalIdentity: String {
        guard let design else {
            return "archi-companion-equipment/v1\nhand=\(hand?.rawValue ?? "none")\n"
        }
        return "archi-companion-equipment/v2\nhand=\(hand?.rawValue ?? "none")\ndesign=\(design.id)\n"
    }

    private enum CodingKeys: String, CodingKey { case hand, design }

    /// The descriptor is also used in accessibility labels. Keep creator text
    /// single-line and bounded; the avatar renderer applies its own total budget.
    private static func boundedLabel(_ text: String, limit: Int) -> String {
        let singleLine = text.components(separatedBy: .controlCharacters).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        for character in singleLine {
            let next = String(character)
            guard result.utf16.count + next.utf16.count <= limit else { break }
            result += next
        }
        return result
    }

    private struct InputKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: InputKey.self)
        guard all.allKeys.allSatisfy({ [CodingKeys.hand.rawValue, CodingKeys.design.rawValue].contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Equipment contains an unsupported field."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hand = try values.decodeIfPresent(CompanionItemID.self, forKey: .hand)
        design = try values.decodeIfPresent(CompanionItemPackage.self, forKey: .design)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "A creator design requires a valid Focus Staff selection."))
        }
    }

    func encode(to encoder: Encoder) throws {
        guard isValid else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                debugDescription: "A creator design requires a valid Focus Staff selection."))
        }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(hand, forKey: .hand)
        try values.encodeIfPresent(design, forKey: .design)
    }
}
