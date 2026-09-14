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
            if equipment.hand == .focusStaff, equipment.isValid {
                Canvas { context, bounds in
                    let u = min(bounds.width, bounds.height)
                    let colors = Self.colors(for: equipment.design?.palette ?? .lilac)
                    let shaft = Path { p in
                        p.move(to: CGPoint(x: u * 0.80, y: u * 0.79))
                        p.addLine(to: CGPoint(x: u * 0.855, y: u * 0.30))
                    }
                    context.stroke(shaft, with: .color(colors.shaft),
                                   style: StrokeStyle(lineWidth: max(1.4, u * 0.018), lineCap: .round))
                    let head = CGRect(x: u * 0.804, y: u * 0.235, width: u * 0.10, height: u * 0.10)
                    let crown = equipment.design?.crown ?? .pearl
                    context.fill(Path(ellipseIn: head.insetBy(dx: -u * 0.022, dy: -u * 0.022)),
                                 with: .color(colors.head.opacity(0.18)))
                    context.fill(Self.crownPath(crown, in: head), with: .color(colors.head))
                    context.stroke(Self.crownPath(crown, in: head), with: .color(colors.shaft.opacity(0.75)),
                                   lineWidth: max(0.8, u * 0.007))
                    context.fill(Self.crownPath(crown, in: head.insetBy(dx: u * 0.027, dy: u * 0.027)),
                                 with: .color(.white.opacity(0.9)))
                }
                if activated && equipment.supportsPointing { FocusStaffSparkles(size: size, reduceMotion: reduceMotion) }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func colors(for palette: CompanionItemPackage.Palette) -> (shaft: Color, head: Color) {
        switch palette {
        // Preserve the existing staff's exact color inputs and compositing.
        case .lilac: (ArchiPalette.violet, ArchiPalette.peach)
        case .mint: (Color(red: 0.14, green: 0.55, blue: 0.43), Color(red: 0.66, green: 0.94, blue: 0.78))
        case .gold: (Color(red: 0.67, green: 0.39, blue: 0.07), Color(red: 1, green: 0.83, blue: 0.29))
        case .rose: (Color(red: 0.70, green: 0.28, blue: 0.48), Color(red: 0.99, green: 0.66, blue: 0.79))
        case .ice: (Color(red: 0.19, green: 0.46, blue: 0.77), Color(red: 0.66, green: 0.90, blue: 1))
        }
    }

    /// Closed local silhouettes fit inside the original head bounds. No design
    /// value can supply geometry, an asset path, or executable rendering code.
    private static func crownPath(_ crown: CompanionItemPackage.Crown, in rect: CGRect) -> Path {
        switch crown {
        case .pearl:
            return Path(ellipseIn: rect)
        case .star:
            return Path { path in
                for index in 0..<10 {
                    let angle = -Double.pi / 2 + Double(index) * Double.pi / 5
                    let radius = index.isMultiple(of: 2) ? 0.5 : 0.23
                    let point = CGPoint(x: rect.midX + CGFloat(cos(angle) * radius) * rect.width,
                                        y: rect.midY + CGFloat(sin(angle) * radius) * rect.height)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
            }
        case .leaf:
            return Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                              control1: CGPoint(x: rect.minX, y: rect.minY),
                              control2: CGPoint(x: rect.midX, y: rect.minY))
                path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                              control1: CGPoint(x: rect.maxX, y: rect.maxY),
                              control2: CGPoint(x: rect.midX, y: rect.maxY))
                path.closeSubpath()
            }
        }
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
