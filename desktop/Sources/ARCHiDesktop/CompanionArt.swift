import SwiftUI

enum ArchiPalette {
    static let violet = Color(red: 0.49, green: 0.40, blue: 0.74)
    static let lavender = Color(red: 0.80, green: 0.76, blue: 0.96)
    static let lilac = Color(red: 0.91, green: 0.87, blue: 0.98)
    static let peach = Color(red: 0.98, green: 0.79, blue: 0.68)
    static let ink = Color(red: 0.22, green: 0.19, blue: 0.34)
}

/// The desktop body is entirely local drawing. It owns no input or assistant state.
struct CompanionArt: View {
    let form: CompanionForm
    let size: CGFloat
    let reduceMotion: Bool
    var naturalVariation: CompanionNaturalVariation? = nil

    private var effectiveNaturalVariation: CompanionNaturalVariation? {
        form == .companion ? naturalVariation : nil
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 1.5
            let float = reduceMotion ? 0 : sin(phase) * size * 0.018
            ZStack {
                Ellipse()
                    .fill(ArchiPalette.violet.opacity(0.13))
                    .frame(width: size * 0.56, height: size * 0.09)
                    .blur(radius: size * 0.04)
                    .offset(y: size * 0.39)
                if let variation = effectiveNaturalVariation {
                    formBody
                        .frame(width: size * 0.88, height: size * 0.88)
                        .modifier(CompanionNaturalFinish(variation: variation))
                        .offset(y: float - size * 0.025)
                } else {
                    formBody
                        .frame(width: size * 0.88, height: size * 0.88)
                        .offset(y: float - size * 0.025)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(effectiveNaturalVariation == nil
            ? "ARCHi, \(form.rawValue) form"
            : "ARCHi, \(form.rawValue) form, individual variation")
    }

    @ViewBuilder private var formBody: some View {
        switch form {
        case .companion: softCompanion
        case .light: guideLight
        case .ribbon: ribbon
        case .ink: ink
        case .pixel: pixel
        }
    }

    private var softCompanion: some View {
        ZStack {
            CompanionSilhouette()
                .fill(LinearGradient(colors: [.white, ArchiPalette.lilac, ArchiPalette.lavender], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: ArchiPalette.violet.opacity(0.25), radius: size * 0.04, x: 0, y: size * 0.035)
            CompanionSilhouette()
                .stroke(.white.opacity(0.82), lineWidth: max(0.8, size * 0.009))
            Ellipse().fill(.white.opacity(0.76))
                .frame(width: size * 0.21, height: size * 0.105)
                .rotationEffect(.degrees(-28))
                .offset(x: -size * 0.18, y: -size * 0.22)
                .blur(radius: size * 0.026)
            face
                .offset(y: size * 0.045)
        }
    }

    private var guideLight: some View {
        ZStack {
            Circle().fill(ArchiPalette.lavender.opacity(0.20)).blur(radius: size * 0.05)
            Circle().fill(RadialGradient(colors: [.white, ArchiPalette.lilac, ArchiPalette.lavender.opacity(0.62), .clear], center: .init(x: 0.38, y: 0.32), startRadius: 0, endRadius: size * 0.40))
                .padding(size * 0.05)
            Circle().stroke(.white.opacity(0.8), lineWidth: 1).padding(size * 0.13)
            face.scaleEffect(0.82)
        }
    }

    private var ribbon: some View {
        ZStack {
            RibbonShape().stroke(ArchiPalette.violet.opacity(0.18), style: StrokeStyle(lineWidth: size * 0.17, lineCap: .round))
                .blur(radius: size * 0.035).offset(y: size * 0.025)
            RibbonShape().stroke(LinearGradient(colors: [ArchiPalette.peach, ArchiPalette.lilac, ArchiPalette.violet, ArchiPalette.lavender], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: size * 0.125, lineCap: .round))
            RibbonShape().stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
                .offset(x: -size * 0.024)
            face.scaleEffect(0.72).offset(y: -size * 0.12)
        }
    }

    private var ink: some View {
        ZStack {
            InkShape().fill(LinearGradient(colors: [ArchiPalette.ink, ArchiPalette.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: ArchiPalette.ink.opacity(0.18), radius: size * 0.035, y: size * 0.03)
            HStack(spacing: size * 0.10) {
                Capsule().fill(ArchiPalette.lilac).frame(width: size * 0.042, height: size * 0.092)
                Capsule().fill(ArchiPalette.lilac).frame(width: size * 0.042, height: size * 0.092)
            }.offset(y: -size * 0.025)
            Capsule().fill(.white.opacity(0.22)).frame(width: size * 0.12, height: size * 0.024)
                .rotationEffect(.degrees(-48)).offset(x: -size * 0.20, y: -size * 0.18)
        }
    }

    private var pixel: some View {
        Canvas { context, rect in
            let cells = [
                "0001111000", "0011111100", "0111111110", "1111111111",
                "1112112111", "1112112111", "1111111111", "0111221110",
                "0011111100", "0011001100"
            ]
            let cell = min(rect.width, rect.height) / 12
            let origin = CGPoint(x: (rect.width - cell * 10) / 2, y: (rect.height - cell * 10) / 2)
            for (y, row) in cells.enumerated() {
                for (x, value) in row.enumerated() where value != "0" {
                    let box = CGRect(x: origin.x + CGFloat(x) * cell, y: origin.y + CGFloat(y) * cell, width: cell + 0.2, height: cell + 0.2)
                    let color = value == "2" ? ArchiPalette.ink : (y < 3 ? ArchiPalette.lilac : ArchiPalette.lavender)
                    context.fill(Path(box), with: .color(color))
                }
            }
        }
        .shadow(color: ArchiPalette.violet.opacity(0.20), radius: 0, x: size * 0.025, y: size * 0.035)
    }

    private var face: some View {
        VStack(spacing: size * 0.055) {
            HStack(spacing: size * 0.13) {
                eye
                eye
            }
            SmileShape().stroke(ArchiPalette.ink.opacity(0.86), style: StrokeStyle(lineWidth: max(1, size * 0.012), lineCap: .round))
                .frame(width: size * 0.085, height: size * 0.032)
        }
    }

    private var eye: some View {
        Capsule().fill(ArchiPalette.ink)
            .frame(width: size * 0.037, height: size * 0.077)
    }
}

private struct CompanionSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0.50, y: 0.08))
            path.addCurve(to: CGPoint(x: 0.88, y: 0.60), control1: CGPoint(x: 0.80, y: 0.06), control2: CGPoint(x: 0.91, y: 0.30))
            path.addCurve(to: CGPoint(x: 0.72, y: 0.83), control1: CGPoint(x: 0.88, y: 0.77), control2: CGPoint(x: 0.82, y: 0.88))
            path.addCurve(to: CGPoint(x: 0.52, y: 0.82), control1: CGPoint(x: 0.62, y: 0.79), control2: CGPoint(x: 0.62, y: 0.78))
            path.addCurve(to: CGPoint(x: 0.27, y: 0.87), control1: CGPoint(x: 0.36, y: 0.90), control2: CGPoint(x: 0.28, y: 0.96))
            path.addCurve(to: CGPoint(x: 0.13, y: 0.56), control1: CGPoint(x: 0.14, y: 0.84), control2: CGPoint(x: 0.09, y: 0.74))
            path.addCurve(to: CGPoint(x: 0.50, y: 0.08), control1: CGPoint(x: 0.15, y: 0.26), control2: CGPoint(x: 0.23, y: 0.09))
            path.closeSubpath()
        }.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
    }
}

private struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0.72, y: 0.85))
            path.addCurve(to: CGPoint(x: 0.32, y: 0.62), control1: CGPoint(x: 0.44, y: 0.88), control2: CGPoint(x: 0.34, y: 0.73))
            path.addCurve(to: CGPoint(x: 0.56, y: 0.18), control1: CGPoint(x: 0.17, y: 0.28), control2: CGPoint(x: 0.32, y: 0.04))
            path.addCurve(to: CGPoint(x: 0.44, y: 0.63), control1: CGPoint(x: 0.85, y: 0.36), control2: CGPoint(x: 0.80, y: 0.63))
            path.addCurve(to: CGPoint(x: 0.25, y: 0.88), control1: CGPoint(x: 0.20, y: 0.62), control2: CGPoint(x: 0.16, y: 0.73))
        }.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
    }
}

private struct InkShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0.65, y: 0.07))
            path.addCurve(to: CGPoint(x: 0.80, y: 0.69), control1: CGPoint(x: 0.62, y: 0.36), control2: CGPoint(x: 0.91, y: 0.37))
            path.addCurve(to: CGPoint(x: 0.56, y: 0.83), control1: CGPoint(x: 0.75, y: 0.84), control2: CGPoint(x: 0.66, y: 0.85))
            path.addCurve(to: CGPoint(x: 0.15, y: 0.80), control1: CGPoint(x: 0.38, y: 0.79), control2: CGPoint(x: 0.20, y: 0.92))
            path.addCurve(to: CGPoint(x: 0.65, y: 0.07), control1: CGPoint(x: 0.08, y: 0.52), control2: CGPoint(x: 0.32, y: 0.20))
            path.closeSubpath()
        }.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: 0), control: CGPoint(x: rect.midX, y: rect.height * 1.5))
        }
    }
}
