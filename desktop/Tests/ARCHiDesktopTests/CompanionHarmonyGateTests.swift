import XCTest
@testable import ARCHiDesktop

final class CompanionHarmonyGateTests: XCTestCase {
    func testStartupAndExistingStateNeverProduceCatchUpSound() {
        for initial in KinLightMode.allCases {
            var gate = CompanionHarmonyGate()
            XCTAssertEqual(gate.update(snapshot: snapshot(initial), now: 10), .none)
            XCTAssertEqual(gate.update(snapshot: snapshot(initial), now: 100), .none)
        }
        var gate = CompanionHarmonyGate()
        XCTAssertEqual(gate.update(snapshot: snapshot(.rest), now: 0), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.orbit), now: 1), .play(.orbit))
        XCTAssertEqual(gate.update(snapshot: snapshot(.orbit), now: 10), .none)
    }

    func testEnablingExistingWorkStaysSilentUntilANewModeChange() {
        var gate = CompanionHarmonyGate()
        XCTAssertEqual(gate.update(snapshot: snapshot(.orbit, enabled: false), now: 0), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse, enabled: false), now: 1), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse), now: 2), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse), now: 10), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.delight), now: 11), .play(.delight))
    }

    func testRestMuteQuietAndHideStopTheOwnedCueWithoutReplayOnReturn() {
        let silentSnapshots = [snapshot(.rest), snapshot(.orbit, enabled: false),
            snapshot(.orbit, quiet: true), snapshot(.orbit, visible: false)]
        for silent in silentSnapshots {
            var gate = CompanionHarmonyGate()
            XCTAssertEqual(gate.update(snapshot: snapshot(.rest), now: 0), .none)
            XCTAssertEqual(gate.update(snapshot: snapshot(.orbit), now: 1), .play(.orbit))
            XCTAssertEqual(gate.update(snapshot: silent, now: 2), .stop)
            XCTAssertEqual(gate.update(snapshot: silent, now: 3), .none)
            if silent.expression.mode != .rest {
                XCTAssertEqual(gate.update(snapshot: snapshot(.orbit), now: 10), .none)
                XCTAssertEqual(gate.update(snapshot: snapshot(.orbit), now: 20), .none)
            }
        }
    }

    func testAutomaticCooldownDropsTransitionsInsteadOfDelayingThem() {
        var gate = CompanionHarmonyGate()
        _ = gate.update(snapshot: snapshot(.rest), now: 0)
        XCTAssertEqual(gate.update(snapshot: snapshot(.orbit), now: 1), .play(.orbit))
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse), now: 2), .stop)
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse), now: 10), .none,
            "The dropped pulse must not play after the cooldown has expired")
        XCTAssertEqual(gate.update(snapshot: snapshot(.delight), now: 11), .play(.delight))
        XCTAssertEqual(gate.update(snapshot: snapshot(.hold), now: 15), .play(.hold),
            "Exactly four elapsed seconds admits a new automatic mode")
    }

    func testNewPreviewUUIDCanReplayTheSameModeAndSupersedeCooldown() {
        var gate = CompanionHarmonyGate()
        _ = gate.update(snapshot: snapshot(.rest), now: 0)
        let first = UUID(), second = UUID()
        XCTAssertEqual(gate.update(snapshot: snapshot(.focus, preview: first), now: 1), .play(.focus))
        XCTAssertEqual(gate.update(snapshot: snapshot(.focus, preview: first), now: 1.1), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.focus, preview: second), now: 1.2), .play(.focus))
        XCTAssertEqual(gate.update(snapshot: snapshot(.focus, preview: second), now: 10), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.orbit), now: 10.1), .play(.orbit))
        XCTAssertEqual(gate.update(snapshot: snapshot(.core, preview: UUID()), now: 10.2), .play(.core))
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse), now: 10.3), .stop,
            "Automatic cues still wait after a deliberate preview")
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse), now: 20), .none)
    }

    func testPreviewNeedsAnEventAndCannotReplayByChangingItsModeOrFinishing() {
        var gate = CompanionHarmonyGate()
        _ = gate.update(snapshot: snapshot(.rest), now: 0)
        let missingEvent = CompanionHarmonySnapshot(expression: .init(mode: .focus, isPreview: true),
            enabled: true, quiet: false, visible: true)
        XCTAssertEqual(gate.update(snapshot: missingEvent, now: 1), .none)
        let id = UUID()
        XCTAssertEqual(gate.update(snapshot: snapshot(.focus, preview: id), now: 2), .play(.focus))
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse, preview: id), now: 3), .stop,
            "Changing a preview snapshot does not create a new user event")
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse, preview: id), now: 10), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse), now: 11), .none)
        let newID = UUID()
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse, preview: newID), now: 12), .play(.pulse))
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse), now: 13), .stop)
    }

    func testInvalidAndBackwardClocksStopSoundAndConsumeTheDroppedChange() {
        for invalid in [Double.nan, .infinity, -.infinity, -1, 9] {
            var gate = CompanionHarmonyGate()
            _ = gate.update(snapshot: snapshot(.rest), now: 10)
            XCTAssertEqual(gate.update(snapshot: snapshot(.orbit), now: 11), .play(.orbit))
            XCTAssertEqual(gate.update(snapshot: snapshot(.pulse, preview: UUID()), now: invalid), .stop)
            XCTAssertEqual(gate.update(snapshot: snapshot(.pulse), now: 20), .none)
            XCTAssertEqual(gate.update(snapshot: snapshot(.delight), now: 21), .play(.delight))
        }
    }

    func testBackwardClockCannotLowerTheHighWaterMarkAndTriggerAnotherCue() {
        var gate = CompanionHarmonyGate()
        _ = gate.update(snapshot: snapshot(.rest), now: 100)
        XCTAssertEqual(gate.update(snapshot: snapshot(.orbit), now: 101), .play(.orbit))
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse), now: 50), .stop)
        XCTAssertEqual(gate.update(snapshot: snapshot(.focus, preview: UUID()), now: 60), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.delight), now: 90), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.delight), now: 110), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.hold), now: 111), .play(.hold))
    }

    func testAnInvalidInitialClockAndResetBothRequireASilentBaseline() {
        var gate = CompanionHarmonyGate()
        XCTAssertEqual(gate.update(snapshot: snapshot(.orbit), now: .nan), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.pulse), now: 1), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.delight), now: 2), .play(.delight))
        gate.reset()
        XCTAssertEqual(gate.update(snapshot: snapshot(.hold), now: 3), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.hold), now: 10), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.core, preview: UUID()), now: 11), .play(.core))
    }

    func testPreviewCreatedWhileMutedIsNotReplayedWhenSoundReturns() {
        var gate = CompanionHarmonyGate()
        _ = gate.update(snapshot: snapshot(.rest), now: 0)
        let oldID = UUID()
        XCTAssertEqual(gate.update(snapshot: snapshot(.focus, preview: oldID, enabled: false), now: 1), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.focus, preview: oldID), now: 2), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.focus, preview: oldID), now: 10), .none)
        XCTAssertEqual(gate.update(snapshot: snapshot(.focus, preview: UUID()), now: 11), .play(.focus))
    }

    private func snapshot(_ mode: KinLightMode, preview: UUID? = nil,
                          enabled: Bool = true, quiet: Bool = false, visible: Bool = true) -> CompanionHarmonySnapshot {
        CompanionHarmonySnapshot(expression: .init(mode: mode, isPreview: preview != nil),
            enabled: enabled, quiet: quiet, visible: visible, previewID: preview)
    }
}
