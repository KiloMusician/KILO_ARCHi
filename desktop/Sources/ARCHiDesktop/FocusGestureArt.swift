import SwiftUI

/// A single sampled moment of the taught staff gesture. It depends only on the
/// captured lesson and elapsed time, never on identity, source, or target state.
struct FocusGestureSample: Equatable, Sendable {
    let shaftProgress: Double
    let shaftOpacity: Double
    let headOpacity: Double
    let sparkleOpacity: Double
    let sparkleScale: Double

    static let hidden = Self(shaftProgress: 0, shaftOpacity: 0, headOpacity: 0,
                             sparkleOpacity: 0, sparkleScale: 0)
    var isVisible: Bool { shaftOpacity > 0 || headOpacity > 0 || sparkleOpacity > 0 }

    static func sample(elapsed: TimeInterval, configuration: FocusGestureConfiguration,
                       reduceMotion: Bool) -> Self {
        guard elapsed.isFinite, elapsed >= 0, elapsed < configuration.duration else { return .hidden }
        // A steady, modest head light takes the place of all travel and sparkle.
        // Its lifetime still belongs to the original playback, not a new loop.
        if reduceMotion {
            return Self(shaftProgress: 1, shaftOpacity: 0, headOpacity: 0.60,
                        sparkleOpacity: 0, sparkleScale: 0)
        }
        let travel = configuration.travelDuration
        let progress = min(1, elapsed / travel)
        let easedProgress = progress * progress * (3 - 2 * progress)
        let arrival = elapsed - travel
        let fadeStart = travel + configuration.holdDuration
        let fadeDuration = configuration.duration - fadeStart
        let fade = elapsed <= fadeStart ? 1 : max(0, (configuration.duration - elapsed) / fadeDuration)
        let startup = min(1, elapsed / 0.12)
        let shaftOpacity = arrival < 0 ? startup : max(0, 1 - arrival / 0.12)
        let headOpacity = min(1, max(0, (progress - 0.85) / 0.15)) * fade
        let sparkleDuration = min(configuration.holdDuration, 0.5)
        let sparkleStrength: Double = switch configuration.sparkle {
        case .none: 0
        case .soft: 0.55
        case .bright: 1
        }
        let pulse = arrival >= 0 && arrival < sparkleDuration
            ? sin(.pi * arrival / sparkleDuration) : 0
        return Self(shaftProgress: easedProgress, shaftOpacity: shaftOpacity,
                    headOpacity: headOpacity, sparkleOpacity: pulse * sparkleStrength,
                    sparkleScale: 0.72 + 0.28 * pulse)
    }

    /// Explicit finite entries avoid a perpetually running animation timeline.
    /// Wall-clock dates schedule refreshes only; sampling and expiry use uptime.
    static func timelineDates(playback: FocusGesturePlayback, uptime: TimeInterval,
                              wallClock: Date) -> [Date] {
        guard playback.isFresh(at: uptime), wallClock.timeIntervalSinceReferenceDate.isFinite else { return [] }
        let remaining = playback.configuration.duration - (uptime - playback.startedAt)
        let interval = 1.0 / 24.0
        let count = Int(ceil(remaining / interval))
        return (0...count).map { wallClock.addingTimeInterval(min(remaining, Double($0) * interval)) }
    }
}

/// Transient decoration above the existing equipped body. The staff and body
/// exports stay static; this overlay never changes their bytes or appearance ID.
struct FocusStaffGestureOverlay: View {
    let playback: FocusGesturePlayback
    let size: CGFloat
    let reduceMotion: Bool
    /// A fixed sample for review sheets and deterministic renderer tests only.
    /// Runtime callers leave this absent and use the captured monotonic start.
    var elapsed: TimeInterval? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var expiredPlaybackID: UUID?

    private var reduced: Bool { reduceMotion || systemReduceMotion }
    private var frameSize: CGFloat { size.isFinite && size > 0 ? size : 1 }

    var body: some View {
        Group {
            if let elapsed {
                artwork(FocusGestureSample.sample(elapsed: elapsed,
                    configuration: playback.configuration, reduceMotion: reduced))
            } else if expiredPlaybackID != playback.id,
                      playback.isFresh(at: ProcessInfo.processInfo.systemUptime) {
                if reduced {
                    artwork(FocusGestureSample.sample(elapsed: ProcessInfo.processInfo.systemUptime - playback.startedAt,
                        configuration: playback.configuration, reduceMotion: true))
                } else {
                    TimelineView(.explicit(FocusGestureSample.timelineDates(playback: playback,
                        uptime: ProcessInfo.processInfo.systemUptime, wallClock: Date()))) { _ in
                        artwork(FocusGestureSample.sample(elapsed: ProcessInfo.processInfo.systemUptime - playback.startedAt,
                            configuration: playback.configuration, reduceMotion: false))
                    }
                }
            }
        }
        .frame(width: frameSize, height: frameSize)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: playback.id) {
            guard elapsed == nil else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard playback.isFresh(at: now) else {
                expiredPlaybackID = playback.id
                return
            }
            let remaining = playback.configuration.duration - (now - playback.startedAt)
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            guard !Task.isCancelled else { return }
            expiredPlaybackID = playback.id
        }
    }

    private func artwork(_ sample: FocusGestureSample) -> some View {
        Canvas { context, bounds in
            guard sample.isVisible else { return }
            let u = min(bounds.width, bounds.height)
            let tint = Color(red: 0.42, green: 0.84, blue: 0.77)
            let head = CGPoint(x: 0.854 * u, y: 0.285 * u)

            if sample.shaftOpacity > 0 {
                func shaftPoint(_ progress: Double) -> CGPoint {
                    CGPoint(x: (0.80 + 0.055 * progress) * u, y: (0.79 - 0.49 * progress) * u)
                }
                let point = shaftPoint(sample.shaftProgress)
                let trail = Path { path in
                    path.move(to: shaftPoint(max(0, sample.shaftProgress - 0.16)))
                    path.addLine(to: point)
                }
                context.stroke(trail, with: .color(tint.opacity(sample.shaftOpacity * 0.42)),
                    style: StrokeStyle(lineWidth: max(1, u * 0.027), lineCap: .round))
                let radius = u * 0.035
                let glow = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: glow), with: .radialGradient(
                    Gradient(colors: [tint.opacity(sample.shaftOpacity), tint.opacity(0)]),
                    center: point, startRadius: 0, endRadius: radius))
                context.fill(Path(ellipseIn: glow.insetBy(dx: radius * 0.72, dy: radius * 0.72)),
                    with: .color(.white.opacity(sample.shaftOpacity)))
            }

            if sample.headOpacity > 0 {
                let radius = u * 0.085
                let glow = CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: glow), with: .radialGradient(
                    Gradient(colors: [.white.opacity(sample.headOpacity * 0.9),
                                      tint.opacity(sample.headOpacity * 0.65), tint.opacity(0)]),
                    center: head, startRadius: 0, endRadius: radius))
                context.stroke(Path(ellipseIn: glow.insetBy(dx: u * 0.025, dy: u * 0.025)),
                    with: .color(tint.opacity(sample.headOpacity * 0.50)), lineWidth: max(0.7, u * 0.006))
            }

            if sample.sparkleOpacity > 0 {
                let radius = u * 0.074 * sample.sparkleScale
                let inset = radius * 0.18
                let star = Path { path in
                    path.move(to: CGPoint(x: head.x, y: head.y - radius))
                    path.addLine(to: CGPoint(x: head.x + inset, y: head.y - inset))
                    path.addLine(to: CGPoint(x: head.x + radius, y: head.y))
                    path.addLine(to: CGPoint(x: head.x + inset, y: head.y + inset))
                    path.addLine(to: CGPoint(x: head.x, y: head.y + radius))
                    path.addLine(to: CGPoint(x: head.x - inset, y: head.y + inset))
                    path.addLine(to: CGPoint(x: head.x - radius, y: head.y))
                    path.addLine(to: CGPoint(x: head.x - inset, y: head.y - inset))
                    path.closeSubpath()
                }
                context.fill(star, with: .color(.white.opacity(sample.sparkleOpacity)))
            }
        }
    }
}
