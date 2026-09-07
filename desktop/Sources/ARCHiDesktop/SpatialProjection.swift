import Foundation

/// Canonical input shared by native planning and recording. Layout rectangles
/// project both measured edges; action rectangles preserve AppKit's exact size.
enum SpatialProjection {
    static let maximumCoordinate: Double = 1_000_000

    static func scene(geometry: SelectedPassageGeometry, companionFrame: CGRect,
                      visibleDisplay: CGRect) -> SpatialRecordedScene? {
        let origin = geometry.screenFrame.origin
        guard validOrigin(origin), !geometry.rects.isEmpty,
              geometry.screenFrame.contains(visibleDisplay),
              geometry.rects.allSatisfy({ geometry.viewport.contains($0)
                  && geometry.windowFrame.contains($0) && visibleDisplay.contains($0) }),
              let screen = layout(geometry.screenFrame, origin: origin),
              let visible = layout(visibleDisplay, origin: origin),
              let viewport = layout(geometry.viewport, origin: origin),
              let window = layout(geometry.windowFrame, origin: origin),
              let companion = actionFrame(companionFrame, origin: origin) else { return nil }
        let targets = geometry.rects.compactMap { layout($0, origin: origin) }
        guard targets.count == geometry.rects.count else { return nil }
        return SpatialRecordedScene(screen: screen, visibleDisplay: visible, viewport: viewport,
            windowFrame: window, companionFrame: companion, targets: targets)
    }

    static func actionFrame(_ rect: CGRect, origin: CGPoint) -> SpatialRecordedRect? {
        project(rect, origin: origin, preserveSize: true)
    }

    static func globalActionFrame(_ rect: CGRect, origin: CGPoint) -> CGRect? {
        guard validOrigin(origin) else { return nil }
        let global = CGRect(x: rect.origin.x + origin.x, y: rect.origin.y + origin.y,
                            width: rect.size.width, height: rect.size.height)
        guard let projected = actionFrame(global, origin: origin), projected.cgRect == rect else { return nil }
        return global
    }

    private static func layout(_ rect: CGRect, origin: CGPoint) -> SpatialRecordedRect? {
        project(rect, origin: origin, preserveSize: false)
    }

    private static func validOrigin(_ origin: CGPoint) -> Bool {
        [origin.x, origin.y].allSatisfy {
            $0.isFinite && abs(Double($0)) <= maximumCoordinate && $0.rounded(.towardZero) == $0
        }
    }

    private static func project(_ rect: CGRect, origin: CGPoint, preserveSize: Bool) -> SpatialRecordedRect? {
        guard validOrigin(origin), !rect.isNull, !rect.isInfinite,
              rect.size.width > 0, rect.size.height > 0 else { return nil }
        let global = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, rect.maxX, rect.maxY]
        guard global.allSatisfy({ $0.isFinite && abs(Double($0)) <= maximumCoordinate }) else { return nil }
        let x = Double(rect.origin.x - origin.x), y = Double(rect.origin.y - origin.y)
        let local = SpatialRecordedRect(x: x, y: y,
            width: preserveSize ? Double(rect.size.width) : Double(rect.maxX - origin.x) - x,
            height: preserveSize ? Double(rect.size.height) : Double(rect.maxY - origin.y) - y)
        let components = [local.x, local.y, local.width, local.height,
                          local.x + local.width, local.y + local.height]
        guard local.width > 0, local.height > 0,
              components.allSatisfy({ $0.isFinite && abs($0) <= maximumCoordinate }) else { return nil }
        return local
    }
}
