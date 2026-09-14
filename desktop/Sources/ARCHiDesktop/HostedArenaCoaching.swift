import Foundation

/// A nearby person's temporary advice in the native Arena. Accepting returns a
/// projected move for the player's draft; this type cannot seal or play a turn.
struct HostedArenaCoaching: Equatable, Sendable {
    struct Context: Equatable, Sendable {
        let sessionID: UUID
        let visibilityRevision: Int
        let journeyRevision: String
        let arenaRevision: String
        let battleID: UUID
    }

    struct Offer: Equatable, Sendable {
        let action: HostedArenaProjection.Action
        let reason: String
    }

    struct Session: Equatable, Identifiable, Sendable {
        let id: UUID
        let context: Context
        let choices: [HostedArenaProjection.Action]
        fileprivate(set) var offer: Offer?
    }

    private(set) var session: Session?

    /// Eligibility comes from the current projected actions. This only removes
    /// non-move intents and the other player's controls; it never invents moves.
    static func legalChoices(from actions: [HostedArenaProjection.Action]) -> [HostedArenaProjection.Action] {
        actions.filter { action in
            guard action.isValid else { return false }
            if ["one:pulse", "one:guard", "one:signature"].contains(action.id) { return true }
            let parts = action.id.split(separator: ":", omittingEmptySubsequences: false)
            return parts.count == 3 && parts[0] == "one" && ["signature", "swap"].contains(String(parts[1]))
                && !parts[2].isEmpty && !parts[2].contains(where: \.isWhitespace)
                && !parts[2].unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }
    }

    @discardableResult
    mutating func begin(context: Context, choices: [HostedArenaProjection.Action]) -> UUID? {
        guard Self.validChoices(choices) else { return nil }
        let id = UUID()
        session = Session(id: id, context: context, choices: choices, offer: nil)
        return id
    }

    @discardableResult
    mutating func offer(sessionID: UUID, actionID: String, reason: String, context: Context,
                        choices: [HostedArenaProjection.Action]) -> Bool {
        guard var current = matchingSession(id: sessionID, context: context, choices: choices),
              let action = choices.first(where: { $0.id == actionID }),
              let reason = Self.normalizedReason(reason) else { return false }
        current.offer = Offer(action: action, reason: reason)
        session = current
        return true
    }

    /// The caller may select this action in its native draft. Actual play still
    /// requires the player's separate, existing Arena action.
    mutating func accept(sessionID: UUID, context: Context,
                         choices: [HostedArenaProjection.Action]) -> HostedArenaProjection.Action? {
        guard let current = matchingSession(id: sessionID, context: context, choices: choices),
              let offer = current.offer, choices.contains(offer.action) else { return nil }
        session = nil
        return offer.action
    }

    mutating func dismiss(sessionID: UUID) {
        guard session?.id == sessionID else { return }
        session = nil
    }

    mutating func reconcile(context: Context?, choices: [HostedArenaProjection.Action]) {
        guard let current = session else { return }
        guard let context, current.context == context, current.choices == choices else {
            session = nil
            return
        }
    }

    mutating func reset() { session = nil }

    private func matchingSession(id: UUID, context: Context,
                                 choices: [HostedArenaProjection.Action]) -> Session? {
        guard let current = session, current.id == id, current.context == context,
              current.choices == choices, Self.validChoices(choices) else { return nil }
        return current
    }

    private static func validChoices(_ choices: [HostedArenaProjection.Action]) -> Bool {
        !choices.isEmpty && choices.count <= 32 && legalChoices(from: choices) == choices
            && Set(choices.map(\.id)).count == choices.count
    }

    static func normalizedReason(_ reason: String) -> String? {
        guard !reason.unicodeScalars.contains(where: { scalar in
            // Joiners are ordinary parts of words and composed emoji. Other
            // control/format scalars and line separators are not prose input.
            CharacterSet.newlines.contains(scalar) ||
                (CharacterSet.controlCharacters.contains(scalar) && scalar.value != 0x200C && scalar.value != 0x200D)
        }) else { return nil }
        let normalized = reason.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !normalized.isEmpty, normalized.count <= 240 else { return nil }
        return normalized
    }
}
