import AppKit
import Testing
@testable import ARCHiDesktop

@MainActor
struct NativePlacementFrameTests {
    @Test(arguments: [1.0, 0.83, 1.6])
    func fractionalPassagePlanMatchesTheFrameAppKitActuallyApplies(scale: Double) throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main ?? NSScreen.screens.first)
        let display = screen.visibleFrame
        let passage = CGRect(x: display.minX + 300.25,
                             y: display.minY + min(500.25, display.height * 0.55),
                             width: 219.67, height: 16.7)
        let panel = NSPanel(contentRect: CGRect(x: passage.minX + 30, y: passage.minY - 25,
                                               width: 128 * scale, height: 154 * scale),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        defer { panel.close() }

        // Planning starts from the frame AppKit accepted, including any native
        // size normalization. The panel is never shown or given keyboard focus.
        let startingFrame = panel.frame
        let geometry = SelectedPassageGeometry(
            selection: try #require(DocumentSelection(range: NSRange(location: 0, length: 8),
                                                       text: "A passage", sourceRevision: 1)),
            rects: [passage], viewport: display.insetBy(dx: 80, dy: 60),
            windowFrame: display.insetBy(dx: 40, dy: 30),
            windowNumber: 12, screenID: 1, screenFrame: screen.frame)
        let candidate = try #require(SpatialPlacementPlanner.propose(
            geometry: geometry, companionFrame: startingFrame, visibleDisplay: display))
        #expect(!candidate.staysPut)
        panel.setFrame(candidate.frame, display: false, animate: false)

        #expect(panel.frame == candidate.frame)
        #expect(panel.frame.size == startingFrame.size)
        #expect(display.insetBy(dx: SpatialPlacementPlanner.displayInset,
                                dy: SpatialPlacementPlanner.displayInset).contains(panel.frame))
        let protected = passage.insetBy(dx: -SpatialPlacementPlanner.targetPadding,
                                       dy: -SpatialPlacementPlanner.targetPadding)
        #expect(panel.frame.maxX <= protected.minX || panel.frame.minX >= protected.maxX
                || panel.frame.maxY <= protected.minY || panel.frame.minY >= protected.maxY)
        #expect(!panel.isVisible)
        #expect(!panel.isKeyWindow)
    }
}
