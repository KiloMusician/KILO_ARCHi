import Foundation

/// Two native presentations of the same individual. A surface has no saved
/// identity, development, placement or permission state of its own.
enum CompanionPresentationRole: Equatable, Sendable {
    case body
    case cursor
}

@MainActor
extension CompanionStore {
    var hasPersonalQiMon: Bool { keptQiMon != nil }
    var canChooseStartingForm: Bool { !hasPersonalQiMon }

    /// Identity remains in LocalQiMon. The existing Evolution owner supplies
    /// an explicitly kept body only for that same individual.
    func presentationForm(for preferences: CompanionPreferences, role: CompanionPresentationRole = .body) -> CompanionForm {
        if let kin = activeQiMon {
            // The Seed persists as KIN's cursor even after a body is kept.
            // Use the same active-identity check as body presentation.
            if role == .cursor { return .kinSeed }
            if let growth = evolution.kinGrowthRecord,
               growth.originDigest == kin.originDigest, growth.active { return .kin }
            return kin.currentBody
        }
        return preferences.form.isKin ? .companion : preferences.form
    }
    var presentationForm: CompanionForm { presentationForm(for: preferences) }
    var cursorPresentationForm: CompanionForm { presentationForm(for: preferences, role: .cursor) }
    var presentationFamily: EvolutionFamily? { hasPersonalQiMon ? nil : evolution.activeFamily }
    var presentationRecipe: CompanionAppearanceRecipe? { hasPersonalQiMon ? nil : evolution.activeAppearanceRecipe }
    var presentationNaturalVariation: CompanionNaturalVariation? { hasPersonalQiMon ? nil : evolution.naturalVariation }
    var presentationTitle: String { activeQiMon?.name ?? presentationFamily?.title ?? presentationForm.rawValue }
    var kinBodyTitle: String { presentationForm == .kin ? "First Light" : "Core Seed" }

    /// Uses the existing saved appearance preference. A missing or mismatched
    /// personal Journey cannot select a different individual's presentation.
    func chooseLightForm(_ form: CompanionForm) {
        guard !isShuttingDown, form.isOpticalLight else { return }
        guard !hasPersonalQiMon else { return }
        chooseStartingForm(form)
    }
}
