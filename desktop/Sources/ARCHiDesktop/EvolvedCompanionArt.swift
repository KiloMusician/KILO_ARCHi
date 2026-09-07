import SwiftUI

/// Local, presentation-only studies. A different body never changes assistant state.
struct EvolvedCompanionArt: View {
    let family: EvolutionFamily
    let size: CGFloat
    let reduceMotion: Bool
    var recipe: CompanionAppearanceRecipe? = nil
    var naturalVariation: CompanionNaturalVariation? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var effectiveRecipe: CompanionAppearanceRecipe? { recipe?.family == family ? recipe : nil }
    private var effectiveNaturalVariation: CompanionNaturalVariation? {
        effectiveRecipe == nil && family == .lumen ? naturalVariation : nil
    }
    private var motionDisabled: Bool { reduceMotion || systemReduceMotion }

    var body: some View {
        Group {
            if motionDisabled {
                artwork(phase: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    artwork(phase: timeline.date.timeIntervalSinceReferenceDate * 0.8 * (effectiveRecipe?.motionSpeed ?? 1))
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let base = "ARCHi, \(familyName) later-form study, with a luminous pearl core"
        if let recipe = effectiveRecipe {
            return "\(base), individual appearance \(recipe.fingerprint.prefix(8)), \(recipe.role.title), \(recipe.helpStyle.title)"
        }
        return effectiveNaturalVariation == nil ? base : "\(base), individual variation"
    }

    private var familyName: String {
        switch family {
        case .lumen: "Lumen orbital light"
        case .fen: "Fen leaf sprite"
        case .frame: "Frame little mechanism"
        case .pop: "Pop playful creature"
        case .relic: "Relic lantern"
        case .veil: "Veil ribbon wisp"
        }
    }

    private func artwork(phase: Double) -> some View {
        Canvas { context, canvasSize in
            let unit = min(canvasSize.width, canvasSize.height)
            guard unit > 0 else { return }
            var drawing = context
            drawing.translateBy(x: (canvasSize.width - unit) / 2, y: (canvasSize.height - unit) / 2)
            drawing.scaleBy(x: unit, y: unit)
            let renderer = EvolutionDrawing(context: drawing, phase: phase, recipe: effectiveRecipe)
            renderer.ground()
            drawing.translateBy(x: 0, y: motionDisabled ? 0 : sin(phase) * 0.009)
            if let recipe = effectiveRecipe {
                // Change proportions around the center, never the app-owned frame.
                drawing.translateBy(x: 0.5, y: 0.5)
                drawing.scaleBy(x: recipe.horizontalScale, y: 1)
                drawing.translateBy(x: -0.5, y: -0.5)
            } else if let variation = effectiveNaturalVariation {
                drawing.translateBy(x: 0.5, y: 0.5)
                drawing.scaleBy(x: variation.horizontalScale, y: 1)
                drawing.translateBy(x: -0.5, y: -0.5)
                drawing.addFilter(.hueRotation(.degrees(variation.hueDegrees)))
            }
            EvolutionDrawing(context: drawing, phase: phase, recipe: effectiveRecipe,
                naturalVariation: effectiveNaturalVariation).draw(family)
        }
    }
}

private struct EvolutionDrawing {
    let context: GraphicsContext
    let phase: Double
    let recipe: CompanionAppearanceRecipe?
    var naturalVariation: CompanionNaturalVariation? = nil

    private var cyan: Color { accented(Color(red: 0.26, green: 0.65, blue: 0.73)) }
    private var green: Color { accented(Color(red: 0.40, green: 0.62, blue: 0.40)) }
    private var brass: Color { accented(Color(red: 0.65, green: 0.53, blue: 0.34)) }
    private var pink: Color { accented(Color(red: 0.82, green: 0.47, blue: 0.66)) }
    private var amber: Color { accented(Color(red: 0.79, green: 0.53, blue: 0.25)) }

    private func accented(_ base: Color) -> Color {
        guard let recipe else { return base }
        let accent = NSColor(calibratedHue: recipe.accentHue, saturation: 0.42, brightness: 0.78, alpha: 1)
        // Retain each family's recognizable palette; the individual accent is restrained.
        return Color(nsColor: NSColor(base).blended(withFraction: 0.28, of: accent) ?? NSColor(base))
    }

    func draw(_ family: EvolutionFamily) {
        switch family {
        case .lumen: lumen()
        case .fen: fen()
        case .frame: frame()
        case .pop: pop()
        case .relic: relic()
        case .veil: veil()
        }
    }

    func ground() {
        context.fill(oval(0.26, 0.86, 0.48, 0.065), with: .radialGradient(
            Gradient(colors: [ArchiPalette.violet.opacity(0.14), .clear]),
            center: pt(0.5, 0.892), startRadius: 0, endRadius: 0.25
        ))
    }

    private func lumen() {
        halo(at: pt(0.5, 0.46), radius: 0.32, tint: cyan)
        let tilt = sin(phase * 0.55) * 0.035
        for angle in [-0.34, 0.86, 1.88] {
            var orbit = context
            orbit.translateBy(x: 0.5, y: 0.46)
            orbit.rotate(by: .radians(angle + tilt))
            let ring = oval(-0.355, -0.145, 0.71, 0.29)
            orbit.fill(ring, with: .color(cyan.opacity(0.025)))
            orbit.stroke(ring, with: .color(cyan.opacity(0.46)), lineWidth: 0.009)
            orbit.stroke(oval(-0.335, -0.123, 0.67, 0.246), with: .color(.white.opacity(0.75)), lineWidth: 0.004)
        }
        core(at: pt(0.5, 0.46), radius: 0.125, tint: cyan)
        stroke(oval(0.334, 0.294, 0.332, 0.332), cyan.opacity(0.42), width: 0.006)
        for (x, y, radius) in [(0.20, 0.29, 0.030), (0.79, 0.56, 0.025), (0.58, 0.17, 0.022), (0.40, 0.76, 0.019)] {
            pearl(at: pt(x, y), radius: radius, tint: cyan)
        }
        sparkle(at: pt(0.79, 0.27), radius: 0.025, tint: cyan)
        sparkle(at: pt(0.25, 0.66), radius: 0.019, tint: cyan)
        stroke(oval(0.37, 0.818, 0.26, 0.032), cyan.opacity(0.35), width: 0.006)
    }

    private func fen() {
        let branch = Path { p in
            p.move(to: pt(0.5, 0.49))
            p.addCurve(to: pt(0.32, 0.13), control1: pt(0.40, 0.37), control2: pt(0.35, 0.23))
            p.move(to: pt(0.46, 0.38))
            p.addQuadCurve(to: pt(0.22, 0.23), control: pt(0.30, 0.35))
        }
        stroke(branch, green.opacity(0.8), width: 0.014)
        stroke(mirror(branch), green.opacity(0.8), width: 0.014)
        for leaf in [
            leaf(from: pt(0.34, 0.24), tip: pt(0.23, 0.095), bend: -0.07),
            leaf(from: pt(0.36, 0.28), tip: pt(0.43, 0.12), bend: 0.065),
            leaf(from: pt(0.29, 0.30), tip: pt(0.15, 0.215), bend: -0.065)
        ] {
            shell(leaf, tint: green)
            shell(mirror(leaf), tint: green)
        }
        let limbs = Path { p in
            p.move(to: pt(0.40, 0.59))
            p.addQuadCurve(to: pt(0.24, 0.66), control: pt(0.28, 0.55))
            p.move(to: pt(0.43, 0.70))
            p.addCurve(to: pt(0.34, 0.83), control1: pt(0.45, 0.80), control2: pt(0.40, 0.82))
        }
        stroke(limbs, green.opacity(0.65), width: 0.027)
        stroke(mirror(limbs), green.opacity(0.65), width: 0.027)
        shell(leaf(from: pt(0.30, 0.63), tip: pt(0.17, 0.50), bend: -0.085), tint: green)
        shell(leaf(from: pt(0.70, 0.63), tip: pt(0.83, 0.50), bend: 0.085), tint: green)
        let seed = Path { p in
            p.move(to: pt(0.50, 0.29))
            p.addCurve(to: pt(0.68, 0.58), control1: pt(0.66, 0.37), control2: pt(0.71, 0.44))
            p.addCurve(to: pt(0.50, 0.79), control1: pt(0.68, 0.70), control2: pt(0.57, 0.76))
            p.addCurve(to: pt(0.32, 0.58), control1: pt(0.42, 0.77), control2: pt(0.32, 0.69))
            p.addCurve(to: pt(0.50, 0.29), control1: pt(0.28, 0.45), control2: pt(0.36, 0.37))
            p.closeSubpath()
        }
        shell(seed, tint: green)
        stroke(curve(from: pt(0.50, 0.33), to: pt(0.50, 0.75), control: pt(0.44, 0.56)), .white.opacity(0.80), width: 0.009)
        core(at: pt(0.50, 0.58), radius: 0.083, tint: green)
        eyes(at: pt(0.5, 0.445), separation: 0.090, tint: green)
        pearl(at: pt(0.24, 0.40), radius: 0.014, tint: green)
        sparkle(at: pt(0.76, 0.36), radius: 0.024, tint: green)
    }

    private func frame() {
        let limb = Path { p in
            p.move(to: pt(0.35, 0.45))
            p.addLine(to: pt(0.22, 0.52))
            p.addLine(to: pt(0.18, 0.69))
            p.move(to: pt(0.43, 0.66))
            p.addLine(to: pt(0.39, 0.80))
            p.addLine(to: pt(0.30, 0.83))
        }
        stroke(limb, brass.opacity(0.72), width: 0.054)
        stroke(mirror(limb), brass.opacity(0.72), width: 0.054)
        stroke(limb, .white.opacity(0.85), width: 0.017)
        stroke(mirror(limb), .white.opacity(0.85), width: 0.017)
        for (x, y) in [(0.22, 0.52), (0.78, 0.52), (0.39, 0.79), (0.61, 0.79)] {
            pearl(at: pt(x, y), radius: 0.040, tint: brass)
            fill(oval(x - 0.012, y - 0.012, 0.024, 0.024), brass.opacity(0.85))
        }
        let chassis = polygon([(0.37, 0.37), (0.63, 0.37), (0.71, 0.49), (0.64, 0.70), (0.36, 0.70), (0.29, 0.49)])
        shell(chassis, tint: brass)
        stroke(polygon([(0.40, 0.41), (0.60, 0.41), (0.66, 0.50), (0.60, 0.65), (0.40, 0.65), (0.34, 0.50)]), brass.opacity(0.55), width: 0.009)
        shell(Path(roundedRect: CGRect(x: 0.37, y: 0.20, width: 0.26, height: 0.18), cornerRadius: 0.045), tint: brass)
        fill(Path(roundedRect: CGRect(x: 0.407, y: 0.245, width: 0.186, height: 0.079), cornerRadius: 0.027), ArchiPalette.ink.opacity(0.78))
        eyes(at: pt(0.5, 0.282), separation: 0.090, tint: .white)
        stroke(line([(0.5, 0.20), (0.5, 0.135), (0.56, 0.11)]), brass.opacity(0.8), width: 0.012)
        pearl(at: pt(0.56, 0.11), radius: 0.021, tint: brass)
        core(at: pt(0.50, 0.53), radius: 0.091, tint: brass)
        for x in [0.375, 0.625] {
            fill(oval(x - 0.012, 0.42, 0.024, 0.024), brass.opacity(0.8))
            fill(oval(x - 0.012, 0.63, 0.024, 0.024), brass.opacity(0.8))
        }
        stroke(line([(0.17, 0.69), (0.15, 0.72), (0.19, 0.74)]), brass.opacity(0.8), width: 0.017)
        stroke(line([(0.83, 0.69), (0.85, 0.72), (0.81, 0.74)]), brass.opacity(0.8), width: 0.017)
    }

    private func pop() {
        let ear = leaf(from: pt(0.38, 0.33), tip: pt(0.26, 0.10), bend: -0.115)
        shell(ear, tint: pink)
        shell(mirror(ear), tint: pink)
        stroke(curve(from: pt(0.37, 0.29), to: pt(0.28, 0.145), control: pt(0.29, 0.25)), pink.opacity(0.45), width: 0.019)
        stroke(mirror(curve(from: pt(0.37, 0.29), to: pt(0.28, 0.145), control: pt(0.29, 0.25))), pink.opacity(0.45), width: 0.019)
        shell(oval(0.34, 0.70, 0.13, 0.145), tint: pink)
        shell(oval(0.53, 0.70, 0.13, 0.145), tint: pink)
        shell(leaf(from: pt(0.40, 0.58), tip: pt(0.24, 0.68), bend: -0.10), tint: pink)
        shell(leaf(from: pt(0.60, 0.58), tip: pt(0.76, 0.68), bend: 0.10), tint: pink)
        shell(oval(0.35, 0.51, 0.30, 0.28), tint: pink)
        shell(oval(0.26, 0.265, 0.48, 0.34), tint: pink)
        fill(oval(0.315, 0.31, 0.12, 0.065), .white.opacity(0.70))
        eyes(at: pt(0.5, 0.43), separation: 0.15, tint: ArchiPalette.ink)
        fill(oval(0.325, 0.458, 0.052, 0.027), pink.opacity(0.35))
        fill(oval(0.623, 0.458, 0.052, 0.027), pink.opacity(0.35))
        stroke(curve(from: pt(0.46, 0.489), to: pt(0.54, 0.489), control: pt(0.50, 0.529)), ArchiPalette.ink.opacity(0.65), width: 0.010)
        core(at: pt(0.50, 0.655), radius: 0.070, tint: pink)
        stroke(oval(0.795, 0.39, 0.045, 0.045), pink.opacity(0.5), width: 0.007)
        pearl(at: pt(0.19, 0.53), radius: 0.017, tint: pink)
        sparkle(at: pt(0.79, 0.22), radius: 0.027, tint: pink)
    }

    private func relic() {
        halo(at: pt(0.5, 0.55), radius: 0.30, tint: amber)
        stroke(oval(0.435, 0.105, 0.13, 0.155), amber.opacity(0.85), width: 0.023)
        stroke(oval(0.444, 0.108, 0.112, 0.139), .white.opacity(0.76), width: 0.006)
        let glass = polygon([(0.31, 0.36), (0.69, 0.36), (0.66, 0.73), (0.34, 0.73)])
        shell(glass, tint: amber)
        fill(oval(0.372, 0.419, 0.256, 0.256), .white.opacity(0.26))
        core(at: pt(0.5, 0.55), radius: 0.105, tint: amber)
        let ribs = Path { p in
            p.move(to: pt(0.40, 0.37))
            p.addCurve(to: pt(0.40, 0.735), control1: pt(0.34, 0.48), control2: pt(0.37, 0.66))
            p.move(to: pt(0.60, 0.37))
            p.addCurve(to: pt(0.60, 0.735), control1: pt(0.66, 0.48), control2: pt(0.63, 0.66))
        }
        stroke(ribs, amber.opacity(0.60), width: 0.014)
        stroke(line([(0.31, 0.36), (0.34, 0.73), (0.66, 0.73), (0.69, 0.36)]), amber.opacity(0.85), width: 0.016)
        let roof = Path { p in
            p.move(to: pt(0.28, 0.355))
            p.addQuadCurve(to: pt(0.455, 0.235), control: pt(0.34, 0.25))
            p.addLine(to: pt(0.545, 0.235))
            p.addQuadCurve(to: pt(0.72, 0.355), control: pt(0.66, 0.25))
            p.closeSubpath()
        }
        shell(roof, tint: amber)
        stroke(line([(0.28, 0.36), (0.72, 0.36)]), amber.opacity(0.9), width: 0.025)
        shell(polygon([(0.34, 0.73), (0.66, 0.73), (0.72, 0.795), (0.28, 0.795)]), tint: amber)
        stroke(line([(0.28, 0.805), (0.72, 0.805)]), amber.opacity(0.78), width: 0.019)
        for x in [0.34, 0.66] {
            pearl(at: pt(x, 0.39), radius: 0.015, tint: amber)
            pearl(at: pt(x, 0.705), radius: 0.015, tint: amber)
        }
        stroke(curve(from: pt(0.70, 0.40), to: pt(0.77, 0.56), control: pt(0.83, 0.37)), amber.opacity(0.7), width: 0.012)
        pearl(at: pt(0.77, 0.575), radius: 0.022, tint: amber)
        sparkle(at: pt(0.23, 0.49), radius: 0.023, tint: amber)
        sparkle(at: pt(0.75, 0.23), radius: 0.017, tint: amber)
    }

    private func veil() {
        let violet = accented(ArchiPalette.violet)
        let tail = Path { p in
            p.move(to: pt(0.44, 0.50))
            p.addCurve(to: pt(0.51, 0.76), control1: pt(0.63, 0.58), control2: pt(0.72, 0.68))
            p.addCurve(to: pt(0.32, 0.875), control1: pt(0.37, 0.77), control2: pt(0.31, 0.80))
            p.addCurve(to: pt(0.64, 0.76), control1: pt(0.52, 0.84), control2: pt(0.77, 0.86))
            p.addCurve(to: pt(0.56, 0.50), control1: pt(0.86, 0.61), control2: pt(0.57, 0.62))
            p.closeSubpath()
        }
        shell(tail, tint: violet)
        let wing = Path { p in
            p.move(to: pt(0.50, 0.34))
            p.addCurve(to: pt(0.15, 0.23), control1: pt(0.32, 0.22), control2: pt(0.27, 0.08))
            p.addCurve(to: pt(0.08, 0.55), control1: pt(0.08, 0.31), control2: pt(0.18, 0.43))
            p.addCurve(to: pt(0.39, 0.61), control1: pt(0.22, 0.52), control2: pt(0.24, 0.69))
            p.addCurve(to: pt(0.50, 0.68), control1: pt(0.44, 0.62), control2: pt(0.47, 0.66))
            p.addCurve(to: pt(0.61, 0.61), control1: pt(0.53, 0.66), control2: pt(0.56, 0.62))
            p.addCurve(to: pt(0.92, 0.55), control1: pt(0.76, 0.69), control2: pt(0.78, 0.52))
            p.addCurve(to: pt(0.85, 0.23), control1: pt(0.82, 0.43), control2: pt(0.92, 0.31))
            p.addCurve(to: pt(0.50, 0.34), control1: pt(0.73, 0.08), control2: pt(0.68, 0.22))
            p.closeSubpath()
        }
        shell(wing, tint: violet)
        let vein = Path { p in
            p.move(to: pt(0.48, 0.47))
            p.addCurve(to: pt(0.19, 0.27), control1: pt(0.25, 0.47), control2: pt(0.30, 0.27))
            p.move(to: pt(0.46, 0.51))
            p.addQuadCurve(to: pt(0.15, 0.51), control: pt(0.28, 0.60))
        }
        stroke(vein, .white.opacity(0.85), width: 0.011)
        stroke(mirror(vein), .white.opacity(0.85), width: 0.011)
        stroke(curve(from: pt(0.51, 0.66), to: pt(0.39, 0.842), control: pt(0.76, 0.76)), .white.opacity(0.73), width: 0.009)
        core(at: pt(0.5, 0.49), radius: 0.086, tint: violet)
        sparkle(at: pt(0.39, 0.19), radius: 0.020, tint: violet)
        pearl(at: pt(0.77, 0.69), radius: 0.018, tint: violet)
    }

    // Coordinates stay inside a unit square so every body fits the same desktop bounds.
    private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private func oval(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Path {
        Path(ellipseIn: CGRect(x: x, y: y, width: width, height: height))
    }

    private func fill(_ path: Path, _ color: Color) {
        context.fill(path, with: .color(color))
    }

    private func stroke(_ path: Path, _ color: Color, width: CGFloat) {
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func shell(_ path: Path, tint: Color) {
        context.fill(path, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.96), tint.opacity(0.18), tint.opacity(0.48)]),
            startPoint: pt(0.28, 0.20), endPoint: pt(0.73, 0.81)
        ))
        stroke(path, tint.opacity(0.62), width: 0.010)
        // Thin inner light is provided by each form's veins, seams, or rim details.
    }

    private func halo(at center: CGPoint, radius: Double, tint: Color) {
        context.fill(oval(center.x - radius, center.y - radius, radius * 2, radius * 2), with: .radialGradient(
            Gradient(colors: [tint.opacity(0.25), tint.opacity(0.07), .clear]),
            center: center, startRadius: 0, endRadius: radius
        ))
    }

    private func core(at center: CGPoint, radius: Double, tint: Color) {
        halo(at: center, radius: radius * 2.1, tint: tint)
        pearl(at: center, radius: radius, tint: tint)
        stroke(oval(center.x - radius * 1.24, center.y - radius * 1.24, radius * 2.48, radius * 2.48), tint.opacity(0.44), width: 0.006)
        if let recipe {
            for index in 0..<recipe.markingCount {
                let angle = recipe.markingRotation + Double(index) * 2 * .pi / Double(recipe.markingCount)
                let point = pt(center.x + cos(angle) * radius * 1.48, center.y + sin(angle) * radius * 1.48)
                pearl(at: point, radius: 0.006 + Double(index % 2) * 0.002, tint: tint)
            }
        } else if let variation = naturalVariation {
            for index in 0..<variation.markingCount {
                let angle = variation.markingRotation + Double(index) * 2.1
                let x = center.x - radius * 0.42 + Double(index) * 0.013 + cos(angle) * 0.005
                let y = center.y + radius * 0.45 + sin(angle) * 0.009 + Double(index % 2) * 0.014
                let dotRadius = 0.0055 + Double(index % 2) * 0.001
                fill(oval(x - dotRadius, y - dotRadius, dotRadius * 2, dotRadius * 2), tint.opacity(0.52))
            }
        }
    }

    private func pearl(at center: CGPoint, radius: Double, tint: Color) {
        context.fill(oval(center.x - radius, center.y - radius, radius * 2, radius * 2), with: .radialGradient(
            Gradient(colors: [.white, Color(red: 1, green: 0.98, blue: 0.91), tint.opacity(0.55)]),
            center: pt(center.x - radius * 0.28, center.y - radius * 0.32),
            startRadius: 0, endRadius: radius * 1.65
        ))
        stroke(oval(center.x - radius, center.y - radius, radius * 2, radius * 2), .white.opacity(0.9), width: 0.007)
        fill(oval(center.x - radius * 0.47, center.y - radius * 0.50, radius * 0.51, radius * 0.30), .white.opacity(0.87))
    }

    private func eyes(at center: CGPoint, separation: Double, tint: Color) {
        for direction in [-1.0, 1.0] {
            fill(oval(center.x + direction * separation / 2 - 0.012, center.y - 0.020, 0.024, 0.040), tint.opacity(0.9))
        }
    }

    private func sparkle(at center: CGPoint, radius: Double, tint: Color) {
        let star = polygon([
            (center.x, center.y - radius), (center.x + radius * 0.25, center.y - radius * 0.25),
            (center.x + radius, center.y), (center.x + radius * 0.25, center.y + radius * 0.25),
            (center.x, center.y + radius), (center.x - radius * 0.25, center.y + radius * 0.25),
            (center.x - radius, center.y), (center.x - radius * 0.25, center.y - radius * 0.25)
        ])
        fill(star, tint.opacity(0.65))
    }

    private func line(_ points: [(Double, Double)]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: pt(first.0, first.1))
            for point in points.dropFirst() { path.addLine(to: pt(point.0, point.1)) }
        }
    }

    private func polygon(_ points: [(Double, Double)]) -> Path {
        var path = line(points)
        path.closeSubpath()
        return path
    }

    private func curve(from start: CGPoint, to end: CGPoint, control: CGPoint) -> Path {
        Path { path in
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
        }
    }

    private func leaf(from base: CGPoint, tip: CGPoint, bend: Double) -> Path {
        Path { path in
            path.move(to: base)
            path.addQuadCurve(to: tip, control: pt(tip.x + bend, base.y))
            path.addQuadCurve(to: base, control: pt(base.x - bend, tip.y))
            path.closeSubpath()
        }
    }

    private func mirror(_ path: Path) -> Path {
        path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0))
    }
}
