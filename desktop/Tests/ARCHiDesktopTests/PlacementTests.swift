import Foundation
import Testing
@testable import ARCHiDesktop

struct PlacementTests {
    @Test func preservesManualPlacementWithinDisplay() {
        let original = CGRect(x: 211, y: 303, width: 128, height: 154)
        #expect(CompanionPlacement.clamped(original, to: [CGRect(x: 0, y: 0, width: 1440, height: 900)]) == original)
    }

    @Test func recoversAfterExternalDisplayDisconnects() {
        let frame = CGRect(x: -1400, y: 400, width: 128, height: 154)
        let remaining = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let recovered = CompanionPlacement.clamped(frame, to: [remaining])
        #expect(remaining.contains(recovered))
        #expect(recovered.minX == 8)
        #expect(recovered.minY == frame.minY)
    }

    @Test func supportsNegativeDisplayCoordinatesAndVerticalLayouts() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: -400, width: 1920, height: 1080)]
        let frame = CGRect(x: -900, y: -250, width: 128, height: 154)
        #expect(CompanionPlacement.clamped(frame, to: screens) == frame)
    }

    @Test func pointerSelectsDestinationAcrossDisplaySeam() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1440, height: 900)]
        let frame = CGRect(x: 1370, y: 200, width: 128, height: 154)
        let moved = CompanionPlacement.clamped(frame, to: screens, pointer: CGPoint(x: 1445, y: 230))
        #expect(moved.minX == 1448)
        #expect(moved.minY == 200)
    }

    @Test func displayGapChoosesNearestUsableScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 800, height: 600), CGRect(x: 1200, y: 0, width: 800, height: 600)]
        let moved = CompanionPlacement.clamped(CGRect(x: 1060, y: 200, width: 128, height: 154), to: screens)
        #expect(moved.minX == 1208)
    }

    @Test func remainsReachableOnTinyDisplay() {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
        let moved = CompanionPlacement.clamped(CGRect(x: 500, y: 500, width: 128, height: 154), to: [screen])
        #expect(screen.contains(moved))
        #expect(moved.width > 0 && moved.height > 0)
    }

    @Test func transientAbsenceOfScreensPreservesPosition() {
        let frame = CGRect(x: -500, y: 300, width: 128, height: 154)
        #expect(CompanionPlacement.clamped(frame, to: []) == frame)
    }
}
