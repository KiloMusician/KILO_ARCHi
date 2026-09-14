import Foundation

@MainActor
extension CompanionStore {
    /// A staff design's closed action reuses the existing app-owned observation,
    /// freshness, expiry and optional-move path. It cannot send a model request.
    @discardableResult
    func activateEquippedItem() -> Bool {
        guard preferences.equipment.supportsPointing, !isShuttingDown else { return false }
        return performFocusGestureOnSelection(configuration: keptFocusGesture ?? preferences.equipment.design?.defaultGesture ?? FocusGestureConfiguration(),
                                              purpose: .pointing)
    }
}
