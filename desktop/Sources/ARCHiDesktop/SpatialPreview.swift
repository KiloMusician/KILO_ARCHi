import Foundation

/// The native adapter observes only display geometry and its own companion.
/// This is not an inventory of other applications or their contents.
struct SpatialDisplay: Equatable {
    let id: UInt32
    let frame: CGRect
    let visibleFrame: CGRect
}

struct SpatialEnvironment: Equatable {
    let companionFrame: CGRect
    let displays: [SpatialDisplay]
}

struct SpatialPlacementReceipt: Equatable {
    let requestedFrame: CGRect
    let actualFrame: CGRect?
    var matched: Bool { actualFrame == requestedFrame }
}

struct SpatialPreview: Equatable {
    static let lifetime: TimeInterval = 30
    let id: UUID
    let candidate: SpatialPlacementCandidate
    let geometry: SelectedPassageGeometry
    let environment: SpatialEnvironment
    let ticket: ContextTicket
    let createdAt: TimeInterval

    func isFresh(at now: TimeInterval) -> Bool {
        now.isFinite && createdAt.isFinite && now >= createdAt && now - createdAt < Self.lifetime
    }
}
