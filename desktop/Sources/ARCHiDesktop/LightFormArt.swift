import SwiftUI

/// A local expression of the supplied Light Form study. This view owns only
/// drawing time; it cannot change identity, growth, task status or placement.
struct LightFormArt: View {
    let form: CompanionForm
    let size: CGFloat
    let reduceMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let still = reduceMotion || systemReduceMotion
        TimelineView(.animation(minimumInterval: 1 / 15, paused: still)) { tick in
            LightFormFrame(form: form, phase: still ? 0 : tick.date.timeIntervalSinceReferenceDate * 0.18)
        }
        .frame(width: size, height: size)
    }
}

/// Fixed transparent frame used by the existing companion snapshot handoff.
/// Broad glass lenses and fine dark edges remain legible on light or dark desks.
struct LightFormFrame: View {
    let form: CompanionForm
    let phase: Double
    private let mint = Color(red: 0.51, green: 0.91, blue: 0.81)
    private let seaGlass = Color(red: 0.24, green: 0.69, blue: 0.61)
    private let deepTeal = Color(red: 0.09, green: 0.38, blue: 0.35)
    private let pearl = Color(red: 0.98, green: 1.0, blue: 0.93)

    var body: some View {
        Canvas { context, canvas in
            let unit = min(canvas.width, canvas.height)
            guard unit > 0 else { return }
            let phase = LightFormGeometry.normalizedPhase(self.phase)
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2 - unit * 0.04)
            let breath = 1 + sin(phase) * 0.012
            let isCore = form == .corePearl
            let isField = form == .orbitField

            // The pool gives the transparent body a resting plane without an
            // opaque rectangle, drop shadow silhouette, or moving window frame.
            drawPool(context: &context, center: CGPoint(x: center.x, y: center.y + unit * 0.405), unit: unit,
                     strength: isCore ? 0.72 : 1)
            let haloRadius = unit * (isCore ? 0.32 : 0.425)
            glow(context: &context, at: center, radius: haloRadius,
                 colors: [mint.opacity(isField ? 0.025 : 0.14), seaGlass.opacity(0.035), .clear])

            if !isCore {
                let shellRadius = unit * 0.327 * breath
                let shell = circle(center, radius: shellRadius)
                context.fill(shell, with: .radialGradient(Gradient(stops: [
                    .init(color: .clear, location: 0.4),
                    .init(color: mint.opacity(isField ? 0.018 : 0.065), location: 0.88),
                    .init(color: seaGlass.opacity(isField ? 0.04 : 0.14), location: 1)
                ]), center: center, startRadius: 0, endRadius: shellRadius))
                context.stroke(shell, with: .color(seaGlass.opacity(isField ? 0.18 : 0.3)),
                               lineWidth: max(0.4, unit * 0.0017))
                drawOrbit(context: &context, center: center, unit: unit, phase: phase)
            }

            if !isCore && !isField {
                // Back lenses precede the front lenses and pearl. Each lens has
                // a low-opacity interior with a thicker luminous optical rim.
                for petal in LightFormGeometry.petals(phase: phase) {
                    drawPetal(context: &context, center: center, unit: unit * breath, petal: petal)
                }
            }

            let coreRadius = unit * (isCore ? 0.198 : isField ? 0.078 : 0.165) * breath
            drawPearl(context: &context, center: center, radius: coreRadius, unit: unit)

            let motes = LightFormGeometry.motes(phase: phase)
            for (index, mote) in motes.enumerated() {
                if isCore && !index.isMultiple(of: 4) { continue }
                let distance = isCore ? 0.66 : 1.0
                let point = CGPoint(x: center.x + mote.x * unit * distance,
                                    y: center.y + mote.y * unit * distance)
                let radius = max(0.45, mote.radius * unit)
                glow(context: &context, at: point, radius: radius * 4.5,
                     colors: [mint.opacity(mote.opacity * 0.52), mint.opacity(mote.opacity * 0.12), .clear])
                context.fill(circle(point, radius: radius), with: .color(pearl.opacity(mote.opacity)))
                if index.isMultiple(of: 6) {
                    context.stroke(circle(point, radius: radius * 1.1), with: .color(seaGlass.opacity(0.55)),
                                   lineWidth: max(0.3, unit * 0.001))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func drawPetal(context: inout GraphicsContext, center: CGPoint, unit: CGFloat,
                           petal: LightFormGeometry.Petal) {
        var lens = context
        lens.translateBy(x: center.x + petal.x * unit, y: center.y + petal.y * unit)
        lens.rotate(by: .radians(petal.rotation))
        let width = unit * 0.279 * petal.scale
        let height = unit * 0.455 * petal.scale
        let bounds = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        let shape = Path(ellipseIn: bounds)
        lens.fill(shape, with: .linearGradient(Gradient(stops: [
            .init(color: pearl.opacity(petal.front ? 0.68 : 0.19), location: 0),
            .init(color: mint.opacity(petal.front ? 0.47 : 0.18), location: 0.22),
            .init(color: seaGlass.opacity(petal.front ? 0.16 : 0.10), location: 0.61),
            .init(color: mint.opacity(petal.front ? 0.37 : 0.16), location: 1)
        ]), startPoint: CGPoint(x: -width * 0.2, y: -height / 2),
            endPoint: CGPoint(x: width * 0.36, y: height / 2)))
        lens.stroke(shape, with: .color(deepTeal.opacity(petal.front ? 0.22 : 0.12)),
                    lineWidth: max(0.65, unit * 0.0038))
        lens.stroke(shape, with: .linearGradient(Gradient(colors: [
            pearl.opacity(petal.front ? 0.85 : 0.35), mint.opacity(0.25), pearl.opacity(petal.front ? 0.55 : 0.22)
        ]), startPoint: CGPoint(x: -width / 2, y: -height / 2),
            endPoint: CGPoint(x: width / 2, y: height / 2)), lineWidth: max(0.4, unit * 0.002))

        // A very fine inner rim reads as thickness instead of another opaque leaf.
        let innerRim = Path(ellipseIn: bounds.insetBy(dx: unit * 0.005, dy: unit * 0.005))
        lens.stroke(innerRim, with: .color(mint.opacity(petal.front ? 0.22 : 0.10)),
                    lineWidth: max(0.3, unit * 0.0012))
        let glint = CGPoint(x: -width * 0.10, y: -height * 0.31)
        glow(context: &lens, at: glint, radius: unit * 0.034,
             colors: [pearl.opacity(petal.front ? 0.22 : 0.08), .clear])
    }

    private func drawPearl(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, unit: CGFloat) {
        glow(context: &context, at: center, radius: radius * 1.46,
             colors: [pearl.opacity(0.37), mint.opacity(0.16), .clear])
        let body = circle(center, radius: radius)
        let highlight = CGPoint(x: center.x - radius * 0.28, y: center.y - radius * 0.34)
        context.fill(body, with: .radialGradient(Gradient(stops: [
            .init(color: .white, location: 0),
            .init(color: pearl, location: 0.34),
            .init(color: Color(red: 0.87, green: 0.98, blue: 0.91), location: 0.68),
            .init(color: mint.opacity(0.93), location: 1)
        ]), center: highlight, startRadius: 0, endRadius: radius * 1.45))
        context.stroke(body, with: .color(deepTeal.opacity(0.25)), lineWidth: max(0.65, unit * 0.004))
        context.stroke(body, with: .linearGradient(Gradient(colors: [pearl, .white.opacity(0.6), mint.opacity(0.6)]),
            startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
            endPoint: CGPoint(x: center.x + radius, y: center.y + radius)), lineWidth: max(0.5, unit * 0.0025))
        glow(context: &context, at: CGPoint(x: center.x - radius * 0.22, y: center.y - radius * 0.24),
             radius: radius * 0.58, colors: [.white.opacity(0.64), .white.opacity(0.18), .clear])
        var glint = Path()
        glint.addArc(center: center, radius: radius * 0.94, startAngle: .degrees(207), endAngle: .degrees(264), clockwise: false)
        context.stroke(glint, with: .color(.white.opacity(0.68)),
                       style: StrokeStyle(lineWidth: max(0.65, unit * 0.004), lineCap: .round))
    }

    private func drawOrbit(context: inout GraphicsContext, center: CGPoint, unit: CGFloat, phase: Double) {
        let radius = unit * 0.382
        let ring = circle(center, radius: radius)
        context.stroke(ring, with: .color(deepTeal.opacity(0.4)), lineWidth: max(0.6, unit * 0.0032))
        context.stroke(ring, with: .linearGradient(Gradient(colors: [mint.opacity(0.84), seaGlass.opacity(0.35), mint.opacity(0.66)]),
            startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
            endPoint: CGPoint(x: center.x + radius, y: center.y + radius)), lineWidth: max(0.4, unit * 0.0017))
        var inner = Path()
        inner.addArc(center: center, radius: radius * 0.965, startAngle: .degrees(192), endAngle: .degrees(340), clockwise: false)
        context.stroke(inner, with: .color(mint.opacity(0.22)), lineWidth: max(0.35, unit * 0.0012))
        for index in 0..<12 {
            let angle = Double(index) * .pi / 6 + sin(phase) * 0.07
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let r = unit * (index.isMultiple(of: 3) ? 0.0045 : 0.0025)
            glow(context: &context, at: point, radius: r * 4, colors: [mint.opacity(0.38), .clear])
            context.fill(circle(point, radius: max(0.45, r)), with: .color(pearl.opacity(0.85)))
        }
    }

    private func drawPool(context: inout GraphicsContext, center: CGPoint, unit: CGFloat, strength: Double) {
        var pool = context
        pool.translateBy(x: center.x, y: center.y)
        pool.scaleBy(x: 1, y: 0.14)
        glow(context: &pool, at: .zero, radius: unit * 0.30,
             colors: [seaGlass.opacity(0.19 * strength), mint.opacity(0.06 * strength), .clear])
        for scale in [0.14, 0.225, 0.285] {
            pool.stroke(circle(.zero, radius: unit * scale), with: .color(seaGlass.opacity(0.13 * strength)),
                        lineWidth: unit * 0.0025)
        }
    }

    private func glow(context: inout GraphicsContext, at point: CGPoint, radius: CGFloat, colors: [Color]) {
        context.fill(circle(point, radius: radius), with: .radialGradient(Gradient(colors: colors),
            center: point, startRadius: 0, endRadius: radius))
    }

    private func circle(_ center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// Small repeatable presentation geometry. No randomness, private context,
/// network, preferences, growth counters, or model events enter this drawing.
enum LightFormGeometry {
    struct Petal: Equatable {
        let x: Double, y: Double, rotation: Double, scale: Double
        let front: Bool
    }
    struct Mote: Equatable {
        let x: Double, y: Double, radius: Double, opacity: Double
    }

    static func normalizedPhase(_ phase: Double) -> Double {
        guard phase.isFinite else { return 0 }
        let wrapped = phase.truncatingRemainder(dividingBy: .pi * 2)
        return wrapped < 0 ? wrapped + .pi * 2 : wrapped
    }

    static func petals(phase: Double) -> [Petal] {
        let phase = normalizedPhase(phase)
        return (0..<12).map { index in
            let front = index >= 6
            let turn = Double(index % 6) * .pi / 3 + (front ? 0 : .pi / 6)
            let tilt = sin(phase) * 0.016 * (front ? 1 : -1)
            let offset = front ? 0.089 : 0.079
            return Petal(x: sin(turn + tilt) * offset, y: -cos(turn + tilt) * offset,
                         rotation: turn + tilt, scale: front ? 1 : 1.03, front: front)
        }
    }

    static func motes(phase: Double) -> [Mote] {
        let phase = normalizedPhase(phase)
        return (0..<34).map { index in
            let angle = Double(index) * .pi * (3 - sqrt(5)) + sin(phase) * 0.022
            let distance = 0.344 + Double((index * 7) % 13) * 0.007
            let shimmer = 0.75 + 0.25 * sin(phase + Double(index) * 1.9)
            return Mote(x: cos(angle) * distance, y: sin(angle) * distance,
                        radius: index.isMultiple(of: 5) ? 0.0042 : 0.0022,
                        opacity: (index.isMultiple(of: 5) ? 0.9 : 0.62) * shimmer)
        }
    }
}
