import AppKit
import Testing
@testable import ARCHiDesktop

@MainActor
struct SpatialStoreTests {
    @MainActor
    private final class Clock { var now: TimeInterval = 10 }

    @MainActor
    private final class Fixture {
        let clock = Clock()
        let store: CompanionStore
        var geometry: SelectedPassageGeometry
        var environment: SpatialEnvironment
        var moves: [CGRect] = []
        var shown: [SpatialPreview?] = []
        init() {
            let clock = clock
            store = CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"), monotonicTime: { clock.now })
            store.share(text: "Same🌙 text\nSame🌙 text", name: "synthetic.txt")
            store.selectText(range: NSRange(location: 12, length: 11), sourceRevision: store.sourceRevision)
            let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
            geometry = SelectedPassageGeometry(selection: store.textSelection!,
                rects: [CGRect(x: 300, y: 500, width: 220, height: 20)],
                viewport: CGRect(x: 280, y: 300, width: 340, height: 300),
                windowFrame: CGRect(x: 200, y: 100, width: 1000, height: 700),
                windowNumber: 12, screenID: 1, screenFrame: display)
            environment = SpatialEnvironment(companionFrame: CGRect(x: 360, y: 450, width: 128, height: 154),
                displays: [SpatialDisplay(id: 1, frame: display, visibleFrame: display)])
            store.onObserveSelectedPassage = { [weak self] in self?.geometry }
            store.onObserveSpatialEnvironment = { [weak self] in self?.environment }
            store.onMoveCompanion = { [weak self] frame in
                guard let self else { return }
                moves.append(frame)
                environment = SpatialEnvironment(companionFrame: frame, displays: environment.displays)
                store.placed(at: CGPoint(x: frame.midX, y: frame.midY))
            }
            store.onPresentPlacementPreview = { [weak self] preview in self?.shown.append(preview) }
        }
    }

    @Test func focusStaffReusesFreshSelectionWithoutMovingOrChangingTheIndividual() throws {
        let f = Fixture()
        f.store.evolution.observeJourneyOrigin(String(repeating: "a", count: 64))
        let individual = f.store.evolution.naturalVariation
        let evolutionRevision = f.store.evolution.revision
        let source = f.store.sharedText
        #expect(!f.store.activateEquippedItem())
        #expect(f.store.spatialPreview == nil)
        f.store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        #expect(f.store.activateEquippedItem())
        let preview = try #require(f.store.spatialPreview)
        #expect(preview.geometry == f.geometry)
        #expect(f.moves.isEmpty)
        #expect(!f.store.isWorking && f.store.compareResults.isEmpty)
        #expect(f.store.sharedText == source)
        #expect(f.store.evolution.naturalVariation == individual)
        #expect(f.store.evolution.revision == evolutionRevision)
        f.store.preferences.equipment = .empty
        #expect(f.store.spatialPreview == nil)
        f.store.applyPlacementPreview()
        #expect(f.moves.isEmpty)
    }

    @Test func focusStaffCannotBypassBusyHiddenStaleOrUnavailableGeometry() {
        let changes: [(CompanionStore) -> Void] = [
            { $0.isWorking = true }, { $0.hideCompanion() },
            { $0.invalidateTextSelection(reason: "Scrolled") },
            { $0.onObserveSelectedPassage = { nil } }
        ]
        for change in changes {
            let f = Fixture()
            f.store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
            change(f.store)
            #expect(!f.store.activateEquippedItem())
            #expect(f.store.spatialPreview == nil)
            #expect(f.moves.isEmpty)
        }
    }

    @Test func previewHasNoMovementAndExplicitApplyChecksActualFrame() throws {
        let f = Fixture()
        let original = f.environment.companionFrame
        f.store.previewPlacement()
        let preview = try #require(f.store.spatialPreview)
        #expect(!preview.candidate.staysPut)
        #expect(f.moves.isEmpty)
        #expect(f.environment.companionFrame == original)
        #expect(preview.geometry.selection.range.location == 12)
        f.store.applyPlacementPreview()
        #expect(f.moves == [preview.candidate.frame])
        #expect(f.store.spatialPreview == nil)
        #expect(f.store.textSelection == nil)
        #expect(f.store.spatialMessage.contains("moved beside"))
        f.store.applyPlacementPreview()
        #expect(f.moves.count == 1)
    }

    @Test func sourceSelectionScrollDragCancelAndHideClearGhostWithoutMoving() throws {
        let changes: [(CompanionStore) -> Void] = [
            { $0.share(text: "Changed", name: "new.txt") },
            { $0.selectText(range: NSRange(location: 0, length: 4), sourceRevision: $0.sourceRevision) },
            { $0.invalidateTextSelection(reason: "Document scrolled.") },
            { $0.placed(at: CGPoint(x: 20, y: 50)) },
            { $0.cancelWork() }, { $0.hideCompanion() },
            { $0.preferences.size = 1.2 }, { $0.dismissPlacementPreview() }
        ]
        for change in changes {
            let f = Fixture()
            f.store.previewPlacement()
            _ = try #require(f.store.spatialPreview)
            change(f.store)
            #expect(f.store.spatialPreview == nil)
            #expect(f.shown.last! == nil)
            f.store.applyPlacementPreview()
            #expect(f.moves.isEmpty)
        }
    }

    @Test func changedNativeGeometryOrDisplayCannotApplyEvenWithoutNotification() throws {
        for change in 0..<4 {
            let f = Fixture()
            f.store.previewPlacement()
            _ = try #require(f.store.spatialPreview)
            let g = f.geometry
            if change == 0 {
                f.geometry = SelectedPassageGeometry(selection: g.selection, rects: g.rects.map { $0.offsetBy(dx: 1, dy: 0) },
                    viewport: g.viewport, windowFrame: g.windowFrame, windowNumber: g.windowNumber, screenID: g.screenID, screenFrame: g.screenFrame)
            } else if change == 1 {
                f.environment = SpatialEnvironment(companionFrame: f.environment.companionFrame.offsetBy(dx: 1, dy: 0), displays: f.environment.displays)
            } else if change == 2 {
                let d = f.environment.displays[0]
                f.environment = SpatialEnvironment(companionFrame: f.environment.companionFrame,
                    displays: [SpatialDisplay(id: d.id, frame: d.frame, visibleFrame: d.visibleFrame.insetBy(dx: 0, dy: 20))])
            } else { f.store.onObserveSelectedPassage = { nil } }
            f.store.applyPlacementPreview()
            #expect(f.moves.isEmpty)
            #expect(f.store.spatialPreview == nil)
        }
    }

    @Test func expiredAndInvalidClockPreviewsNeverMove() throws {
        for time in [40.0, 100.0, 9.0, .infinity, .nan] {
            let f = Fixture()
            f.store.previewPlacement()
            _ = try #require(f.store.spatialPreview)
            f.clock.now = time
            f.store.applyPlacementPreview()
            #expect(f.moves.isEmpty)
            #expect(f.store.spatialPreview == nil)
        }
        let f = Fixture()
        f.store.previewPlacement()
        f.clock.now = 40
        f.store.expirePlacementPreview()
        #expect(f.store.spatialPreview == nil)
        #expect(f.store.spatialMessage.contains("expired"))
    }

    @Test func failedNativeMoveIsNotReportedAsSuccess() throws {
        let f = Fixture()
        f.store.previewPlacement()
        _ = try #require(f.store.spatialPreview)
        f.store.onMoveCompanion = { _ in }
        f.store.applyPlacementPreview()
        #expect(f.store.spatialPreview == nil)
        #expect(f.store.spatialMessage.contains("not confirmed"))
    }

    @Test func applyAfterExpiryRecordsExpiryEvenBeforeTheTimerRuns() throws {
        let f = Fixture()
        f.store.startSpatialRecording()
        f.store.previewPlacement()
        _ = try #require(f.store.spatialPreview)
        f.clock.now = 40
        f.store.applyPlacementPreview()
        f.store.stopSpatialRecording()
        #expect(f.moves.isEmpty)
        #expect(f.store.spatialPreview == nil)
        let root = try #require(JSONSerialization.jsonObject(with: f.store.spatialRecordingData()) as? [String: Any])
        let records = try #require(root["records"] as? [[String: Any]])
        let outcome = try #require(records.first?["outcome"] as? [String: Any])
        #expect(outcome["kind"] as? String == "expired")
    }

    @Test func reentrantInvalidationDuringObservationCannotMove() throws {
        let f = Fixture()
        f.store.previewPlacement()
        _ = try #require(f.store.spatialPreview)
        f.store.onObserveSelectedPassage = {
            f.store.cancelWork(reason: "Stopped while layout refreshed.")
            return f.geometry
        }
        f.store.applyPlacementPreview()
        #expect(f.moves.isEmpty)
        #expect(f.store.spatialPreview == nil)
        f.store.previewPlacement()
        #expect(f.store.spatialPreview == nil)
    }

    @Test func alreadyClearNearbyPositionStaysAndRetainsSelection() throws {
        let f = Fixture()
        f.environment = SpatialEnvironment(companionFrame: CGRect(x: 160, y: 460, width: 128, height: 154), displays: f.environment.displays)
        let selected = f.store.textSelection
        f.store.previewPlacement()
        #expect(try #require(f.store.spatialPreview).candidate.staysPut)
        f.store.applyPlacementPreview()
        #expect(f.moves.isEmpty)
        #expect(f.store.textSelection == selected)
        #expect(f.store.spatialMessage.contains("stayed here"))
    }

    @Test func recordingIsOptInAndAppliedMoveIsNotRecordedAsItsOwnInvalidation() throws {
        let f = Fixture()
        f.store.previewPlacement()
        f.store.dismissPlacementPreview()
        #expect(f.store.spatialRecordCount == 0)
        #expect(throws: (any Error).self) { try f.store.spatialRecordingData() }
        f.store.startSpatialRecording()
        f.store.previewPlacement()
        #expect(f.store.isRecordingSpatial)
        #expect(f.store.spatialRecordCount == 1)
        f.clock.now += 1
        f.store.applyPlacementPreview()
        f.store.stopSpatialRecording()
        let data = try f.store.spatialRecordingData()
        let export = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let records = try #require(export["records"] as? [[String: Any]])
        let outcome = try #require(records.first?["outcome"] as? [String: Any])
        #expect(outcome["kind"] as? String == "moved")
        #expect(outcome["actualFrame"] != nil)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("synthetic.txt"))
        #expect(!text.contains("Same"))
        #expect(!text.contains("sourceRevision"))
        #expect(!text.contains("windowNumber"))
    }

    @Test func stopRecordingClosesPendingObservationWithoutStoppingLivePreview() throws {
        let f = Fixture()
        f.store.startSpatialRecording()
        f.store.previewPlacement()
        f.clock.now += 0.5
        f.store.stopSpatialRecording()
        let before = try f.store.spatialRecordingData()
        #expect(f.store.spatialPreview != nil)
        #expect(String(decoding: before, as: UTF8.self).contains("recording-stopped"))
        f.store.applyPlacementPreview()
        #expect(try f.store.spatialRecordingData() == before)
        #expect(f.moves.count == 1)
        f.store.clearSpatialRecording()
        #expect(f.store.spatialRecordCount == 0)
    }

    @Test func dismissExpiryAndContextLossKeepDistinctRecordedOutcomes() throws {
        for expected in ["dismissed", "expired", "invalidated"] {
            let f = Fixture()
            f.store.startSpatialRecording()
            f.store.previewPlacement()
            if expected == "dismissed" { f.store.dismissPlacementPreview() }
            else if expected == "expired" { f.clock.now += 31; f.store.expirePlacementPreview() }
            else { f.store.invalidateTextSelection(reason: "Document scrolled") }
            f.store.stopSpatialRecording()
            let export = try #require(JSONSerialization.jsonObject(with: f.store.spatialRecordingData()) as? [String: Any])
            let rows = try #require(export["records"] as? [[String: Any]])
            let outcome = try #require(rows.first?["outcome"] as? [String: Any])
            #expect(outcome["kind"] as? String == expected)
        }
    }
}
