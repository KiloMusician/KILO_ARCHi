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
        guard Set(object.keys) == (version == 2 ? baseKeys.union(["originDigest", "practices", "arena"]) : baseKeys),
              JSONSerialization.isValidJSONObject(object) else { throw HostedPlayError.invalidProjection }
        if version == 2 {
            guard let practices = object["practices"] as? [[String: Any]], practices.count <= 8,
                  practices.allSatisfy({ Set($0.keys) == ["originDigest", "eventId", "battleId", "rulesVersion", "rounds", "outcome", "replayDigest", "committedAt"] }) else {
                throw HostedPlayError.invalidProjection
            }
            if let arena = object["arena"] as? [String: Any] {
                guard Set(arena.keys) == ["battleId", "revision", "phase", "round", "summary", "actions"],
                      let actions = arena["actions"] as? [[String: Any]], actions.count <= 32,
                      actions.allSatisfy({ Set($0.keys) == ["id", "label", "detail"] }) else { throw HostedPlayError.invalidProjection }
            }
        }
        let bytes = try JSONSerialization.data(withJSONObject: object)
        guard bytes.count <= (version == 2 ? 32_768 : 4096) else { throw HostedPlayError.invalidProjection }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard [1, 2].contains(value.version), value.host == "archi-desktop", value.kind == "journey-projection",
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
        if value.version == 2 {
            if value.readiness == .loading {
                guard value.originDigest == nil, value.practices?.isEmpty == true, value.arena == nil else { throw HostedPlayError.invalidProjection }
            } else {
                guard let origin = value.originDigest, HostedArenaProjection.isDigest(origin),
                      let practices = value.practices,
                      practices.allSatisfy({ $0.isValid && $0.originDigest == origin }),
                      Set(practices.map(\.id)).count == practices.count,
                      value.arena == nil || value.arena!.isValid,
                      value.arena == nil || [.habitat, .battle].contains(value.mode) else { throw HostedPlayError.invalidProjection }
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
    }
    let battleId: UUID?
    let revision: String
    let phase: Phase
    let round: Int
    let summary: String
    let actions: [Action]

    var isValid: Bool {
        Self.isDigest(revision) && (0...20).contains(round) && !summary.isEmpty && summary.utf8.count <= 500
            && (phase == .entry ? battleId == nil && round == 0 : battleId != nil && round > 0)
            && actions.count <= 32 && Set(actions.map(\.id)).count == actions.count
            && actions.allSatisfy { !$0.id.isEmpty && $0.id.utf8.count <= 160 && !$0.label.isEmpty
                && $0.label.utf8.count <= 120 && $0.detail.utf8.count <= 300 }
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
