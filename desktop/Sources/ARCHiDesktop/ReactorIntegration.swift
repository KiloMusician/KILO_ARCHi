import AppKit
import SwiftUI

@MainActor
extension CompanionStore {
    func refreshReactorReference(family: EvolutionFamily? = nil, usesExplicitFamily: Bool = false) {
        let selectedFamily = usesExplicitFamily ? family : evolution.activeFamily
        let recipe = evolution.activeAppearanceRecipe
        let id = CompanionVisualAsset.appearanceID(form: preferences.form, family: selectedFamily, treatment: preferences.visualTreatment, recipe: recipe, naturalVariation: evolution.naturalVariation)
        let bytes = reactor.appearanceID == id ? reactor.referencePNG : CompanionPresenceArt.png(
            form: preferences.form, family: selectedFamily, treatment: preferences.visualTreatment, recipe: recipe, naturalVariation: evolution.naturalVariation)
        reactor.updateReference(id: id,
            label: CompanionVisualAsset.label(form: preferences.form, family: selectedFamily, treatment: preferences.visualTreatment, recipe: recipe, naturalVariation: evolution.naturalVariation),
            png: bytes,
            motionAllowed: !preferences.quiet && !preferences.reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            visible: isVisible && !(NSApp?.isHidden ?? false))
    }
}

/// Candidate motion stays outside artwork exports and saved character identity.
@MainActor
struct LiveCompanionPresence: View {
    @ObservedObject var store: CompanionStore
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var body: some View {
        Group {
            if !store.preferences.quiet && !store.preferences.reduceMotion && !systemReduceMotion,
               let image = store.reactor.frameImage {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .accessibilityLabel("ARCHi · " + store.reactor.state.title)
            } else {
                CompanionPresenceArt(form: store.preferences.form, family: store.evolution.activeFamily,
                    size: size, reduceMotion: store.preferences.reduceMotion || systemReduceMotion || store.preferences.quiet,
                    treatment: store.preferences.visualTreatment, recipe: store.evolution.activeAppearanceRecipe, naturalVariation: store.evolution.naturalVariation)
            }
        }.frame(width: size, height: size)
    }
}
