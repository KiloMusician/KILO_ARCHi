import SwiftUI

/// A wearable inside the existing character frame. It neither replaces the body
/// nor owns identity, growth, target geometry or provider execution.
struct CompanionEquipmentArt: View {
    let equipment: CompanionEquipment
    let size: CGFloat
    var activated = false
    var reduceMotion = true

    var body: some View {
        ZStack {
            if equipment.hand == .focusStaff {
                Canvas { context, bounds in
                    let u = min(bounds.width, bounds.height)
                    let shaft = Path { p in
                        p.move(to: CGPoint(x: u * 0.80, y: u * 0.79))
                        p.addLine(to: CGPoint(x: u * 0.855, y: u * 0.30))
                    }
                    context.stroke(shaft, with: .color(ArchiPalette.violet),
                                   style: StrokeStyle(lineWidth: max(1.4, u * 0.018), lineCap: .round))
                    let head = CGRect(x: u * 0.804, y: u * 0.235, width: u * 0.10, height: u * 0.10)
                    context.fill(Path(ellipseIn: head.insetBy(dx: -u * 0.022, dy: -u * 0.022)),
                                 with: .color(ArchiPalette.peach.opacity(0.18)))
                    context.fill(Path(ellipseIn: head), with: .color(ArchiPalette.peach))
                    context.stroke(Path(ellipseIn: head), with: .color(ArchiPalette.violet.opacity(0.75)),
                                   lineWidth: max(0.8, u * 0.007))
                    context.fill(Path(ellipseIn: head.insetBy(dx: u * 0.027, dy: u * 0.027)),
                                 with: .color(.white.opacity(0.9)))
                }
                if activated { FocusStaffSparkles(size: size, reduceMotion: reduceMotion) }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Activity decoration is kept out of exported character artwork. It is shown
/// only while the existing, expiring placement preview remains current.
struct FocusStaffSparkles: View {
    let size: CGFloat
    let reduceMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || systemReduceMotion)) { timeline in
            let phase = reduceMotion || systemReduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 2
            Canvas { context, bounds in
                let u = min(bounds.width, bounds.height)
                for (index, point) in [CGPoint(x: 0.74, y: 0.20), CGPoint(x: 0.91, y: 0.18), CGPoint(x: 0.94, y: 0.35)].enumerated() {
                    let radius = u * (0.014 + 0.004 * sin(phase + Double(index)))
                    let center = CGPoint(x: point.x * u, y: point.y * u)
                    var star = Path()
                    star.move(to: CGPoint(x: center.x, y: center.y - radius))
                    star.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                    star.move(to: CGPoint(x: center.x - radius, y: center.y))
                    star.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                    context.stroke(star, with: .color(ArchiPalette.violet.opacity(0.85)),
                                   style: StrokeStyle(lineWidth: max(0.8, u * 0.006), lineCap: .round))
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
