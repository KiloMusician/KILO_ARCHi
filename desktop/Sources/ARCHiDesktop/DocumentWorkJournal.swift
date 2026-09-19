import Foundation
import Combine
import CryptoKit
import Darwin

/// Authored check labels and booleans only. Callers must never put document or
/// model-response text into these metadata fields.
struct DocumentWorkAuditCheck: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var passed: Bool
}

/// Metadata for one provider's revision of one exact selected occurrence.
/// Digests identify bytes; they do not establish factual or semantic correctness.
struct DocumentWorkRecord: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        case proposing, ready, blocked, applying, applied, undoing, undone
        case dismissed, cancelled, failed

        var isActive: Bool { [.proposing, .ready, .applying, .undoing].contains(self) }
    }

    var id: String
    var requestID: String
    var provider: String
    var targetID: String
    var sourceDigest: String
    var sourceRevision: UInt64
    var selectionStart: Int
    var selectionLength: Int
    var mustBeShorter = false
    var preserveNumbersAndLinks = false
    var createdAt = Date()
    var updatedAt = Date()
    var state: State = .proposing
    var proposedDigest: String? = nil
    var expectedAfterDigest: String? = nil
    var actualAfterDigest: String? = nil
    var afterRevision: UInt64? = nil
    var checks: [DocumentWorkAuditCheck] = []
    /// Application-authored status only; never an excerpt or model explanation.
    var detail = ""
}

enum DocumentWorkJournalError: LocalizedError {
    case invalid(String)
    case changed
    case unreadable
    case full
    case locked

    var errorDescription: String? {
        switch self {
        case .invalid(let detail): return "Document work metadata is invalid: \(detail)"
        case .changed: return "Document work records changed outside this session. Reopen to review them before saving."
        case .unreadable: return "The document work journal could not be read. Its existing bytes were preserved."
        case .full: return "The document work journal has 64 active records. Finish or dismiss a task before starting another."
        case .locked: return "Another session is saving document work records. Try again after it finishes."
        }
    }
}

/// A profile sidecar, separate from model usage and companion memory. Loading
/// never rewrites it or replays an action. Saving uses a cooperative lock and an
/// exact fresh-disk baseline so a stale process cannot replace another writer.
@MainActor
final class DocumentWorkJournal: ObservableObject {
    @Published private(set) var records: [DocumentWorkRecord] = []
    @Published private(set) var loadError: String?
    private let url: URL
    private var baselineDigest: String?
    private var requiresRecovery = false
    static let maximumRecords = 64
    private static let maximumBytes = 1_048_576
    private static let schema = "archi-document-work/v1"

    private struct Archive: Codable {
        var schema: String
        var records: [DocumentWorkRecord]
    }

    init(url: URL) {
        self.url = url
        do {
            guard url.isFileURL else { throw DocumentWorkJournalError.unreadable }
            guard let bytes = try Self.readBounded(url) else { return }
            let archive = try Self.decode(bytes)
            baselineDigest = Self.digest(bytes)
            records = Self.sorted(archive.records.map(Self.interruptedProjection))
        } catch {
            requiresRecovery = true
            loadError = error.localizedDescription
        }
    }

    func save(_ record: DocumentWorkRecord) throws {
        guard !requiresRecovery else { throw DocumentWorkJournalError.unreadable }
        try Self.validate(record)
        var next = records
        if let index = next.firstIndex(where: { $0.id == record.id }) {
            try Self.validateUpdate(from: next[index], to: record)
            next[index] = record
        } else {
            guard record.state != .applied, record.state != .undone else {
                throw DocumentWorkJournalError.invalid("A completed mutation requires its earlier pending record.")
            }
            next.append(record)
        }
        next = Self.sorted(next)
        while next.count > Self.maximumRecords {
            guard let oldestTerminal = next.indices.reversed().first(where: {
                next[$0].id != record.id && !next[$0].state.isActive
            }) else { throw DocumentWorkJournalError.full }
            next.remove(at: oldestTerminal)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Archive(schema: Self.schema, records: next))
        guard bytes.count <= Self.maximumBytes else { throw DocumentWorkJournalError.invalid("Journal byte limit exceeded.") }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(url.appendingPathExtension("lock").path,
                                     O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw DocumentWorkJournalError.locked }
        defer { _ = Darwin.close(descriptor) }
        var information = stat()
        guard fstat(descriptor, &information) == 0, information.st_mode & S_IFMT == S_IFREG,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw DocumentWorkJournalError.locked }
        defer { _ = flock(descriptor, LOCK_UN) }
        let actual = try Self.readBounded(url).map(Self.digest)
        guard actual == baselineDigest else { throw DocumentWorkJournalError.changed }
        try bytes.write(to: url, options: [.atomic])
        baselineDigest = Self.digest(bytes)
        records = next
        loadError = nil
    }

    private static func interruptedProjection(_ original: DocumentWorkRecord) -> DocumentWorkRecord {
        var record = original
        switch record.state {
        case .proposing, .ready:
            record.state = .cancelled
            record.detail = "Interrupted before Apply. The proposal was not resumed; request a fresh revision."
        case .applying:
            record.state = .failed
            record.detail = "Interrupted during Apply. The resulting working copy is unverified; no action was replayed."
        case .undoing:
            record.state = .failed
            record.detail = "Interrupted during Undo. The resulting working copy is unverified; no action was replayed."
        default: break
        }
        return record
    }

    private static func sorted(_ records: [DocumentWorkRecord]) -> [DocumentWorkRecord] {
        records.sorted { first, second in
            first.createdAt == second.createdAt ? first.id < second.id : first.createdAt > second.createdAt
        }
    }

    private static func validateUpdate(from old: DocumentWorkRecord, to new: DocumentWorkRecord) throws {
        guard old.requestID == new.requestID, old.provider == new.provider, old.targetID == new.targetID,
              old.sourceDigest == new.sourceDigest, old.sourceRevision == new.sourceRevision,
              old.selectionStart == new.selectionStart, old.selectionLength == new.selectionLength,
              old.mustBeShorter == new.mustBeShorter, old.preserveNumbersAndLinks == new.preserveNumbersAndLinks,
              old.createdAt == new.createdAt, new.updatedAt >= old.updatedAt else {
            throw DocumentWorkJournalError.invalid("The bound request, target, requirements or time changed.")
        }
        if new.state == .applied {
            guard old.state == .applying || old.state == .applied else {
                throw DocumentWorkJournalError.invalid("Apply must retain its pending record before success.")
            }
        }
        if new.state == .undone {
            guard old.state == .undoing || old.state == .undone else {
                throw DocumentWorkJournalError.invalid("Undo must retain its pending record before success.")
            }
        }
        if [.applying, .applied, .undoing, .undone].contains(old.state) {
            guard old.proposedDigest == new.proposedDigest, old.expectedAfterDigest == new.expectedAfterDigest else {
                throw DocumentWorkJournalError.invalid("The dispatched proposal or expected result changed.")
            }
        }
    }

    private static func validate(_ record: DocumentWorkRecord) throws {
        guard metadata(record.id, limit: 384), metadata(record.requestID, limit: 128),
              metadata(record.provider, limit: 128), metadata(record.targetID, limit: 128),
              validDigest(record.sourceDigest),
              record.selectionStart >= 0, record.selectionStart <= 100_000,
              record.selectionLength > 0, record.selectionLength <= 100_000 - record.selectionStart,
              record.createdAt.timeIntervalSince1970.isFinite, record.updatedAt.timeIntervalSince1970.isFinite,
              record.updatedAt >= record.createdAt, record.detail.unicodeScalars.count <= 800,
              record.checks.count <= 24, Set(record.checks.map(\.id)).count == record.checks.count,
              record.checks.allSatisfy({ metadata($0.id, limit: 128) && metadata($0.title, limit: 160) }),
              [record.proposedDigest, record.expectedAfterDigest, record.actualAfterDigest].compactMap({ $0 }).allSatisfy(validDigest),
              record.afterRevision.map({ $0 > record.sourceRevision }) ?? true else {
            throw DocumentWorkJournalError.invalid("Identity, digest, selection, timestamp or field bounds failed.")
        }
        if record.state == .applied {
            guard let expected = record.expectedAfterDigest, let actual = record.actualAfterDigest,
                  expected == actual, record.afterRevision != nil else {
                throw DocumentWorkJournalError.invalid("Applied state requires the matching observed result and revision.")
            }
        }
    }

    private static func metadata(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.unicodeScalars.count <= limit
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func validDigest(_ value: String) -> Bool {
        let raw = value.hasPrefix("sha256:") ? String(value.dropFirst(7)) : value
        return raw.utf8.count == 64 && raw.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func decode(_ data: Data) throws -> Archive {
        var scanner = UniqueJSONKeys(bytes: Array(data))
        try scanner.validate()
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schema", "records"], let rows = object["records"] as? [[String: Any]],
              rows.count <= maximumRecords else { throw DocumentWorkJournalError.unreadable }
        let fields: Set<String> = ["id", "requestID", "provider", "targetID", "sourceDigest", "sourceRevision",
            "selectionStart", "selectionLength", "mustBeShorter", "preserveNumbersAndLinks", "createdAt", "updatedAt",
            "state", "proposedDigest", "expectedAfterDigest", "actualAfterDigest", "afterRevision", "checks", "detail"]
        guard rows.allSatisfy({ row in
            guard Set(row.keys).isSubset(of: fields), let checks = row["checks"] as? [[String: Any]] else { return false }
            return checks.allSatisfy { Set($0.keys) == ["id", "title", "passed"] }
        }) else { throw DocumentWorkJournalError.unreadable }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.schema == schema, Set(archive.records.map(\.id)).count == archive.records.count else {
            throw DocumentWorkJournalError.unreadable
        }
        for record in archive.records { try validate(record) }
        return archive
    }

    private static func readBounded(_ url: URL) throws -> Data? {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw DocumentWorkJournalError.unreadable
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0, information.st_mode & S_IFMT == S_IFREG,
              information.st_size >= 0, information.st_size <= maximumBytes else { throw DocumentWorkJournalError.unreadable }
        var bytes = Data()
        while bytes.count <= maximumBytes {
            guard let part = try handle.read(upToCount: maximumBytes + 1 - bytes.count), !part.isEmpty else { break }
            bytes.append(part)
        }
        guard bytes.count <= maximumBytes else { throw DocumentWorkJournalError.unreadable }
        return bytes
    }

    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
