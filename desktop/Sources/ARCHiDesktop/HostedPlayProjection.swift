import Foundation

/// Read-back from the bundled reducer. Native controls send intents against this
/// revision; only the existing game can admit rounds or Journey events.
struct HostedPlayProjection: Equatable, Decodable, Sendable {
    enum Readiness: String, Decodable, Sendable { case loading, ready }
    enum Storage: String, Decodable, Sendable {
        case unknown, localBrowser = "local-browser", sessionOnly = "session-only", qaEphemeral = "qa-ephemeral"
    }
    enum Mode: String, Decodable, Sendable { case habitat, field, proposal, reflection, battle, relay }
    let version: Int
    let host: String
    let sessionId: String
    let sequence: Int
    let kind: String
    let readiness: Readiness
    let storage: Storage
    let mode: Mode
    let journeyId: String?
    let revision: String?
    let eventCount: Int?
    let visible: Bool
    let originDigest: String?
    let practices: [PracticeEvolutionReference]?
    let arena: HostedArenaProjection?

    static func decode(_ body: Any, sessionID: UUID, after sequence: Int) throws -> Self {
        guard let object = body as? [String: Any] else { throw HostedPlayError.invalidProjection }
        let baseKeys: Set<String> = [
            "version", "host", "sessionId", "sequence", "kind", "readiness", "storage", "mode", "journeyId", "revision", "eventCount", "visible"
        ]
        let version = object["version"] as? Int
        guard Set(object.keys) == ([2, 3, 4].contains(version ?? 0) ? baseKeys.union(["originDigest", "practices", "arena"]) : baseKeys),
              JSONSerialization.isValidJSONObject(object) else { throw HostedPlayError.invalidProjection }
        if [2, 3, 4].contains(version ?? 0) {
            guard let practices = object["practices"] as? [[String: Any]], practices.count <= 8,
                  practices.allSatisfy({ Set($0.keys) == ["originDigest", "eventId", "battleId", "rulesVersion", "rounds", "outcome", "replayDigest", "committedAt"] }) else {
                throw HostedPlayError.invalidProjection
            }
            if let arena = object["arena"] as? [String: Any] {
                var arenaKeys: Set<String> = ["battleId", "revision", "phase", "round", "summary", "actions"]
                if [3, 4].contains(version ?? 0) { arenaKeys.insert("whatIf") }
                if version == 4 { arenaKeys.insert("readback") }
                guard Set(arena.keys) == arenaKeys,
                      let actions = arena["actions"] as? [[String: Any]], actions.count <= 32,
                      actions.allSatisfy({ Set($0.keys) == ["id", "label", "detail"] }) else { throw HostedPlayError.invalidProjection }
                if [3, 4].contains(version ?? 0), !(arena["whatIf"] is NSNull) {
                    guard let whatIf = arena["whatIf"] as? [String: Any],
                          Set(whatIf.keys) == ["choices", "firstId", "secondId", "cases"],
                          let choices = whatIf["choices"] as? [[String: Any]], (2...7).contains(choices.count),
                          choices.allSatisfy({ Set($0.keys) == ["id", "label", "detail"] }),
                          let cases = whatIf["cases"] as? [[String: Any]], (1...7).contains(cases.count),
                          cases.allSatisfy({ Set($0.keys) == ["opponentId", "opponentLabel", "first", "second"] }) else {
                        throw HostedPlayError.invalidProjection
                    }
                }
                if version == 4, !(arena["readback"] is NSNull) {
                    guard let readback = arena["readback"], HostedArenaReadback.hasExactKeys(readback) else {
                        throw HostedPlayError.invalidProjection
                    }
                }
            }
        }
        let bytes = try JSONSerialization.data(withJSONObject: object)
        guard bytes.count <= ([2, 3, 4].contains(version ?? 0) ? 32_768 : 4096) else { throw HostedPlayError.invalidProjection }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard [1, 2, 3, 4].contains(value.version), value.host == "archi-desktop", value.kind == "journey-projection",
              UUID(uuidString: value.sessionId) == sessionID,
              value.sequence > sequence, value.sequence <= 9_007_199_254_740_991,
              value.eventCount == nil || (0...9_007_199_254_740_991).contains(value.eventCount!),
              value.journeyId == nil || (!value.journeyId!.isEmpty && value.journeyId!.utf8.count <= 256),
              value.revision == nil || (!value.revision!.isEmpty && value.revision!.utf8.count <= 1024) else {
            throw HostedPlayError.invalidProjection
        }
        if value.readiness == .loading {
            guard value.storage == .unknown, value.mode == .habitat,
                  value.journeyId == nil, value.revision == nil, value.eventCount == nil else { throw HostedPlayError.invalidProjection }
        } else {
            guard value.storage != .unknown, value.journeyId != nil, value.revision != nil, value.eventCount != nil else { throw HostedPlayError.invalidProjection }
        }
        if [2, 3, 4].contains(value.version) {
            if value.readiness == .loading {
                guard value.originDigest == nil, value.practices?.isEmpty == true, value.arena == nil else { throw HostedPlayError.invalidProjection }
            } else {
                guard let origin = value.originDigest, HostedArenaProjection.isDigest(origin),
                      let practices = value.practices,
                      practices.allSatisfy({ $0.isValid && $0.originDigest == origin }),
                      Set(practices.map(\.id)).count == practices.count,
                      value.arena == nil || value.arena!.isValid,
                      value.arena == nil || [.habitat, .battle].contains(value.mode) else { throw HostedPlayError.invalidProjection }
                if value.version == 4, let arena = value.arena {
                    guard arena.phase == .entry ? arena.readback == nil : arena.readback != nil else {
                        throw HostedPlayError.invalidProjection
                    }
                }
            }
        }
        // Only transport sequence is monotonic. An explicit web-owned import or
        // Reset can replace identity, revision, and event count with older state.
        return value
    }
}

struct HostedArenaProjection: Equatable, Decodable, Sendable {
    enum Phase: String, Decodable, Sendable { case entry, planning, sealed, finished }
    struct Action: Equatable, Decodable, Sendable, Identifiable {
        let id: String
        let label: String
        let detail: String
        var isValid: Bool {
            !id.isEmpty && id.utf8.count <= 160 && !label.isEmpty && label.utf8.count <= 120 && detail.utf8.count <= 300
        }
    }
    struct WhatIf: Equatable, Decodable, Sendable {
        struct Case: Equatable, Decodable, Sendable, Identifiable {
            let opponentId: String
            let opponentLabel: String
            let first: String
            let second: String
            var id: String { opponentId }
            var isValid: Bool {
                !opponentId.isEmpty && opponentId.utf8.count <= 160 && !opponentLabel.isEmpty && opponentLabel.utf8.count <= 120
                    && !first.isEmpty && first.utf8.count <= 700 && !second.isEmpty && second.utf8.count <= 700
            }
        }
        let choices: [Action]
        let firstId: String
        let secondId: String
        let cases: [Case]
        var isValid: Bool {
            (2...7).contains(choices.count) && choices.allSatisfy(\.isValid)
                && Set(choices.map(\.id)).count == choices.count && firstId != secondId
                && choices.contains(where: { $0.id == firstId }) && choices.contains(where: { $0.id == secondId })
                && (1...7).contains(cases.count) && cases.allSatisfy(\.isValid)
                && Set(cases.map(\.opponentId)).count == cases.count
        }
    }
    let battleId: UUID?
    let revision: String
    let phase: Phase
    let round: Int
    let summary: String
    let actions: [Action]
    let whatIf: WhatIf?
    let readback: HostedArenaReadback?

    init(battleId: UUID?, revision: String, phase: Phase, round: Int, summary: String, actions: [Action], whatIf: WhatIf? = nil, readback: HostedArenaReadback? = nil) {
        self.battleId = battleId; self.revision = revision; self.phase = phase; self.round = round
        self.summary = summary; self.actions = actions; self.whatIf = whatIf
        self.readback = readback
    }

    var isValid: Bool {
        Self.isDigest(revision) && (0...20).contains(round) && !summary.isEmpty && summary.utf8.count <= 500
            && (phase == .entry ? battleId == nil && round == 0 : battleId != nil && round > 0)
            && actions.count <= 32 && Set(actions.map(\.id)).count == actions.count
            && actions.allSatisfy(\.isValid)
            && (whatIf == nil || (phase == .planning && whatIf!.isValid))
            && (readback == nil || readback!.isValid(for: phase, round: round))
    }
    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

enum HostedPlayNavigation {
    static func requiresNewSession(from old: URL?, to next: URL?, isReload: Bool) -> Bool {
        guard !isReload, let old, let next,
              old.absoluteString.components(separatedBy: "#").first == next.absoluteString.components(separatedBy: "#").first,
              old.fragment != next.fragment else { return true }
        return false
    }
    static func sameOrigin(_ url: URL?, profile: HostedPlayProfile) -> Bool {
        guard let url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "http" && parts.host == "127.0.0.1" && parts.port == Int(profile.port)
            && parts.user == nil && parts.password == nil
    }
    static func allowsDocument(_ url: URL?, profile: HostedPlayProfile) -> Bool {
        sameOrigin(url, profile: profile) && ["", "/", "/index.html"].contains(url?.path ?? "")
    }
    static func allowsDownload(_ url: URL?, profile: HostedPlayProfile) -> Bool {
        guard let url, url.scheme == "blob", let inner = URL(string: String(url.absoluteString.dropFirst(5))) else { return false }
        return sameOrigin(inner, profile: profile)
    }
}

struct HostedPlayProjectionGate {
    private(set) var sessionID = UUID()
    private(set) var sequence = 0
    private(set) var isActive = false
    mutating func begin() {
        sessionID = UUID(); sequence = 0; isActive = true
    }
    mutating func retire() { isActive = false }
    mutating func receive(_ body: Any) throws -> HostedPlayProjection {
        guard isActive else { throw HostedPlayError.invalidProjection }
        let value = try HostedPlayProjection.decode(body, sessionID: sessionID, after: sequence)
        sequence = value.sequence
        return value
    }
}
