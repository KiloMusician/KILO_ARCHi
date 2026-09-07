import Foundation

/// Every rectangle uses AppKit global points, with a bottom-left origin.
struct SelectedPassageGeometry: Equatable {
    let selection: DocumentSelection
    let rects: [CGRect]
    let viewport: CGRect
    let windowFrame: CGRect
    let windowNumber: Int
    let screenID: UInt32
    let screenFrame: CGRect
}

struct SpatialPlacementCandidate: Equatable {
    let frame: CGRect
    let reason: String
    let staysPut: Bool
}

/// Pure rectangle planning for one measured shared view. It observes no other applications.
enum SpatialPlacementPlanner {
    static let version = "native-placement/2"
    static let displayInset: CGFloat = 8
    static let targetPadding: CGFloat = 12
    static let nearTargetDistance: CGFloat = 48
    static let outsideWindowExtraTravel: CGFloat = 160
    static let movementWeight: CGFloat = 0.25
    static let workspaceOverlapPenalty: CGFloat = 80

    static func propose(geometry: SelectedPassageGeometry, companionFrame: CGRect,
                        visibleDisplay: CGRect) -> SpatialPlacementCandidate? {
        guard geometry.windowNumber > 0, geometry.screenID != 0,
              !geometry.rects.isEmpty,
              [geometry.viewport, geometry.windowFrame, geometry.screenFrame,
               companionFrame, visibleDisplay].allSatisfy(valid),
              geometry.screenFrame.contains(visibleDisplay),
              geometry.rects.allSatisfy({ rect in
                  valid(rect) && geometry.viewport.contains(rect)
                      && geometry.windowFrame.contains(rect) && visibleDisplay.contains(rect)
              }) else { return nil }

        guard let scene = SpatialProjection.scene(geometry: geometry, companionFrame: companionFrame,
                                                   visibleDisplay: visibleDisplay),
              let local = propose(scene: scene) else { return nil }
        let global: CGRect
        if local.staysPut {
            global = companionFrame
        } else {
            guard let mapped = SpatialProjection.globalActionFrame(local.frame, origin: geometry.screenFrame.origin) else { return nil }
            global = mapped
        }
        // Canonical planning never relaxes the original native observation's
        // display boundary or passage protection before a proposal is exposed.
        let rawUsable = visibleDisplay.insetBy(dx: displayInset, dy: displayInset)
        let rawProtected = geometry.rects.map { $0.insetBy(dx: -targetPadding, dy: -targetPadding) }
        guard valid(global), valid(rawUsable), rawProtected.allSatisfy(valid),
              global.size == companionFrame.size, rawUsable.contains(global),
              !rawProtected.contains(where: { overlaps(global, $0) }) else { return nil }
        return SpatialPlacementCandidate(frame: global, reason: local.reason, staysPut: local.staysPut)
    }

    /// All scoring and candidate arithmetic use this exact display-local DTO,
    /// which the recorder also exports. This does not claim cross-platform
    /// floating-point functions are universally identical.
    static func propose(scene: SpatialRecordedScene) -> SpatialPlacementCandidate? {
        let companionFrame = scene.companionFrame.cgRect
        let visibleDisplay = scene.visibleDisplay.cgRect
        let viewport = scene.viewport.cgRect, workspace = scene.windowFrame.cgRect
        let screen = scene.screen.cgRect, targets = scene.targets.map(\.cgRect)
        guard screen.origin == .zero, !targets.isEmpty,
              [screen, visibleDisplay, viewport, workspace, companionFrame].allSatisfy(valid),
              screen.contains(visibleDisplay), targets.allSatisfy({
                  valid($0) && viewport.contains($0) && workspace.contains($0) && visibleDisplay.contains($0)
              }) else { return nil }

        let usable = visibleDisplay.insetBy(dx: displayInset, dy: displayInset)
        guard valid(usable), companionFrame.width <= usable.width,
              companionFrame.height <= usable.height else { return nil }
        let protected = targets.map { $0.insetBy(dx: -targetPadding, dy: -targetPadding) }
        guard protected.allSatisfy(valid) else { return nil }
        let target = targets.dropFirst().reduce(targets[0]) { $0.union($1) }
        guard valid(target) else { return nil }

        func eligible(_ frame: CGRect) -> Bool {
            valid(frame) && frame.size == companionFrame.size && usable.contains(frame)
                && !protected.contains(where: { overlaps(frame, $0) })
        }

        func candidate(_ frame: CGRect) -> SpatialPlacementCandidate {
            SpatialPlacementCandidate(frame: frame, reason: "The selected passage remains clear.",
                                      staysPut: frame == companionFrame)
        }

        // An already useful, clear position wins without an unnecessary automatic move.
        if eligible(companionFrame), distance(companionFrame, target) <= nearTargetDistance {
            return candidate(companionFrame)
        }

        let width = companionFrame.width, height = companionFrame.height
        let centeredX = target.midX - width / 2, centeredY = target.midY - height / 2
        // Stable tie order: stay, left, right, above, below.
        let adjacent = [
            CGRect(x: target.minX - targetPadding - width, y: centeredY, width: width, height: height),
            CGRect(x: target.maxX + targetPadding, y: centeredY, width: width, height: height),
            CGRect(x: centeredX, y: target.maxY + targetPadding, width: width, height: height),
            CGRect(x: centeredX, y: target.minY - targetPadding - height, width: width, height: height)
        ]
        let exterior = [
            CGRect(x: min(adjacent[0].minX, workspace.minX - width), y: centeredY, width: width, height: height),
            CGRect(x: max(adjacent[1].minX, workspace.maxX), y: centeredY, width: width, height: height),
            CGRect(x: centeredX, y: max(adjacent[2].minY, workspace.maxY), width: width, height: height),
            CGRect(x: centeredX, y: min(adjacent[3].minY, workspace.minY - height), width: width, height: height)
        ]

        var frames = [companionFrame]
        for index in adjacent.indices {
            let nearby = adjacent[index], outside = exterior[index]
            // Prefer clearing our whole workspace when that costs at most 160 extra points.
            // This says nothing about visibility or occlusion in external applications.
            if eligible(outside), centerDistance(nearby, outside) <= outsideWindowExtraTravel {
                frames.append(outside)
            } else if valid(nearby) {
                frames.append(CGRect(
                    x: min(max(nearby.minX, usable.minX), usable.maxX - width),
                    y: min(max(nearby.minY, usable.minY), usable.maxY - height),
                    width: width, height: height))
            }
        }

        // AppKit may round a requested fractional origin when applying a window
        // frame. Preview only realizable integral-point origins, then recheck
        // eligibility; rounding after validation could cross the protected text.
        let realizable = [companionFrame] + frames.dropFirst().flatMap { frame in
            [frame.minX.rounded(.down), frame.minX.rounded(.up)].flatMap { x in
                [frame.minY.rounded(.down), frame.minY.rounded(.up)].map { y in
                    CGRect(x: x, y: y, width: width, height: height)
                }
            }
        }
        var best: CGRect?
        var bestScore = CGFloat.infinity
        for frame in realizable where eligible(frame) {
            let score = distance(frame, target)
                + movementWeight * centerDistance(frame, companionFrame)
                + (overlaps(frame, workspace) ? workspaceOverlapPenalty : 0)
            guard score.isFinite else { continue }
            if score < bestScore { best = frame; bestScore = score }
        }
        return best.map(candidate)
    }

    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isInfinite && !rect.isNull && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
            && rect.size.width > 0 && rect.size.height > 0
            && rect.maxX.isFinite && rect.maxY.isFinite
    }

    /// Strict intersection permits boundary contact while preserving the declared padding.
    private static func overlaps(_ first: CGRect, _ second: CGRect) -> Bool {
        first.minX < second.maxX && first.maxX > second.minX
            && first.minY < second.maxY && first.maxY > second.minY
    }

    private static func distance(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let dx = max(0, max(first.minX - second.maxX, second.minX - first.maxX))
        let dy = max(0, max(first.minY - second.maxY, second.minY - first.maxY))
        return hypot(dx, dy)
    }

    private static func centerDistance(_ first: CGRect, _ second: CGRect) -> CGFloat {
        hypot(first.midX - second.midX, first.midY - second.midY)
    }
}
