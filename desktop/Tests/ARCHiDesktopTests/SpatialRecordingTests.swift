import Foundation
import Testing
@testable import ARCHiDesktop

@MainActor
struct SpatialRecordingTests {
    @Test func recordingIsOptInAndExportRequiresStoppedNonemptyEvidence() throws {
        let recorder = SpatialRecorder()
        let preview = makePreview()
        recorder.capture(preview, now: 10)
        #expect(recorder.records.isEmpty)
        #expect(throws: SpatialRecordingError.self) { try recorder.exportData() }
        recorder.start()
        #expect(throws: SpatialRecordingError.self) { try recorder.exportData() }
        recorder.stop(now: 10)
        #expect(throws: SpatialRecordingError.self) { try recorder.exportData() }
        recorder.start()
        recorder.capture(preview, now: 10)
        #expect(throws: SpatialRecordingError.self) { try recorder.exportData() }
        recorder.stop(now: 11)
        #expect(try !recorder.exportData().isEmpty)
    }

    @Test func exportHasOnlyTheExactPrivacyAllowlist() throws {
        let recorder = SpatialRecorder()
        let preview = makePreview()
        recorder.start()
        recorder.capture(preview, now: 123_456.5)
        recorder.finish(previewID: preview.id, kind: .moved,
                        actualFrame: preview.candidate.frame, now: 123_457)
        recorder.stop(now: 123_457.25)
        let data = try recorder.exportData()
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(root.keys) == ["schema", "evidenceKind", "coordinateSpace", "plannerVersion", "limitReached", "records"])
        #expect(root["schema"] as? String == "archi-native-placement-recording/v1")
        #expect(root["evidenceKind"] as? String == "recorded-native")
        #expect(root["coordinateSpace"] as? String == "display-local-appkit-points-bottom-left")
        #expect(root["plannerVersion"] as? String == "native-placement/2")
        let records = try #require(root["records"] as? [[String: Any]])
        let record = try #require(records.first)
        #expect(Set(record.keys) == ["id", "startedMs", "endedMs", "scene", "proposal", "outcome"])
        #expect(record["id"] as? String == preview.id.uuidString)
        #expect(record["startedMs"] as? Int == 0)
        #expect(record["endedMs"] as? Int == 500)
        let scene = try #require(record["scene"] as? [String: Any])
        #expect(Set(scene.keys) == ["screen", "visibleDisplay", "viewport", "windowFrame", "companionFrame", "targets"])
        for name in ["screen", "visibleDisplay", "viewport", "windowFrame", "companionFrame"] {
            let rect = try #require(scene[name] as? [String: Any])
            #expect(Set(rect.keys) == ["x", "y", "width", "height"])
        }
        let targets = try #require(scene["targets"] as? [[String: Any]])
        #expect(targets.allSatisfy { Set($0.keys) == ["x", "y", "width", "height"] })
        let proposal = try #require(record["proposal"] as? [String: Any])
        let outcome = try #require(record["outcome"] as? [String: Any])
        #expect(Set(proposal.keys) == ["frame", "staysPut"])
        #expect(Set(outcome.keys) == ["kind", "actualFrame"])
        for rect in [proposal["frame"], outcome["actualFrame"]] {
            let object = try #require(rect as? [String: Any])
            #expect(Set(object.keys) == ["x", "y", "width", "height"])
        }
        let json = try #require(String(data: data, encoding: .utf8))
        for forbidden in ["PRIVATE_SOURCE_CANARY", "PRIVATE_REASON_CANARY", "sourceRevision", "screenID",
                          "windowNumber", "createdAt", "ticket", "range", "hash", "123456", "-1600"] {
            #expect(!json.contains(forbidden))
        }
    }

    @Test func everyRectangleAndActualOutcomeUsesTheSelectedDisplayOrigin() throws {
        let recorder = SpatialRecorder()
        let preview = makePreview()
        recorder.start()
        recorder.capture(preview, now: 50)
        recorder.finish(previewID: preview.id, kind: .unconfirmed,
                        actualFrame: preview.candidate.frame.offsetBy(dx: 0.5, dy: -0.25), now: 50.5)
        let record = try #require(recorder.records.first)
        let origin = preview.geometry.screenFrame.origin
        #expect(record.scene.screen.cgRect == CGRect(x: 0, y: 0, width: 1600, height: 1000))
        let pairs: [(SpatialRecordedRect, CGRect, Bool)] = [
            (record.scene.visibleDisplay, preview.environment.displays[0].visibleFrame, false),
            (record.scene.viewport, preview.geometry.viewport, false),
            (record.scene.windowFrame, preview.geometry.windowFrame, false),
            (record.scene.companionFrame, preview.environment.companionFrame, true),
            (record.scene.targets[0], preview.geometry.rects[0], false),
            (record.proposal.frame, preview.candidate.frame, true)
        ]
        for (normalized, original, preserveSize) in pairs {
            #expect(normalized.x == Double(original.minX - origin.x))
            #expect(normalized.y == Double(original.minY - origin.y))
            #expect(normalized.width == (preserveSize ? Double(original.width) : Double(original.maxX - origin.x) - normalized.x))
            #expect(normalized.height == (preserveSize ? Double(original.height) : Double(original.maxY - origin.y) - normalized.y))
        }
        #expect(record.outcome.actualFrame?.cgRect == record.proposal.frame.cgRect.offsetBy(dx: 0.5, dy: -0.25))
    }

    @Test func allTerminalOutcomesCloseExactlyOnceAndOmitAbsentActualFrame() throws {
        let recorder = SpatialRecorder()
        recorder.start()
        let kinds = SpatialRecordingOutcome.allCases.filter { $0 != .pending }
        for (index, kind) in kinds.enumerated() {
            let preview = makePreview(staysPut: kind == .stayed)
            let now = 10 + Double(index * 2)
            recorder.capture(preview, now: now)
            recorder.finish(previewID: preview.id, kind: .pending, now: now)
            #expect(recorder.records[index].endedMs == nil)
            recorder.finish(previewID: preview.id, kind: kind,
                actualFrame: kind == .moved || kind == .stayed ? preview.candidate.frame : nil, now: now + 0.5)
            let settled = recorder.records[index]
            recorder.finish(previewID: preview.id, kind: .moved, actualFrame: preview.candidate.frame, now: 0)
            #expect(recorder.records[index] == settled)
            #expect(settled.outcome.kind == kind)
            #expect(settled.endedMs == index * 2000 + 500)
        }
        recorder.stop(now: 100)
        let root = try #require(JSONSerialization.jsonObject(with: recorder.exportData()) as? [String: Any])
        let records = try #require(root["records"] as? [[String: Any]])
        for record in records {
            let outcome = try #require(record["outcome"] as? [String: Any])
            let hasActual = ["moved", "stayed"].contains(outcome["kind"] as? String ?? "")
            #expect(Set(outcome.keys) == (hasActual ? ["kind", "actualFrame"] : ["kind"]))
        }
    }

    @Test func inconsistentTerminalClaimsCannotBecomeRecordedOutcomes() throws {
        // Frame mode: 0 absent, 1 exact proposal, 2 observed mismatch.
        let invalidClaims: [(SpatialRecordingOutcome, Bool, Int)] = [
            (.moved, false, 0), (.moved, false, 2), (.moved, true, 1),
            (.stayed, true, 0), (.stayed, false, 1), (.stayed, true, 2),
            (.unconfirmed, false, 1), (.dismissed, false, 1),
            (.invalidated, false, 1), (.expired, false, 1), (.recordingStopped, false, 1)
        ]
        for (kind, staysPut, frameMode) in invalidClaims {
            let recorder = SpatialRecorder()
            let preview = makePreview(staysPut: staysPut)
            recorder.start()
            recorder.capture(preview, now: 10)
            let actual: CGRect? = frameMode == 0 ? nil
                : frameMode == 1 ? preview.candidate.frame : preview.candidate.frame.offsetBy(dx: 1, dy: 0)
            recorder.finish(previewID: preview.id, kind: kind, actualFrame: actual, now: 10.5)
            let result = try #require(recorder.records.first)
            #expect(!recorder.isRecording)
            #expect(result.outcome.kind == .recordingStopped)
            #expect(result.outcome.actualFrame == nil)
            #expect(result.endedMs == 500)
            #expect(try !recorder.exportData().isEmpty)
        }
    }

    @Test func stopClosesPendingAndStartPreservesStoppedEvidenceUntilClear() throws {
        let recorder = SpatialRecorder()
        recorder.start()
        let first = makePreview(), second = makePreview()
        recorder.capture(first, now: 20)
        recorder.start()
        recorder.capture(first, now: 21) // Duplicate capture cannot add or restart a record.
        recorder.capture(second, now: 21)
        recorder.stop(now: 21.5)
        #expect(recorder.records.count == 2)
        #expect(recorder.records.map(\.startedMs) == [0, 1000])
        #expect(recorder.records.allSatisfy { $0.endedMs == 1500 && $0.outcome.kind == .recordingStopped })
        let saved = try recorder.exportData()
        recorder.start()
        #expect(!recorder.isRecording)
        #expect(try recorder.exportData() == saved)
        recorder.clear()
        #expect(recorder.records.isEmpty)
        #expect(!recorder.limitReached)
        recorder.start()
        recorder.capture(makePreview(), now: 30)
        #expect(recorder.records.first?.startedMs == 0)
    }

    @Test func hundredthPreviewStopsCleanlyAndCannotOverwritePriorEvidence() throws {
        let recorder = SpatialRecorder()
        recorder.start()
        for index in 0..<100 {
            let preview = makePreview()
            recorder.capture(preview, now: 100 + Double(index))
            if index < 99 {
                recorder.finish(previewID: preview.id, kind: .dismissed, now: 100.25 + Double(index))
            }
        }
        #expect(!recorder.isRecording)
        #expect(recorder.limitReached)
        #expect(recorder.records.count == 100)
        #expect(recorder.records.dropLast().allSatisfy { $0.outcome.kind == .dismissed })
        #expect(recorder.records.last?.outcome.kind == .recordingStopped)
        #expect(recorder.records.last?.endedMs == 99_000)
        let saved = try recorder.exportData()
        recorder.capture(makePreview(), now: 201)
        recorder.start()
        #expect(try recorder.exportData() == saved)
        let root = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        #expect(root["limitReached"] as? Bool == true)
    }

    @Test func invalidBackwardOrUnboundedClockStopsAtLastAcceptedTime() throws {
        let invalidTimes: [TimeInterval] = [.nan, .infinity, -1, 10.75, 86_411]
        for invalidTime in invalidTimes {
            let recorder = SpatialRecorder()
            recorder.start()
            let first = makePreview(), second = makePreview()
            recorder.capture(first, now: 10)
            recorder.finish(previewID: first.id, kind: .dismissed, now: 10.5)
            recorder.capture(second, now: 11)
            recorder.finish(previewID: second.id, kind: .moved, now: invalidTime)
            #expect(!recorder.isRecording)
            #expect(recorder.records[0].endedMs == 500)
            #expect(recorder.records[1].startedMs == 1000)
            #expect(recorder.records[1].endedMs == 1000)
            #expect(recorder.records[1].outcome.kind == .recordingStopped)
            #expect(try !recorder.exportData().isEmpty)
        }
    }

    @Test func invalidCaptureOrStopClockCannotCreateAnEarlierEnd() {
        for invalidTime: TimeInterval in [.nan, .infinity, -1, 9] {
            let captureRecorder = SpatialRecorder()
            captureRecorder.start()
            captureRecorder.capture(makePreview(), now: 10)
            captureRecorder.capture(makePreview(), now: invalidTime)
            #expect(!captureRecorder.isRecording)
            #expect(captureRecorder.records.count == 1)
            #expect(captureRecorder.records[0].endedMs == 0)
            let stopRecorder = SpatialRecorder()
            stopRecorder.start()
            stopRecorder.capture(makePreview(), now: 10)
            stopRecorder.stop(now: invalidTime)
            #expect(!stopRecorder.isRecording)
            #expect(stopRecorder.records[0].endedMs == 0)
        }
    }

    @Test func elapsedTimeIsNonnegativeMonotonicAndBoundedAtOneDay() throws {
        let recorder = SpatialRecorder()
        recorder.start()
        let first = makePreview(), second = makePreview()
        recorder.capture(first, now: 1_000)
        recorder.finish(previewID: first.id, kind: .dismissed, now: 1_000.0001)
        recorder.capture(second, now: 1_000.0002)
        recorder.finish(previewID: second.id, kind: .expired, now: 87_400)
        recorder.stop(now: 87_400)
        #expect(recorder.records.map(\.startedMs) == [0, 0])
        #expect(recorder.records[0].endedMs == 0)
        #expect(recorder.records[1].endedMs == SpatialRecorder.maximumDurationMs)
        #expect(try !recorder.exportData().isEmpty)
    }

    @Test func malformedOrExcessiveGeometryStopsWithoutAppendingIt() {
        let badTargets = [[], [CGRect.zero], [CGRect.infinite], [CGRect.null],
            [CGRect(x: CGFloat.nan, y: 10, width: 20, height: 20)],
            [CGRect(x: -1300, y: 100, width: -20, height: 20)],
            [CGRect(x: -1550, y: 100, width: 20, height: 20)],
            [CGRect(x: 2_000_000, y: 10, width: 20, height: 20)],
            Array(repeating: CGRect(x: -1300, y: 100, width: 20, height: 20), count: 129)]
        for targets in badTargets {
            let recorder = SpatialRecorder()
            recorder.start()
            recorder.capture(makePreview(), now: 10)
            recorder.capture(makePreview(targets: targets), now: 11)
            #expect(!recorder.isRecording)
            #expect(recorder.records.count == 1)
            #expect(recorder.records[0].outcome.kind == .recordingStopped)
        }
    }

    @Test func missingDisplayOrInvalidActualFrameCannotEnterExport() throws {
        let recorder = SpatialRecorder()
        recorder.start()
        recorder.capture(makePreview(screenID: 999), now: 10)
        #expect(!recorder.isRecording)
        #expect(recorder.records.isEmpty)
        recorder.start()
        let preview = makePreview()
        recorder.capture(preview, now: 20)
        recorder.finish(previewID: preview.id, kind: .moved, actualFrame: .infinite, now: 20.5)
        #expect(!recorder.isRecording)
        #expect(recorder.records[0].outcome.kind == .recordingStopped)
        #expect(recorder.records[0].outcome.actualFrame == nil)
        #expect(try !recorder.exportData().isEmpty)
    }

    @Test func staysPutMustMatchTheObservedStartingFrame() {
        let recorder = SpatialRecorder()
        recorder.start()
        recorder.capture(makePreview(staysPut: true,
            candidateFrame: CGRect(x: -1450, y: 130, width: 128, height: 154)), now: 10)
        #expect(!recorder.isRecording)
        #expect(recorder.records.isEmpty)
    }

    @Test func excessiveGlobalCoordinatesCannotHideBehindLocalProjection() {
        let p = makePreview()
        func shifted(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: 2_000_000, dy: 0) }
        let g = p.geometry
        let preview = SpatialPreview(id: p.id, candidate: SpatialPlacementCandidate(
            frame: shifted(p.candidate.frame), reason: p.candidate.reason, staysPut: false),
            geometry: SelectedPassageGeometry(selection: g.selection, rects: g.rects.map(shifted),
                viewport: shifted(g.viewport), windowFrame: shifted(g.windowFrame),
                windowNumber: g.windowNumber, screenID: g.screenID, screenFrame: shifted(g.screenFrame)),
            environment: SpatialEnvironment(companionFrame: shifted(p.environment.companionFrame),
                displays: p.environment.displays.map { SpatialDisplay(id: $0.id,
                    frame: shifted($0.frame), visibleFrame: shifted($0.visibleFrame)) }),
            ticket: p.ticket, createdAt: p.createdAt)
        let recorder = SpatialRecorder()
        recorder.start()
        recorder.capture(preview, now: 10)
        #expect(!recorder.isRecording)
        #expect(recorder.records.isEmpty)
    }

    @Test func projectedLayoutEdgesPreserveExactBoundaryContact() throws {
        let base = makePreview()
        let screen = CGRect(x: -3840, y: 0, width: 1920, height: 1080)
        let target = CGRect(x: -3719.7, y: 400, width: 299.7, height: 20)
        let geometry = SelectedPassageGeometry(selection: base.geometry.selection, rects: [target],
            viewport: CGRect(x: -3740, y: 120, width: 320, height: 640),
            windowFrame: CGRect(x: -3740, y: 100, width: 320, height: 700),
            windowNumber: 1, screenID: 1, screenFrame: screen)
        let body = CGRect(x: target.midX - 64, y: 333, width: 128, height: 154)
        let candidate = try #require(SpatialPlacementPlanner.propose(geometry: geometry,
            companionFrame: body, visibleDisplay: screen))
        let recorder = SpatialRecorder()
        recorder.start()
        recorder.capture(SpatialPreview(id: UUID(), candidate: candidate, geometry: geometry,
            environment: SpatialEnvironment(companionFrame: body,
                displays: [SpatialDisplay(id: 1, frame: screen, visibleFrame: screen)]),
            ticket: base.ticket, createdAt: 10), now: 10)
        let record = try #require(recorder.records.first)
        #expect(record.scene.targets[0].cgRect.maxX == record.scene.viewport.cgRect.maxX)
        #expect(Double(record.scene.targets[0].cgRect.maxX + 12) == record.proposal.frame.x)
    }

    @Test func excessiveEncodedBytesAreRejectedWithoutLosingRecordedEvidence() {
        let recorder = SpatialRecorder()
        recorder.start()
        let targets = Array(repeating: CGRect(x: -1300.123456789123, y: 200.123456789123,
            width: 219.123456789123, height: 16.123456789123), count: SpatialRecorder.maximumTargets)
        for index in 0..<SpatialRecorder.maximumPreviews {
            recorder.capture(makePreview(targets: targets), now: 10 + Double(index))
        }
        #expect(recorder.records.count == 100)
        #expect(!recorder.isRecording)
        #expect(throws: SpatialRecordingError.exportTooLarge) { try recorder.exportData() }
        #expect(recorder.records.count == 100)
    }

    private func makePreview(targets: [CGRect]? = nil, screenID: UInt32 = 77,
                             staysPut: Bool = false, candidateFrame: CGRect? = nil) -> SpatialPreview {
        let screen = CGRect(x: -1600, y: -300, width: 1600, height: 1000)
        let selection = DocumentSelection(range: NSRange(location: 0, length: 8),
                                         text: "PRIVATE_SOURCE_CANARY", sourceRevision: 918_271)!
        let geometry = SelectedPassageGeometry(selection: selection,
            rects: targets ?? [CGRect(x: -1300.25, y: 200.25, width: 219.67, height: 16.7)],
            viewport: CGRect(x: -1350, y: -100, width: 700, height: 500),
            windowFrame: CGRect(x: -1400, y: -200, width: 1000, height: 800),
            windowNumber: 82_419, screenID: screenID, screenFrame: screen)
        let body = CGRect(x: -1200, y: 160, width: 128, height: 154)
        return SpatialPreview(id: UUID(), candidate: SpatialPlacementCandidate(
            frame: candidateFrame ?? (staysPut ? body : CGRect(x: -1450, y: 130, width: 128, height: 154)),
            reason: "PRIVATE_REASON_CANARY", staysPut: staysPut), geometry: geometry,
            environment: SpatialEnvironment(companionFrame: body,
                displays: [SpatialDisplay(id: 77, frame: screen, visibleFrame: screen.insetBy(dx: 0, dy: 20))]),
            ticket: ContextTicket(generation: 48, placement: 84, source: 918_271, selection: 94),
            createdAt: 123_456.5)
    }
}
