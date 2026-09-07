import Foundation

enum SpatialRecordingOutcome: String, Codable, CaseIterable {
    case pending, moved, stayed, dismissed, invalidated, expired, unconfirmed
    case recordingStopped = "recording-stopped"
}

struct SpatialRecordedRect: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct SpatialRecordedScene: Codable, Equatable {
    let screen: SpatialRecordedRect
    let visibleDisplay: SpatialRecordedRect
    let viewport: SpatialRecordedRect
    let windowFrame: SpatialRecordedRect
    let companionFrame: SpatialRecordedRect
    let targets: [SpatialRecordedRect]
}

struct SpatialRecordedProposal: Codable, Equatable {
    let frame: SpatialRecordedRect
    let staysPut: Bool
}

struct SpatialRecordedResult: Codable, Equatable {
    let kind: SpatialRecordingOutcome
    let actualFrame: SpatialRecordedRect?
}

struct SpatialRecordedPreview: Codable, Equatable {
    let id: UUID
    let startedMs: Int
    var endedMs: Int?
    let scene: SpatialRecordedScene
    let proposal: SpatialRecordedProposal
    var outcome: SpatialRecordedResult
}

enum SpatialRecordingError: Error, LocalizedError, Equatable {
    case recordingInProgress, noRecords, unfinishedRecords, exportTooLarge

    var errorDescription: String? {
        switch self {
        case .recordingInProgress: "Stop recording before exporting."
        case .noRecords: "Record at least one placement preview before exporting."
        case .unfinishedRecords: "The recording contains an unfinished preview."
        case .exportTooLarge: "This recording exceeds the 1 MiB export limit. Record a shorter session."
        }
    }
}

/// Opt-in, memory-only evidence. The encoded types deliberately have no text,
/// source identity, global display origin, absolute clock, or free-form fields.
@MainActor
final class SpatialRecorder {
    static let maximumPreviews = 100
    static let maximumTargets = 128
    static let maximumDurationMs = 86_400_000
    static let maximumCoordinate = SpatialProjection.maximumCoordinate
    static let maximumExportBytes = 1_048_576

    private(set) var isRecording = false
    private(set) var limitReached = false
    private(set) var records: [SpatialRecordedPreview] = []
    private var beganAt: TimeInterval?
    private var lastAcceptedTime: TimeInterval?
    private var lastAcceptedMs = 0
    // Only pending outcomes need this private normalization origin.
    private var pendingOrigins: [UUID: CGPoint] = [:]

    /// A stopped recording is preserved until clear() explicitly discards it.
    func start() {
        guard !isRecording, records.isEmpty else { return }
        isRecording = true
        limitReached = false
        beganAt = nil
        lastAcceptedTime = nil
        lastAcceptedMs = 0
        pendingOrigins = [:]
    }

    func stop(now: TimeInterval) {
        guard isRecording else { return }
        if beganAt != nil { _ = acceptTime(now) }
        closePendingAndStop()
    }

    func clear() {
        isRecording = false
        limitReached = false
        records = []
        pendingOrigins = [:]
        beganAt = nil
        lastAcceptedTime = nil
        lastAcceptedMs = 0
    }

    func capture(_ preview: SpatialPreview, now: TimeInterval) {
        guard isRecording, !records.contains(where: { $0.id == preview.id }) else { return }
        guard let normalized = normalize(preview), let milliseconds = acceptTime(now) else {
            closePendingAndStop()
            return
        }
        records.append(SpatialRecordedPreview(
            id: preview.id, startedMs: milliseconds, endedMs: nil,
            scene: normalized.scene, proposal: normalized.proposal,
            outcome: SpatialRecordedResult(kind: .pending, actualFrame: nil)))
        pendingOrigins[preview.id] = preview.geometry.screenFrame.origin
        if records.count == Self.maximumPreviews {
            limitReached = true
            closePendingAndStop()
        }
    }

    func finish(previewID: UUID, kind: SpatialRecordingOutcome,
                actualFrame: CGRect? = nil, now: TimeInterval) {
        guard isRecording, kind != .pending,
              let index = records.firstIndex(where: { $0.id == previewID && $0.outcome.kind == .pending }),
              let origin = pendingOrigins[previewID] else { return }
        guard let milliseconds = acceptTime(now) else {
            closePendingAndStop()
            return
        }
        var normalizedActual: SpatialRecordedRect?
        if let actualFrame {
            guard let rect = SpatialProjection.actionFrame(actualFrame, origin: origin) else {
                closePendingAndStop()
                return
            }
            normalizedActual = rect
        }
        guard Self.validOutcome(kind, actual: normalizedActual, record: records[index]) else {
            closePendingAndStop()
            return
        }
        records[index].endedMs = milliseconds
        records[index].outcome = SpatialRecordedResult(kind: kind, actualFrame: normalizedActual)
        pendingOrigins.removeValue(forKey: previewID)
    }

    func exportData() throws -> Data {
        guard !isRecording else { throw SpatialRecordingError.recordingInProgress }
        guard !records.isEmpty else { throw SpatialRecordingError.noRecords }
        guard records.allSatisfy({ $0.outcome.kind != .pending && $0.endedMs != nil }) else {
            throw SpatialRecordingError.unfinishedRecords
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Export(limitReached: limitReached, records: records))
        guard data.count <= Self.maximumExportBytes else { throw SpatialRecordingError.exportTooLarge }
        return data
    }

    private struct Export: Encodable {
        let schema = "archi-native-placement-recording/v1"
        let evidenceKind = "recorded-native"
        let coordinateSpace = "display-local-appkit-points-bottom-left"
        let plannerVersion = SpatialPlacementPlanner.version
        let limitReached: Bool
        let records: [SpatialRecordedPreview]
    }

    private func acceptTime(_ now: TimeInterval) -> Int? {
        guard now.isFinite, now >= 0,
              lastAcceptedTime.map({ now >= $0 }) ?? true else { return nil }
        let start = beganAt ?? now
        let elapsedMs = (now - start) * 1000
        guard elapsedMs.isFinite, elapsedMs >= 0,
              elapsedMs <= Double(Self.maximumDurationMs) else { return nil }
        let milliseconds = Int(elapsedMs.rounded(.down))
        guard milliseconds >= lastAcceptedMs else { return nil }
        beganAt = start
        lastAcceptedTime = now
        lastAcceptedMs = milliseconds
        return milliseconds
    }

    private func closePendingAndStop() {
        for index in records.indices where records[index].outcome.kind == .pending {
            records[index].endedMs = max(records[index].startedMs, lastAcceptedMs)
            records[index].outcome = SpatialRecordedResult(kind: .recordingStopped, actualFrame: nil)
        }
        isRecording = false
        pendingOrigins = [:]
        beganAt = nil
        lastAcceptedTime = nil
    }

    private static func validOutcome(_ kind: SpatialRecordingOutcome, actual: SpatialRecordedRect?,
                                     record: SpatialRecordedPreview) -> Bool {
        switch kind {
        case .moved:
            !record.proposal.staysPut && actual == record.proposal.frame
        case .stayed:
            record.proposal.staysPut && record.proposal.frame == record.scene.companionFrame
                && actual == record.proposal.frame
        case .unconfirmed:
            actual == nil || actual != record.proposal.frame
        case .dismissed, .invalidated, .expired, .recordingStopped:
            actual == nil
        case .pending:
            false
        }
    }

    private func normalize(_ preview: SpatialPreview) -> (scene: SpatialRecordedScene, proposal: SpatialRecordedProposal)? {
        let geometry = preview.geometry
        let matchingDisplays = preview.environment.displays.filter { $0.id == geometry.screenID }
        guard matchingDisplays.count == 1, let display = matchingDisplays.first,
              display.frame == geometry.screenFrame,
              !geometry.rects.isEmpty, geometry.rects.count <= Self.maximumTargets,
              preview.candidate.staysPut == (preview.candidate.frame == preview.environment.companionFrame),
              let scene = SpatialProjection.scene(geometry: geometry,
                  companionFrame: preview.environment.companionFrame, visibleDisplay: display.visibleFrame),
              let frame = SpatialProjection.actionFrame(preview.candidate.frame,
                  origin: geometry.screenFrame.origin) else { return nil }
        return (scene, SpatialRecordedProposal(frame: frame, staysPut: preview.candidate.staysPut))
    }
}
