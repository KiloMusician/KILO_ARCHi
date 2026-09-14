import Foundation

/// Public, already-resolved battle facts supplied by the existing game reducer.
/// This snapshot cannot contain sealed commands and never advances the game.
struct HostedArenaReadback: Equatable, Decodable, Sendable {
    enum TeamID: String, Decodable, Sendable { case one, two }
    enum Role: String, Decodable, Sendable {
        case hearth, muse, scout, beacon, keeper, guardian
    }

    struct Member: Equatable, Decodable, Sendable, Identifiable {
        let id: String
        let name: String
        let role: Role
        let integrity: Int
        let maximumIntegrity: Int
        let active: Bool
        let exposed: Bool

        var isValid: Bool {
            HostedArenaReadback.validText(id, limit: 160)
                && HostedArenaReadback.validText(name, limit: 120)
                && (1...36).contains(maximumIntegrity)
                && (0...maximumIntegrity).contains(integrity)
                && (!active || integrity > 0)
        }
    }

    struct Team: Equatable, Decodable, Sendable, Identifiable {
        let id: TeamID
        let label: String
        let spark: Int
        let roster: [Member]

        var integrity: Int { roster.reduce(0) { $0 + $1.integrity } }
        var maximumIntegrity: Int { roster.reduce(0) { $0 + $1.maximumIntegrity } }
        var activeMember: Member? { roster.first(where: \.active) }
        var reserves: [Member] { roster.filter { !$0.active } }
        var isValid: Bool {
            HostedArenaReadback.validText(label, limit: 120) && (0...3).contains(spark)
                && (1...3).contains(roster.count) && roster.allSatisfy(\.isValid)
                && Set(roster.map(\.id)).count == roster.count
                && maximumIntegrity == 36 && roster.filter(\.active).count <= 1
        }
    }

    struct Round: Equatable, Decodable, Sendable, Identifiable {
        let round: Int
        let summary: String
        var id: Int { round }
        var isValid: Bool {
            (1...20).contains(round) && HostedArenaReadback.validText(summary, limit: 500)
        }
    }

    struct Result: Equatable, Decodable, Sendable {
        enum Winner: String, Decodable, Sendable { case one, two, draw }
        enum Reason: String, Decodable, Sendable {
            case eliminated, roundLimit = "round-limit", surrender
        }
        enum Retention: String, Decodable, Sendable {
            case unsaved, saving, saved, sessionOnly = "session-only", unavailable
        }
        let winner: Winner
        let reason: Reason
        let retention: Retention
        let message: String
        var isValid: Bool { HostedArenaReadback.validText(message, limit: 300) }
    }

    let teams: [Team]
    let rounds: [Round]
    let result: Result?

    var latestRound: Round? { rounds.last }

    func isValid(for phase: HostedArenaProjection.Phase, round: Int) -> Bool {
        guard teams.map(\.id) == [.one, .two], teams.allSatisfy(\.isValid),
              rounds.count <= 20, rounds.allSatisfy(\.isValid),
              rounds.enumerated().allSatisfy({ $0.element.round == $0.offset + 1 }) else { return false }
        let memberIDs = teams.flatMap { $0.roster.map(\.id) }
        guard Set(memberIDs).count == memberIDs.count else { return false }
        switch phase {
        case .entry:
            return false
        case .planning, .sealed:
            return result == nil && rounds.count == round - 1
        case .finished:
            return result?.isValid == true && rounds.count == round
        }
    }

    /// JSONDecoder rejects wrong scalar types; this closes every nested object
    /// before decoding so extra private or authority-bearing fields are rejected.
    static func hasExactKeys(_ body: Any) -> Bool {
        guard let object = body as? [String: Any], Set(object.keys) == ["teams", "rounds", "result"],
              let teams = object["teams"] as? [[String: Any]], teams.count == 2,
              let rounds = object["rounds"] as? [[String: Any]], rounds.count <= 20 else { return false }
        for team in teams {
            guard Set(team.keys) == ["id", "label", "spark", "roster"],
                  let roster = team["roster"] as? [[String: Any]], (1...3).contains(roster.count),
                  roster.allSatisfy({ Set($0.keys) == ["id", "name", "role", "integrity", "maximumIntegrity", "active", "exposed"] }) else { return false }
        }
        guard rounds.allSatisfy({ Set($0.keys) == ["round", "summary"] }) else { return false }
        if !(object["result"] is NSNull) {
            guard let result = object["result"] as? [String: Any],
                  Set(result.keys) == ["winner", "reason", "retention", "message"] else { return false }
        }
        return true
    }

    private static func validText(_ value: String, limit: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= limit
    }
}
