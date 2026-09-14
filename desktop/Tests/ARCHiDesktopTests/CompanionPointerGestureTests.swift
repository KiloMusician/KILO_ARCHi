import AppKit
import Testing
@testable import ARCHiDesktop

struct CompanionPointerGestureTests {
    private let frame = CGRect(x: 550, y: 360, width: 128, height: 154)
    private let origin = CGPoint(x: 613, y: 423)

    @Test func releaseDisplacementRecognizesDragWithoutAnIntermediateEvent() {
        var gesture = CompanionPointerGesture()
        gesture.begin(at: origin, frame: frame)
        #expect(gesture.release(at: CGPoint(x: origin.x + 28, y: origin.y - 19))
            == .moved(frame.offsetBy(dx: 28, dy: -19)))
        #expect(gesture.release(at: origin) == .cancelled)
    }

    @Test func queuedMovesUseTheOriginalFrameRatherThanAccumulatingWindowMovement() {
        var gesture = CompanionPointerGesture()
        gesture.begin(at: origin, frame: frame)
        #expect(gesture.move(to: CGPoint(x: origin.x + 10, y: origin.y + 7)) == frame.offsetBy(dx: 10, dy: 7))
        #expect(gesture.move(to: CGPoint(x: origin.x + 20, y: origin.y + 13)) == frame.offsetBy(dx: 20, dy: 13))
        #expect(gesture.release(at: CGPoint(x: origin.x + 28, y: origin.y + 19)) == .moved(frame.offsetBy(dx: 28, dy: 19)))
    }

    @Test func smallJitterIsAClickButReturningAfterADragIsNot() {
        var gesture = CompanionPointerGesture()
        gesture.begin(at: origin, frame: frame)
        #expect(gesture.move(to: CGPoint(x: origin.x + 1, y: origin.y + 1)) == nil)
        #expect(gesture.release(at: CGPoint(x: origin.x + 1, y: origin.y + 1)) == .click)
        gesture.begin(at: origin, frame: frame)
        #expect(gesture.move(to: CGPoint(x: origin.x + 3, y: origin.y)) != nil)
        #expect(gesture.release(at: origin) == .moved(frame))
    }

    @Test func negativeDisplayCoordinatesAndReleasePositionRemainExact() {
        var gesture = CompanionPointerGesture()
        let negativeFrame = CGRect(x: -1500, y: -900, width: 128, height: 154)
        gesture.begin(at: CGPoint(x: -1450, y: -830), frame: negativeFrame)
        #expect(gesture.release(at: CGPoint(x: -1422, y: -849))
            == .moved(negativeFrame.offsetBy(dx: 28, dy: -19)))
    }

    @Test func cancelledOrMalformedInputCannotBecomeAClick() {
        var gesture = CompanionPointerGesture()
        gesture.begin(at: origin, frame: frame)
        gesture.cancel()
        #expect(gesture.release(at: origin) == .cancelled)
        gesture.begin(at: CGPoint(x: CGFloat.nan, y: 1), frame: frame)
        #expect(gesture.release(at: origin) == .cancelled)
        gesture.begin(at: origin, frame: .null)
        #expect(gesture.release(at: origin) == .cancelled)
        gesture.begin(at: origin, frame: frame)
        #expect(gesture.release(at: nil) == .cancelled)
        #expect(gesture.release(at: origin) == .cancelled)
    }

    @Test func newDownReplacesThePreviousGestureWithoutMovingAnything() {
        var gesture = CompanionPointerGesture()
        gesture.begin(at: origin, frame: frame)
        _ = gesture.move(to: CGPoint(x: origin.x + 50, y: origin.y))
        let nextPoint = CGPoint(x: -400, y: 200)
        let nextFrame = CGRect(x: -450, y: 140, width: 128, height: 154)
        gesture.begin(at: nextPoint, frame: nextFrame)
        #expect(gesture.release(at: nextPoint) == .click)
    }
}

@MainActor
struct CompanionPointerEventTests {
    /// Construct and deliver event values in-process only: no posting events,
    /// live-pointer movement, visible windows or app activation.
    @Test func eventPositionsStayDistinctAfterQueuedCreationAndWindowMovement() throws {
        _ = NSApplication.shared
        let downQuartz = CGPoint(x: 300, y: 240)
        let dragQuartz = CGPoint(x: 328, y: 259)
        let releaseQuartz = CGPoint(x: 350, y: 278)
        let downCG = try #require(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                         mouseCursorPosition: downQuartz, mouseButton: .left))
        let dragCG = try #require(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                                         mouseCursorPosition: dragQuartz, mouseButton: .left))
        let releaseCG = try #require(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                            mouseCursorPosition: releaseQuartz, mouseButton: .left))
        let down = try #require(NSEvent(cgEvent: downCG))
        let drag = try #require(NSEvent(cgEvent: dragCG))
        let release = try #require(NSEvent(cgEvent: releaseCG))
        let start = try #require(CompanionPointerLocation.screenPoint(for: down))
        let middle = try #require(CompanionPointerLocation.screenPoint(for: drag))
        let end = try #require(CompanionPointerLocation.screenPoint(for: release))
        #expect(middle.x - start.x == 28)
        #expect(middle.y - start.y == -19)
        #expect(end.x - start.x == 50)
        #expect(end.y - start.y == -38)
        let panel = NSPanel(contentRect: CGRect(x: 220, y: 300, width: 128, height: 154),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let frame = panel.frame
        var gesture = CompanionPointerGesture()
        gesture.begin(at: start, frame: frame)
        let middleFrame = gesture.move(to: middle)
        panel.setFrame(try #require(middleFrame), display: false)
        // Earlier queued events do not acquire the window's new origin.
        #expect(CompanionPointerLocation.screenPoint(for: down) == start)
        #expect(CompanionPointerLocation.screenPoint(for: release) == end)
        #expect(gesture.release(at: CompanionPointerLocation.screenPoint(for: release))
            == .moved(frame.offsetBy(dx: 50, dy: -38)))
        #expect(!panel.isVisible && !panel.isKeyWindow)
    }
}
