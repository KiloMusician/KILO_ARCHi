import CryptoKit
import SwiftUI

@MainActor
extension CompanionStore {
    /// Re-read at click time: a previously displayed button cannot admit stale work.
    func evolutionFeedbackReceipt(provider: AssistantProvider, requestID: String) -> AssistantLaneReceipt? {
        guard !isShuttingDown, sourceName != nil, !sharedText.isEmpty,
              let lane = compareResults[provider], lane.state == .complete,
              !lane.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let receipt = lane.receipt, receipt.state == .complete,
              receipt.provider == provider, receipt.requestID == requestID,
              isCurrent(receipt.context, requireVisible: false) else { return nil }
        let currentDigest = SHA256.hash(data: Data(sharedText.utf8)).map { String(format: "%02x", $0) }.joined()
        guard receipt.sourceDigest == currentDigest else { return nil }
        return receipt
    }

    @discardableResult
    func markReplyUsefulForEvolution(provider: AssistantProvider, requestID: String) -> Bool {
        guard let receipt = evolutionFeedbackReceipt(provider: provider, requestID: requestID),
              let digest = receipt.sourceDigest else { return false }
        return evolution.markUseful(receipt: receipt, sourceDigest: digest)
    }

    func chooseStartingForm(_ form: CompanionForm) {
        evolution.returnToStarter()
        preferences.form = form
    }

    func returnEvolutionToStarter() {
        evolution.returnToStarter()
        preferences.form = evolution.origin
    }
}

/// Both art paths fit the same app-owned frame; a new body never moves its window.
struct CompanionPresenceArt: View {
    let form: CompanionForm
    let family: EvolutionFamily?
    let size: CGFloat
    let reduceMotion: Bool
    var treatment: CompanionVisualTreatment = .original
    var recipe: CompanionAppearanceRecipe? = nil
    var naturalVariation: CompanionNaturalVariation? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var effectiveRecipe: CompanionAppearanceRecipe? {
        guard let family, recipe?.family == family else { return nil }
        return recipe
    }

    private var effectiveNaturalVariation: CompanionNaturalVariation? {
        CompanionVisualAsset.effectiveNaturalVariation(form: form, family: family, recipe: recipe,
            naturalVariation: naturalVariation)
    }

    /// Habitat consumes this same drawing instead of maintaining a second body.
    @MainActor
    static func png(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment = .original,
                    recipe: CompanionAppearanceRecipe? = nil, naturalVariation: CompanionNaturalVariation? = nil) -> Data? {
        let renderer = ImageRenderer(content: CompanionPresenceArt(form: form, family: family, size: 256, reduceMotion: true,
            treatment: treatment, recipe: recipe, naturalVariation: naturalVariation))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    var body: some View {
        Group {
            if let image = CompanionVisualAsset.resolvedImage(form: form, family: family, treatment: treatment) {
                TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || systemReduceMotion)) { context in
                    let phase = reduceMotion || systemReduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                    if let recipe = effectiveRecipe {
                        personalizedImage(image, recipe: recipe, phase: phase)
                    } else if let variation = effectiveNaturalVariation {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .frame(width: size, height: size)
                            .modifier(CompanionNaturalFinish(variation: variation))
                            .offset(y: sin(phase * 1.2) * size * 0.018)
                            .accessibilityLabel("ARCHi, " + CompanionVisualAsset.label(form: form, family: family,
                                treatment: treatment, naturalVariation: variation))
                    } else {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .frame(width: size, height: size)
                            .offset(y: sin(phase * 1.2) * size * 0.018)
                            .accessibilityLabel("ARCHi, \(family?.title ?? form.rawValue) form, Pearl study finish")
                    }
                }
            } else if let family {
                EvolvedCompanionArt(family: family, size: size, reduceMotion: reduceMotion || systemReduceMotion,
                    recipe: effectiveRecipe, naturalVariation: effectiveNaturalVariation)
            } else {
                CompanionArt(form: form, size: size, reduceMotion: reduceMotion || systemReduceMotion,
                    naturalVariation: effectiveNaturalVariation)
            }
        }.frame(width: size, height: size)
    }

    private func personalizedImage(_ image: NSImage, recipe: CompanionAppearanceRecipe, phase: Double) -> some View {
        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            // The approved Lumen artwork remains the body. This restrained finish
            // and small core marks are deterministic drawing, never a new raster asset.
            .hueRotation(.degrees((recipe.accentHue - 0.5) * 24))
            .overlay {
                CompanionRecipeMarkings(recipe: recipe, center: CGPoint(x: 0.5, y: 0.594), radius: 0.061)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .scaleEffect(x: recipe.horizontalScale, y: 1)
            .offset(y: sin(phase * 1.2 * recipe.motionSpeed) * size * 0.018)
            .accessibilityLabel("ARCHi, \(CompanionVisualAsset.label(form: form, family: family, treatment: treatment, recipe: recipe))")
    }
}

/// Restrained individual variation on existing authored geometry. No role, help
/// preference, or growth milestone participates; motion retains the form's rhythm.
struct CompanionNaturalFinish: ViewModifier {
    let variation: CompanionNaturalVariation

    func body(content: Content) -> some View {
        content
            .hueRotation(.degrees(variation.hueDegrees))
            .overlay {
                Canvas { context, size in
                    let unit = min(size.width, size.height)
                    for index in 0..<variation.markingCount {
                        let angle = variation.markingRotation + Double(index) * 2.1
                        let x = (0.40 + Double(index) * 0.013 + cos(angle) * 0.005) * unit
                        let y = (0.66 + sin(angle) * 0.009 + Double(index % 2) * 0.014) * unit
                        let radius = unit * (0.0055 + Double(index % 2) * 0.001)
                        let dot = Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                            width: radius * 2, height: radius * 2))
                        context.fill(dot, with: .color(ArchiPalette.violet.opacity(0.40)))
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .scaleEffect(x: variation.horizontalScale, y: 1)
    }
}

/// Small body-local details for the reviewed image-based form.
/// Coordinates are normalized to the existing frame; marks never establish identity.
private struct CompanionRecipeMarkings: View {
    let recipe: CompanionAppearanceRecipe
    let center: CGPoint
    let radius: Double

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height)
            let tint = Color(hue: recipe.accentHue, saturation: 0.36, brightness: 0.76)
            for index in 0..<recipe.markingCount {
                let angle = recipe.markingRotation + Double(index) * 2 * .pi / Double(recipe.markingCount)
                let point = CGPoint(x: (center.x + cos(angle) * radius) * unit,
                                    y: (center.y + sin(angle) * radius) * unit)
                let dot = Path(ellipseIn: CGRect(x: point.x - unit * 0.0055, y: point.y - unit * 0.0055,
                                                width: unit * 0.011, height: unit * 0.011))
                context.fill(dot, with: .color(tint.opacity(0.82)))
                context.stroke(dot, with: .color(.white.opacity(0.75)), lineWidth: unit * 0.0025)
            }
        }
    }
}

@MainActor
struct EvolutionReplyFeedback: View {
    @ObservedObject var store: CompanionStore
    let provider: AssistantProvider

    var body: some View {
        if let id = store.compareResults[provider]?.receipt?.requestID,
           store.evolutionFeedbackReceipt(provider: provider, requestID: id) != nil {
            let recorded = store.evolution.usefulReceipts.contains { $0.requestID.uuidString == id }
            Button {
                store.markReplyUsefulForEvolution(provider: provider, requestID: id)
            } label: {
                Label(recorded ? "Added to evolution" : "This helped my work", systemImage: recorded ? "checkmark.circle" : "sparkle")
            }
            .buttonStyle(.borderless).font(.system(size: 11))
            .disabled(recorded)
            .accessibilityIdentifier("evolution-useful-\(provider.rawValue)")
            .help("Add your usefulness feedback to Evolution. Retains only a request ID and source digest; no document or reply text.")
        }
    }
}
