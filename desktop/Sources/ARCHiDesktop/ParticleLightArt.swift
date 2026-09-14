import SwiftUI

/// A local starting body. Time moves only the drawing, never the individual.
struct ParticleLightArt: View {
    let size: CGFloat
    let reduceMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let still = reduceMotion || systemReduceMotion
        TimelineView(.animation(minimumInterval: 1 / 15, paused: still)) { tick in
            ParticleLightFrame(phase: still ? 0 : tick.date.timeIntervalSinceReferenceDate * 0.22)
        }
        .frame(width: size, height: size)
    }
}

/// A fixed frame also used by the existing transparent-PNG handoff to play.
/// Keeping the shell stationary makes slow internal motion readable at icon size.
struct ParticleLightFrame: View {
    let phase: Double
    private let mint = Color(red: 0.48, green: 0.91, blue: 0.81)
    private let teal = Color(red: 0.18, green: 0.57, blue: 0.52)

    var body: some View {
        Canvas { context, canvas in
            let unit = min(canvas.width, canvas.height)
            let center = CGPoint(x: canvas.width / 2, y: canvas.height * 0.465)
            let radius = unit * 0.315
            let shell = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2))

            let ground = CGRect(x: center.x - unit * 0.26, y: unit * 0.825,
                width: unit * 0.52, height: unit * 0.07)
            context.fill(Path(ellipseIn: ground), with: .radialGradient(
                Gradient(colors: [teal.opacity(0.14), mint.opacity(0.04), .clear]),
                center: CGPoint(x: center.x, y: ground.midY), startRadius: 0, endRadius: unit * 0.26))
            let halo = Path(ellipseIn: CGRect(x: center.x - unit * 0.43, y: center.y - unit * 0.43,
                width: unit * 0.86, height: unit * 0.86))
            context.fill(halo, with: .radialGradient(Gradient(stops: [
                .init(color: mint.opacity(0.04), location: 0),
                .init(color: mint.opacity(0.13), location: 0.64),
                .init(color: mint.opacity(0.04), location: 0.83),
                .init(color: .clear, location: 1)
            ]), center: center, startRadius: 0, endRadius: unit * 0.43))
            context.fill(shell, with: .radialGradient(Gradient(stops: [
                .init(color: .white.opacity(0.72), location: 0),
                .init(color: mint.opacity(0.22), location: 0.30),
                .init(color: teal.opacity(0.31), location: 0.76),
                .init(color: mint.opacity(0.59), location: 1)
            ]), center: center, startRadius: 0, endRadius: radius))

            let points = ParticleLightGeometry.project(phase: phase)
            func position(_ point: ParticleLightGeometry.Point) -> CGPoint {
                CGPoint(x: center.x + point.x * radius, y: center.y + point.y * radius)
            }
            context.drawLayer { layer in
                layer.clip(to: shell)
                for edge in ParticleLightGeometry.edges {
                    let a = points[edge.0], b = points[edge.1]
                    var line = Path()
                    line.move(to: position(a)); line.addLine(to: position(b))
                    let depth = (a.z + b.z + 2) / 4
                    layer.stroke(line, with: .color(mint.opacity(0.10 + depth * 0.25)),
                        lineWidth: max(0.35, unit * 0.0018))
                }
                for index in points.indices.sorted(by: { points[$0].z < points[$1].z }) {
                    let point = points[index], pointCenter = position(point)
                    let depth = (point.z + 1) / 2
                    let sparkle = 0.84 + 0.16 * sin(phase * 1.7 + Double(index) * 2.4)
                    let r = max(0.40, unit * (0.0018 + depth * 0.0031))
                    if index.isMultiple(of: 4) {
                        let glow = CGRect(x: pointCenter.x - r * 4, y: pointCenter.y - r * 4,
                            width: r * 8, height: r * 8)
                        layer.fill(Path(ellipseIn: glow), with: .radialGradient(
                            Gradient(colors: [mint.opacity(0.48 * depth), .clear]),
                            center: pointCenter, startRadius: 0, endRadius: r * 4))
                    }
                    layer.fill(Path(ellipseIn: CGRect(x: pointCenter.x - r, y: pointCenter.y - r,
                        width: r * 2, height: r * 2)), with: .color(.white.opacity((0.32 + depth * 0.62) * sparkle)))
                }
            }

            context.stroke(shell, with: .linearGradient(Gradient(colors: [
                .white.opacity(0.96), mint.opacity(0.55), teal.opacity(0.58), .white.opacity(0.76)
            ]), startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
                endPoint: CGPoint(x: center.x + radius, y: center.y + radius)),
                lineWidth: max(0.7, unit * 0.005))
            var glint = Path()
            glint.addArc(center: center, radius: radius * 0.963,
                startAngle: .degrees(205), endAngle: .degrees(271), clockwise: false)
            context.stroke(glint, with: .color(.white.opacity(0.82)),
                style: StrokeStyle(lineWidth: max(0.8, unit * 0.008), lineCap: .round))

            let coreRadius = radius * 0.32
            context.fill(Path(ellipseIn: CGRect(x: center.x - coreRadius, y: center.y - coreRadius,
                width: coreRadius * 2, height: coreRadius * 2)), with: .radialGradient(
                    Gradient(stops: [.init(color: .white, location: 0),
                        .init(color: .white.opacity(0.95), location: 0.13),
                        .init(color: mint.opacity(0.65), location: 0.34),
                        .init(color: .clear, location: 1)]),
                    center: center, startRadius: 0, endRadius: coreRadius))
            var star = Path()
            let long = unit * 0.071, short = unit * 0.008
            star.move(to: CGPoint(x: center.x, y: center.y - long))
            for delta in [(short, -short), (long, 0), (short, short), (0, long),
                          (-short, short), (-long, 0), (-short, -short)] {
                star.addLine(to: CGPoint(x: center.x + delta.0, y: center.y + delta.1))
            }
            star.closeSubpath()
            context.fill(star, with: .color(.white.opacity(0.85)))
        }
        .accessibilityHidden(true)
    }
}

/// Bounded, repeatable geometry, independent of a user's data or the model loop.
enum ParticleLightGeometry {
    struct Point: Equatable {
        let x: Double, y: Double, z: Double
    }

    static let points: [Point] = (0..<72).map { index in
        let y = 1 - (Double(index) + 0.5) * 2 / 72
        let longitude = Double(index) * .pi * (3 - sqrt(5))
        let circle = sqrt(1 - y * y)
        let radius = index.isMultiple(of: 3) ? 0.56 : 0.96
        return Point(x: cos(longitude) * circle * radius, y: y * radius,
            z: sin(longitude) * circle * radius)
    }

    static let edges: [(Int, Int)] = points.indices.flatMap { a in
        ((a + 1)..<points.count).compactMap { b in
            let p = points[a], q = points[b]
            let distance = pow(p.x - q.x, 2) + pow(p.y - q.y, 2) + pow(p.z - q.z, 2)
            return distance < 0.25 ? (a, b) : nil
        }
    }

    static func project(phase: Double) -> [Point] {
        // The angle is bounded even after a long-running desktop session.
        let angle = phase.truncatingRemainder(dividingBy: .pi * 2)
        return points.map { p in
            let x = p.x * cos(angle) + p.z * sin(angle)
            let z = -p.x * sin(angle) + p.z * cos(angle)
            return Point(x: x, y: p.y * cos(0.18) - z * sin(0.18),
                z: p.y * sin(0.18) + z * cos(0.18))
        }
    }
}
