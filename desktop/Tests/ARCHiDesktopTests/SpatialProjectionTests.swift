import Foundation
import Testing
@testable import ARCHiDesktop

@MainActor
struct SpatialProjectionTests {
    @Test func midpointBoundaryPlansFromTheExactSceneThatIsRecorded() throws {
        let f = fixture(origin: CGPoint(x: -7680, y: 0),
            target: CGRect(x: 300.1, y: 500, width: 1.8, height: 16.7),
            body: CGRect(x: 238, y: 490, width: 128, height: 154))
        let scene = try #require(SpatialProjection.scene(geometry: f.geometry,
            companionFrame: f.body, visibleDisplay: f.display))
        // This is the actual failure boundary: projecting endpoints changes the
        // midpoint's rounding relative to performing arithmetic globally first.
        #expect(f.geometry.rects[0].midX - f.display.minX == 301)
        #expect(scene.targets[0].cgRect.midX > 301)
        let local = try #require(SpatialPlacementPlanner.propose(scene: scene))
        let global = try #require(SpatialPlacementPlanner.propose(geometry: f.geometry,
            companionFrame: f.body, visibleDisplay: f.display))
        #expect(local.frame == CGRect(x: 238, y: 529, width: 128, height: 154))
        #expect(global.frame == local.frame.offsetBy(dx: f.display.minX, dy: f.display.minY))
        let recorder = SpatialRecorder()
        recorder.start()
        recorder.capture(preview(f, candidate: global), now: 10)
        let record = try #require(recorder.records.first)
        #expect(record.scene == scene)
        #expect(record.proposal.frame.cgRect == local.frame)
        #expect(record.proposal.staysPut == local.staysPut)
    }

    @Test func exactlyRepresentableScenesKeepIdenticalLocalDecisionsAcrossIntegralDisplays() throws {
        let target = CGRect(x: 420.25, y: 420.5, width: 240.5, height: 60.25)
        let body = CGRect(x: 460.25, y: 425.5, width: 137.5, height: 151.25)
        let base = fixture(origin: .zero, target: target, body: body)
        let expectedScene = try #require(SpatialProjection.scene(geometry: base.geometry,
            companionFrame: base.body, visibleDisplay: base.display))
        let expected = try #require(SpatialPlacementPlanner.propose(scene: expectedScene))
        for origin in [CGPoint(x: -7680, y: -300), CGPoint(x: -3840, y: 1080),
                       .zero, CGPoint(x: 1920, y: -1200), CGPoint(x: 3840, y: 0)] {
            let f = fixture(origin: origin, target: target, body: body)
            let scene = try #require(SpatialProjection.scene(geometry: f.geometry,
                companionFrame: f.body, visibleDisplay: f.display))
            let result = try #require(SpatialPlacementPlanner.propose(geometry: f.geometry,
                companionFrame: f.body, visibleDisplay: f.display))
            #expect(scene == expectedScene)
            #expect(result.frame == expected.frame.offsetBy(dx: origin.x, dy: origin.y))
            #expect(result.staysPut == expected.staysPut)
        }
    }

    @Test func stayPreservesTheOriginalNativeFrameIncludingItsFractionalSize() throws {
        let f = fixture(origin: CGPoint(x: -3840, y: -300),
            target: CGRect(x: 420.25, y: 420.5, width: 240.5, height: 60.25),
            body: CGRect(x: 308.25, y: 420.5, width: 99.5, height: 100.25))
        let result = try #require(SpatialPlacementPlanner.propose(geometry: f.geometry,
            companionFrame: f.body, visibleDisplay: f.display))
        #expect(result.staysPut)
        #expect(result.frame == f.body)
        let recorder = SpatialRecorder()
        recorder.start()
        let p = preview(f, candidate: result)
        recorder.capture(p, now: 10)
        recorder.finish(previewID: p.id, kind: .stayed, actualFrame: f.body, now: 10.5)
        let record = try #require(recorder.records.first)
        #expect(record.scene.companionFrame.cgRect.size == f.body.size)
        #expect(record.proposal.frame == record.scene.companionFrame)
        #expect(record.outcome.actualFrame == record.proposal.frame)
    }

    @Test func fractionalNonfiniteAndExcessiveOriginsCannotPlanOrRecord() {
        for origin in [CGPoint(x: 0.25, y: 0), CGPoint(x: 0, y: -0.5),
                       CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: CGFloat.infinity, y: 0),
                       CGPoint(x: 1_000_001, y: 0)] {
            let f = fixture(origin: origin)
            #expect(SpatialProjection.scene(geometry: f.geometry,
                companionFrame: f.body, visibleDisplay: f.display) == nil)
            #expect(SpatialPlacementPlanner.propose(geometry: f.geometry,
                companionFrame: f.body, visibleDisplay: f.display) == nil)
            let recorder = SpatialRecorder()
            recorder.start()
            recorder.capture(preview(f, candidate: SpatialPlacementCandidate(
                frame: f.body, reason: "Stay", staysPut: true)), now: 10)
            #expect(!recorder.isRecording)
            #expect(recorder.records.isEmpty)
        }
    }

    @Test func invalidActionRectanglesCannotMapBetweenCoordinateSpaces() {
        for invalid in [CGRect.zero, CGRect.null, CGRect.infinite,
                        CGRect(x: CGFloat.nan, y: 10, width: 20, height: 20),
                        CGRect(x: 10, y: 10, width: -20, height: 20),
                        CGRect(x: 1_000_001, y: 10, width: 20, height: 20)] {
            #expect(SpatialProjection.actionFrame(invalid, origin: .zero) == nil)
            #expect(SpatialProjection.globalActionFrame(invalid, origin: .zero) == nil)
        }
    }

    @Test func admittedCanonicalCandidatesKeepRawNativePassageProtection() throws {
        var admitted = 0
        for originX: CGFloat in [-7680, -3840, 0, 1920] {
            for width: CGFloat in [1.8, 16.7, 219.67, 299.7] {
                let f = fixture(origin: CGPoint(x: originX, y: -300),
                    target: CGRect(x: 300.1, y: 500.3, width: width, height: 16.7),
                    body: CGRect(x: 300.25, y: 470.5, width: 128, height: 154))
                guard let candidate = SpatialPlacementPlanner.propose(geometry: f.geometry,
                    companionFrame: f.body, visibleDisplay: f.display) else { continue }
                admitted += 1
                #expect(candidate.frame.size == f.body.size)
                #expect(f.display.insetBy(dx: 8, dy: 8).contains(candidate.frame))
                for target in f.geometry.rects {
                    let protected = target.insetBy(dx: -12, dy: -12)
                    #expect(candidate.frame.maxX <= protected.minX || candidate.frame.minX >= protected.maxX
                        || candidate.frame.maxY <= protected.minY || candidate.frame.minY >= protected.maxY)
                }
            }
        }
        #expect(admitted > 0)
    }

    private typealias Fixture = (geometry: SelectedPassageGeometry, body: CGRect, display: CGRect)

    private func fixture(origin: CGPoint,
                         target: CGRect = CGRect(x: 420, y: 420, width: 240, height: 60),
                         body: CGRect = CGRect(x: 460, y: 425, width: 128, height: 154)) -> Fixture {
        func moved(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: origin.x, dy: origin.y) }
        let display = CGRect(origin: origin, size: CGSize(width: 1600, height: 1000))
        return (SelectedPassageGeometry(
            selection: DocumentSelection(range: NSRange(location: 0, length: 8), text: "A passage", sourceRevision: 1)!,
            rects: [moved(target)], viewport: moved(CGRect(x: 250, y: 200, width: 850, height: 650)),
            windowFrame: moved(CGRect(x: 200, y: 100, width: 1000, height: 800)),
            windowNumber: 12, screenID: 1, screenFrame: display), moved(body), display)
    }

    private func preview(_ f: Fixture, candidate: SpatialPlacementCandidate) -> SpatialPreview {
        SpatialPreview(id: UUID(), candidate: candidate, geometry: f.geometry,
            environment: SpatialEnvironment(companionFrame: f.body,
                displays: [SpatialDisplay(id: 1, frame: f.display, visibleFrame: f.display)]),
            ticket: ContextTicket(generation: 0, placement: 0, source: 1, selection: 1), createdAt: 10)
    }
}
