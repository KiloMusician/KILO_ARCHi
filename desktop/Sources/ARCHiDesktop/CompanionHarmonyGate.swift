import Foundation

/// One presentation observation. This gate never starts work or infers a mood.
struct CompanionHarmonySnapshot: Equatable, Sendable {
    let expression: KinLightExpression
    let enabled: Bool
    let quiet: Bool
    let visible: Bool
    let previewID: UUID?

    init(expression: KinLightExpression, enabled: Bool, quiet: Bool, visible: Bool, previewID: UUID? = nil) {
        self.expression = expression
        self.enabled = enabled
        self.quiet = quiet
        self.visible = visible
        self.previewID = previewID
    }

    fileprivate var permitsSound: Bool { enabled && !quiet && visible }
}

enum CompanionHarmonyDecision: Equatable, Sendable {
    case none
    case stop
    /// The audio owner replaces any previous cue before playing this one.
    case play(KinLightMode)
}

/// Edge-triggered, bounded sound admission. Suppressed transitions are consumed
/// immediately; no timer or queued cue can replay them later.
struct CompanionHarmonyGate: Sendable {
    static let automaticCooldown: TimeInterval = 4
    private var previous: CompanionHarmonySnapshot?
    private var lastObservedTime: TimeInterval?
    private var lastPlayedAt: TimeInterval?
    private var ownsCue = false

    mutating func update(snapshot: CompanionHarmonySnapshot, now: TimeInterval) -> CompanionHarmonyDecision {
        let prior = previous
        // Even invalid-clock and muted observations consume their transition.
        previous = snapshot
        guard now.isFinite, now >= 0 else { return stopOwnedCue() }
        if let lastObservedTime, now < lastObservedTime { return stopOwnedCue() }
        let hadClockBaseline = lastObservedTime != nil
        lastObservedTime = now
        guard hadClockBaseline, let prior else { return stopOwnedCue() }
        guard snapshot.permitsSound, snapshot.expression.mode != .rest else { return stopOwnedCue() }
        // Re-enabling or showing an existing state must not produce a catch-up cue.
        guard prior.permitsSound else { return stopOwnedCue() }

        let modeChanged = snapshot.expression.mode != prior.expression.mode
        if snapshot.expression.isPreview {
            // A cosmetic state with no explicit preview event is not an audio request.
            guard let id = snapshot.previewID else { return stopOwnedCue() }
            let samePreview = prior.expression.isPreview && prior.previewID == id
            if samePreview {
                return modeChanged ? stopOwnedCue() : .none
            }
            // A deliberate new preview can replace a cue inside the cooldown.
            return admit(snapshot.expression.mode, at: now)
        }

        guard modeChanged else {
            // Finishing a preview may retain the same color, but cannot retain
            // ownership of that preview's sound or replay it automatically.
            return prior.expression.isPreview ? stopOwnedCue() : .none
        }
        if let lastPlayedAt, now - lastPlayedAt < Self.automaticCooldown {
            return stopOwnedCue()
        }
        return admit(snapshot.expression.mode, at: now)
    }

    /// The audio owner stops its player before resetting, for example on app hide.
    /// The next observation establishes a silent baseline rather than replaying work.
    mutating func reset() {
        previous = nil
        lastObservedTime = nil
        lastPlayedAt = nil
        ownsCue = false
    }

    private mutating func admit(_ mode: KinLightMode, at now: TimeInterval) -> CompanionHarmonyDecision {
        lastPlayedAt = now
        ownsCue = true
        return .play(mode)
    }

    private mutating func stopOwnedCue() -> CompanionHarmonyDecision {
        guard ownsCue else { return .none }
        ownsCue = false
        return .stop
    }
}
