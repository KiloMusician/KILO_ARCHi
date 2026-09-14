import XCTest
@testable import ARCHiDesktop

final class KinSeedMotionTests: XCTestCase {
    func testUninterruptedCirculationRetainsTheEightySecondPeriod() {
        let motion = KinSeedMotion(at: 10)
        XCTAssertEqual(motion.sample(at: 10).angle, 0)
        XCTAssertEqual(motion.sample(at: 30).angle, 90, accuracy: 1e-12)
        XCTAssertEqual(motion.sample(at: 90).angle, 0, accuracy: 1e-12)
        XCTAssertEqual(motion.sample(at: 30).speed, 4.5, accuracy: 1e-12)
    }

    func testFocusSettlesWithContinuousAngleAndSpeedThenStaysAtThatOrientation() {
        var motion = KinSeedMotion()
        let before = motion.sample(at: 10)
        motion.transition(to: .init(mode: .focus), at: 10)
        XCTAssertEqual(motion.sample(at: 10), before)
        XCTAssertEqual(motion.sample(at: 10.3).speed, 2.25, accuracy: 1e-12)
        // The symmetric ease loses half of 4.5°/s over 0.6s: 1.35° of travel.
        let settled = motion.sample(at: 10.6)
        XCTAssertEqual(settled.angle, 46.35, accuracy: 1e-12)
        XCTAssertEqual(settled.speed, 0, accuracy: 1e-12)
        XCTAssertEqual(motion.sample(at: 100), motion.sample(at: 11))
        assertBoundedSmoothTravel(motion, from: 10, through: 12)
    }

    func testResumeStartsAtHeldOrientationAndEasesBackToOriginalSpeed() {
        var motion = KinSeedMotion()
        motion.transition(to: .init(mode: .hold), at: 10)
        let held = motion.sample(at: 50)
        motion.transition(to: .init(mode: .orbit), at: 50)
        XCTAssertEqual(motion.sample(at: 50), held)
        XCTAssertEqual(motion.sample(at: 50.3).speed, 2.25, accuracy: 1e-12)
        XCTAssertEqual(motion.sample(at: 50.6).angle, held.angle + 1.35, accuracy: 1e-12)
        XCTAssertEqual(motion.sample(at: 51).speed, 4.5, accuracy: 1e-12)
        assertBoundedSmoothTravel(motion, from: 50, through: 52)
    }

    func testRapidModeChangesDoNotJumpReverseOrExceedOriginalSpeed() {
        var motion = KinSeedMotion()
        let modes: [KinLightMode] = [.focus, .pulse, .hold, .orbit, .focus, .delight, .rest]
        for (index, mode) in modes.enumerated() {
            let time = 79.9 + Double(index) * 0.08
            let before = motion.sample(at: time)
            motion.transition(to: .init(mode: mode), at: time)
            let after = motion.sample(at: time)
            XCTAssertEqual(after.angle, before.angle, accuracy: 1e-12)
            XCTAssertEqual(after.speed, before.speed, accuracy: 1e-12)
            assertBoundedSmoothTravel(motion, from: time, through: time + 0.08)
            let epsilon = 0.00001
            let derivative = forwardAngle(after.angle, motion.sample(at: time + epsilon).angle) / epsilon
            XCTAssertEqual(derivative, before.speed, accuracy: 0.0001)
        }
        XCTAssertEqual(motion.sample(at: 90).speed, 4.5, accuracy: 1e-12)
    }

    func testSwitchingFocusToHoldDoesNotRestartAnUnfinishedSettlement() {
        var motion = KinSeedMotion()
        motion.transition(to: .init(mode: .focus), at: 1)
        let uninterrupted = motion
        motion.transition(to: .init(mode: .hold), at: 1.2)
        XCTAssertEqual(motion, uninterrupted)
        XCTAssertEqual(motion.sample(at: 1.7).speed, 0, accuracy: 1e-12)
        for mode in [KinLightMode.rest, .core, .orbit, .pulse, .delight] {
            XCTAssertEqual(KinSeedMotion.Policy(mode: mode).targetSpeed, 4.5)
        }
    }

    func testEitherReduceMotionSettingFreezesImmediatelyAndFreshExportsStayAtReference() {
        for (app, system) in [(true, false), (false, true), (true, true)] {
            for mode in KinLightMode.allCases {
                let reduced = KinSeedMotion.Policy(mode: mode, reduceMotion: app, systemReduceMotion: system)
                let fresh = KinSeedMotion(at: 100, policy: reduced)
                for time in [100.0, 1000, Double.greatestFiniteMagnitude] {
                    XCTAssertEqual(fresh.sample(at: time), .init(angle: 0, speed: 0))
                }
                var motion = KinSeedMotion()
                let angle = motion.sample(at: 15).angle
                motion.transition(to: reduced, at: 15)
                XCTAssertEqual(motion.sample(at: 15), .init(angle: angle, speed: 0))
                XCTAssertEqual(motion.sample(at: 100), .init(angle: angle, speed: 0))
                motion.transition(to: .init(mode: .rest), at: 100)
                XCTAssertEqual(motion.sample(at: 100), .init(angle: angle, speed: 0))
                XCTAssertEqual(motion.sample(at: 101).speed, 4.5, accuracy: 1e-12)
            }
        }
    }

    func testInvalidAndEarlierTransitionTimesCannotRewindOrPoisonMotion() {
        var motion = KinSeedMotion(at: 10)
        motion.transition(to: .init(mode: .focus), at: 20)
        let baseline = motion
        for time in [Double.nan, .infinity, -.infinity, -1, 19.9] {
            motion.transition(to: .init(mode: .rest), at: time)
            XCTAssertEqual(motion, baseline)
            XCTAssertTrue(motion.sample(at: time).angle.isFinite)
            XCTAssertTrue(motion.sample(at: time).speed.isFinite)
        }
        for state in [motion, KinSeedMotion(), KinSeedMotion(at: .nan)] {
            let distant = state.sample(at: .greatestFiniteMagnitude)
            XCTAssertTrue(distant.angle.isFinite)
            XCTAssertTrue((0..<360).contains(distant.angle))
            XCTAssertTrue((0...4.5).contains(distant.speed))
        }
    }

    func testFrameSamplingDoesNotAdvanceStateOrDependOnFrameRate() {
        var motion = KinSeedMotion()
        motion.transition(to: .init(mode: .focus), at: 10)
        let expected = motion.sample(at: 10.5)
        let original = motion
        for index in 0..<300 { _ = motion.sample(at: 10 + Double(index) / 600) }
        XCTAssertEqual(motion, original)
        XCTAssertEqual(motion.sample(at: 10.5), expected)
        XCTAssertEqual(expected.radians, expected.angle * .pi / 180, accuracy: 1e-12)
    }

    private func assertBoundedSmoothTravel(_ motion: KinSeedMotion, from start: Double, through end: Double,
                                           file: StaticString = #filePath, line: UInt = #line) {
        let interval = (end - start) / 100
        var previous = motion.sample(at: start)
        for index in 1...100 {
            let current = motion.sample(at: start + Double(index) * interval)
            XCTAssertTrue((0...4.5).contains(current.speed), file: file, line: line)
            XCTAssertLessThanOrEqual(forwardAngle(previous.angle, current.angle),
                                    4.5 * interval + 1e-10, file: file, line: line)
            previous = current
        }
    }

    private func forwardAngle(_ start: Double, _ end: Double) -> Double {
        (end - start + 360).truncatingRemainder(dividingBy: 360)
    }
}
