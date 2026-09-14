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

    init(hand: CompanionItemID? = nil) { self.hand = hand }

    static let empty = Self()
    var isEmpty: Bool { hand == nil }
    var item: CompanionItemDescriptor? { hand?.item }

    /// Explicit, stable inputs for the shared artwork's cache identity.
    var canonicalIdentity: String {
        "archi-companion-equipment/v1\nhand=\(hand?.rawValue ?? "none")\n"
    }

    private enum CodingKeys: String, CodingKey { case hand }

    private struct InputKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: InputKey.self)
        guard all.allKeys.allSatisfy({ $0.stringValue == CodingKeys.hand.rawValue }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Equipment contains an unsupported field."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hand = try values.decodeIfPresent(CompanionItemID.self, forKey: .hand)
    }
}
