import Foundation

@MainActor
extension CompanionStore {
    /// A bundled item's closed action reuses the existing app-owned observation,
    /// freshness, expiry and optional-move path. It cannot send a model request.
    @discardableResult
    func activateEquippedItem() -> Bool {
        guard preferences.equipment.hand == .focusStaff, !isShuttingDown else { return false }
        return performFocusGestureOnSelection(configuration: keptFocusGesture ?? FocusGestureConfiguration(),
                                              purpose: .pointing)
    }
}
