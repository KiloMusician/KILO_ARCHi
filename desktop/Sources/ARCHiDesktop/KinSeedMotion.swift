import Foundation

/// Ephemeral pose of the existing Seed. Rendering samples an analytical curve;
/// only a mode change replaces its anchor. No frame tick writes companion state.
struct KinSeedMotion: Equatable, Sendable {
    static let revolutionDuration = 80.0
    static let maximumSpeed = 360 / revolutionDuration
    static let settlingDuration = 0.6

    struct Policy: Equatable, Sendable {
        let settles: Bool
        let reduceMotion: Bool

        init(mode: KinLightMode, reduceMotion: Bool = false, systemReduceMotion: Bool = false) {
            settles = mode == .focus || mode == .hold
            self.reduceMotion = reduceMotion || systemReduceMotion
        }

        var targetSpeed: Double { settles || reduceMotion ? 0 : KinSeedMotion.maximumSpeed }
    }

    struct Sample: Equatable, Sendable {
        /// Degrees wrap at one revolution; the rendered orientation is continuous.
        let angle: Double
        let speed: Double
        var radians: Double { angle * .pi / 180 }
    }

    private(set) var policy: Policy
    private var anchorTime: TimeInterval
    private var anchorAngle = 0.0
    private var initialSpeed: Double
    private var duration = 0.0

    init(at time: TimeInterval = 0, policy: Policy = .init(mode: .rest)) {
        anchorTime = time.isFinite && time >= 0 ? time : 0
        self.policy = policy
        initialSpeed = policy.targetSpeed
    }

    mutating func transition(to next: Policy, at time: TimeInterval) {
        guard next != policy, time.isFinite, time >= anchorTime else { return }
        let current = sample(at: time)
        anchorAngle = current.angle
        anchorTime = time
        // Accessibility stops motion immediately at the current orientation.
        // A fresh reduced-motion view/export starts at the fixed reference, 0°.
        initialSpeed = next.reduceMotion ? 0 : current.speed
        duration = next.reduceMotion || initialSpeed == next.targetSpeed ? 0 : Self.settlingDuration
        policy = next
    }

    func sample(at time: TimeInterval) -> Sample {
        let elapsed = time.isFinite && time >= anchorTime ? time - anchorTime : 0
        let rampTime = min(elapsed, duration)
        let fraction = duration > 0 ? rampTime / duration : 1
        let square = fraction * fraction
        let smoothstep = square * (3 - 2 * fraction)
        let speed = initialSpeed + (policy.targetSpeed - initialSpeed) * smoothstep
        // Integral of smoothstep: x³ - x⁴/2. This retains angle AND speed when
        // Focus/Hold is interrupted, without depending on rendering cadence.
        let rampAngle = initialSpeed * rampTime + (policy.targetSpeed - initialSpeed)
            * duration * (square * fraction - square * square / 2)
        // Reduce elapsed time before multiplication so extreme finite timestamps
        // cannot overflow the phase. Steady speed is either 0 or one turn/80 s.
        let steadyTime = max(0, elapsed - duration).truncatingRemainder(dividingBy: Self.revolutionDuration)
        let angle = (anchorAngle + rampAngle + policy.targetSpeed * steadyTime)
            .truncatingRemainder(dividingBy: 360)
        return Sample(angle: angle, speed: min(Self.maximumSpeed, max(0, speed)))
    }
}
