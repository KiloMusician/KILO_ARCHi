import Foundation

/// A reviewed reference to a replayed, committed Journey outcome. This is not
/// another battle ledger and contains no assistant or shared-document content.
struct PracticeEvolutionReference: Codable, Equatable, Sendable, Identifiable {
    enum Outcome: String, Codable, Sendable { case won, lost, draw }
    let originDigest: String
    let eventId: String
    let battleId: UUID
    let rulesVersion: Int
    let rounds: Int
    let outcome: Outcome
    let replayDigest: String
    let committedAt: String

    var id: String { originDigest + ":" + eventId }
    var isValid: Bool {
        guard Self.isDigest(originDigest), Self.isDigest(replayDigest), rulesVersion == 1,
              (1...20).contains(rounds), !eventId.isEmpty, eventId.utf8.count <= 160,
              eventId.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || ":._-".unicodeScalars.contains($0) }),
              committedAt.utf8.count <= 40,
              committedAt.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: committedAt) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: committedAt) != nil
    }

    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static let keys: Set<String> = ["originDigest", "eventId", "battleId", "rulesVersion", "rounds", "outcome", "replayDigest", "committedAt"]
}

/// The rule reviewed when a form was kept. A Journey rebind can retire
/// eligibility without rewriting the historical reason for that kept appearance.
struct EvolutionProposalBasis: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case usefulWork = "useful-work/v1"
        case appearanceChoice = "appearance-choice/v1"
        case completedPractice = "first-completed-practice/v1"
    }
    let kind: Kind
    let practice: PracticeEvolutionReference?

    var title: String {
        switch kind {
        case .usefulWork: "Two useful work requests"
        case .completedPractice: "First completed practice"
        case .appearanceChoice: "Your appearance choice"
        }
    }
    var isValid: Bool {
        switch kind {
        case .usefulWork, .appearanceChoice:
            return practice == nil
        case .completedPractice:
            return practice?.isValid == true
        }
    }
}
