import Foundation
import Testing
@testable import ARCHiDesktop

struct SpatialPlacementTests {
    private let display = CGRect(x: 0, y: 0, width: 1200, height: 900)
    private let body = CGRect(x: 460, y: 425, width: 100, height: 100)

    private func geometry(rects: [CGRect]? = nil, viewport: CGRect? = nil,
                          window: CGRect? = nil, screen: CGRect? = nil) -> SelectedPassageGeometry {
        SelectedPassageGeometry(
            selection: DocumentSelection(range: NSRange(location: 0, length: 8), text: "A passage", sourceRevision: 1)!,
            rects: rects ?? [CGRect(x: 420, y: 420, width: 240, height: 60)],
            viewport: viewport ?? CGRect(x: 260, y: 210, width: 640, height: 480),
            windowFrame: window ?? CGRect(x: 220, y: 160, width: 720, height: 580),
            windowNumber: 12, screenID: 1, screenFrame: screen ?? display)
    }

    @Test func overlappingCompanionMovesAndPreservesExactSize() throws {
        let original = CGRect(x: 460, y: 425, width: 137.5, height: 151.25)
        let scene = geometry()
        let result = try #require(SpatialPlacementPlanner.propose(geometry: scene, companionFrame: original, visibleDisplay: display))
        #expect(!result.staysPut)
        #expect(result.frame.size == original.size)
        #expect(display.insetBy(dx: 8, dy: 8).contains(result.frame))
        #expect(scene.rects.allSatisfy { rect in
            let protected = rect.insetBy(dx: -12, dy: -12)
            return result.frame.maxX <= protected.minX || result.frame.minX >= protected.maxX
                || result.frame.maxY <= protected.minY || result.frame.minY >= protected.maxY
        })
        #expect(result.reason == "The selected passage remains clear.")
    }

    @Test func clearNearbyPlacementStaysPut() throws {
        let original = CGRect(x: 308, y: 420, width: 100, height: 100)
        let result = try #require(SpatialPlacementPlanner.propose(geometry: geometry(), companionFrame: original, visibleDisplay: display))
        #expect(result.staysPut)
        #expect(result.frame == original)
    }

    @Test func malformedGeometryIsRejected() {
        let invalid = [CGRect.zero, CGRect.null, CGRect.infinite,
                       CGRect(x: CGFloat.nan, y: 420, width: 20, height: 20),
                       CGRect(x: 420, y: 420, width: -1, height: 20),
                       CGRect(x: 420, y: 420, width: 20, height: 0)]
        #expect(SpatialPlacementPlanner.propose(geometry: geometry(rects: []), companionFrame: body, visibleDisplay: display) == nil)
        for rect in invalid {
            #expect(SpatialPlacementPlanner.propose(geometry: geometry(rects: [rect]), companionFrame: body, visibleDisplay: display) == nil)
            #expect(SpatialPlacementPlanner.propose(geometry: geometry(viewport: rect), companionFrame: body, visibleDisplay: display) == nil)
            #expect(SpatialPlacementPlanner.propose(geometry: geometry(window: rect), companionFrame: body, visibleDisplay: display) == nil)
            #expect(SpatialPlacementPlanner.propose(geometry: geometry(screen: rect), companionFrame: body, visibleDisplay: display) == nil)
            #expect(SpatialPlacementPlanner.propose(geometry: geometry(), companionFrame: rect, visibleDisplay: display) == nil)
            #expect(SpatialPlacementPlanner.propose(geometry: geometry(), companionFrame: body, visibleDisplay: rect) == nil)
        }
    }

    @Test func targetMustBeFullyVisibleInEveryDeclaredBoundary() {
        let clippedViewport = CGRect(x: 450, y: 210, width: 450, height: 480)
        #expect(SpatialPlacementPlanner.propose(geometry: geometry(viewport: clippedViewport), companionFrame: body, visibleDisplay: display) == nil)
        let clippedWindow = CGRect(x: 220, y: 160, width: 400, height: 580)
        #expect(SpatialPlacementPlanner.propose(geometry: geometry(window: clippedWindow), companionFrame: body, visibleDisplay: display) == nil)
        let clippedDisplay = CGRect(x: 0, y: 0, width: 600, height: 900)
        #expect(SpatialPlacementPlanner.propose(geometry: geometry(), companionFrame: body, visibleDisplay: clippedDisplay) == nil)
        let differentDisplay = display.offsetBy(dx: 1000, dy: 0)
        #expect(SpatialPlacementPlanner.propose(geometry: geometry(), companionFrame: body, visibleDisplay: differentDisplay) == nil)
    }

    @Test func noEligiblePositionReturnsNilWithoutResizing() {
        let smallDisplay = CGRect(x: 0, y: 0, width: 200, height: 200)
        let scene = geometry(rects: [CGRect(x: 20, y: 20, width: 160, height: 160)],
                             viewport: smallDisplay, window: smallDisplay, screen: smallDisplay)
        #expect(SpatialPlacementPlanner.propose(geometry: scene, companionFrame: body, visibleDisplay: smallDisplay) == nil)
        #expect(SpatialPlacementPlanner.propose(geometry: geometry(),
                    companionFrame: CGRect(x: 0, y: 0, width: 1190, height: 100), visibleDisplay: display) == nil)
    }

    @Test func negativeOriginDisplaysPreserveTranslatedDecisions() throws {
        let scene = geometry()
        let original = try #require(SpatialPlacementPlanner.propose(geometry: scene, companionFrame: body, visibleDisplay: display))
        let dx: CGFloat = -1600, dy: CGFloat = -300
        let translatedDisplay = display.offsetBy(dx: dx, dy: dy)
        let translated = geometry(rects: scene.rects.map { $0.offsetBy(dx: dx, dy: dy) },
                                  viewport: scene.viewport.offsetBy(dx: dx, dy: dy),
                                  window: scene.windowFrame.offsetBy(dx: dx, dy: dy), screen: translatedDisplay)
        let result = try #require(SpatialPlacementPlanner.propose(geometry: translated,
                    companionFrame: body.offsetBy(dx: dx, dy: dy), visibleDisplay: translatedDisplay))
        #expect(result.frame == original.frame.offsetBy(dx: dx, dy: dy))
        #expect(result.staysPut == original.staysPut)
    }

    @Test func identicalInputsAndFragmentOrderProduceTheSameDecision() throws {
        let fragments = [CGRect(x: 420, y: 420, width: 240, height: 20),
                         CGRect(x: 420, y: 460, width: 120, height: 20)]
        let scene = geometry(rects: fragments)
        let original = try #require(SpatialPlacementPlanner.propose(geometry: scene, companionFrame: body, visibleDisplay: display))
        for _ in 0..<20 {
            #expect(SpatialPlacementPlanner.propose(geometry: scene, companionFrame: body, visibleDisplay: display) == original)
        }
        #expect(SpatialPlacementPlanner.propose(geometry: geometry(rects: Array(fragments.reversed())), companionFrame: body, visibleDisplay: display) == original)
    }

    @Test func protectionUsesIndividualFragmentsInsteadOfInventingSolidSelectedArea() throws {
        let fragments = [CGRect(x: 400, y: 360, width: 220, height: 20),
                         CGRect(x: 400, y: 540, width: 80, height: 20)]
        let between = CGRect(x: 430, y: 424, width: 72, height: 72)
        let result = try #require(SpatialPlacementPlanner.propose(geometry: geometry(rects: fragments), companionFrame: between, visibleDisplay: display))
        #expect(result.staysPut)
        #expect(result.frame == between)
    }

    @Test func practicalExteriorPositionAvoidsOurWorkspace() throws {
        let window = CGRect(x: 300, y: 100, width: 600, height: 700)
        let scene = geometry(rects: [CGRect(x: 330, y: 380, width: 140, height: 60)],
                             viewport: CGRect(x: 320, y: 120, width: 550, height: 660), window: window)
        let result = try #require(SpatialPlacementPlanner.propose(geometry: scene,
                    companionFrame: CGRect(x: 10, y: 10, width: 100, height: 100), visibleDisplay: display))
        #expect(result.frame.maxX == window.minX)
        #expect(!result.staysPut)
    }
}
