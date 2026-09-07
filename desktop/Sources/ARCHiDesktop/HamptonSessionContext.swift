import Foundation
import CryptoKit

enum SessionContextKind: String, Sendable { case userQuestion, document }

/// An app-created exact span. Source references are advisory, not verified facts.
struct SessionContextCandidate: Equatable, Sendable, Identifiable {
    let id: String
    let text: String
    let kind: SessionContextKind
    let sourceID: String
    let sourceRevision: UInt64
    let sourceDigest: String
    let range: NSRange

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.text.utf8.elementsEqual(rhs.text.utf8)
            && lhs.kind == rhs.kind && lhs.sourceID == rhs.sourceID
            && lhs.sourceRevision == rhs.sourceRevision && lhs.sourceDigest == rhs.sourceDigest
            && lhs.range == rhs.range
    }
}

struct SessionContextRecord: Equatable, Sendable, Identifiable {
    let id: String
    let text: String
    let kind: SessionContextKind
    let sourceID: String
    let sourceRevision: UInt64
    let sourceDigest: String
    let range: NSRange
    let createdTurn: Int
    let expiresAtTurn: Int
    fileprivate(set) var lastReminderTurn: Int?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.text.utf8.elementsEqual(rhs.text.utf8)
            && lhs.kind == rhs.kind && lhs.sourceID == rhs.sourceID
            && lhs.sourceRevision == rhs.sourceRevision && lhs.sourceDigest == rhs.sourceDigest
            && lhs.range == rhs.range && lhs.createdTurn == rhs.createdTurn
            && lhs.expiresAtTurn == rhs.expiresAtTurn && lhs.lastReminderTurn == rhs.lastReminderTurn
    }
}

enum SessionContextError: Error, Equatable {
    case staleCandidates, invalidCandidateIDs, staleReminders, invalidReminderIDs
}

/// Value semantics permit tentative role work; the owner publishes only a current,
/// completed turn. No persistence, inferred facts, or generated record text enters here.
/// Only active records are kept; expiry, revocation, and oldest-first pruning erase text.
struct HamptonSessionContext: Sendable {
    static let maximumCandidates = 24
    static let maximumCandidateCharacters = 360
    static let maximumCandidateBytes = 1_440
    static let maximumRecords = 24
    static let maximumRetainedPerTurn = 4
    static let maximumReminders = 3
    static let reminderCooldownTurns = 2
    static let userLifetimeTurns = 32
    static let documentLifetimeTurns = 16

    private(set) var turn = 0
    private(set) var records: [SessionContextRecord] = []
    private var sessionID = UUID().uuidString
    private var candidates: [SessionContextCandidate] = []
    private var requestIdentity: RequestIdentity?
    private var sourceID: String?
    private var visibleRecordIDs = Set<String>()

    mutating func beginTurn(request: AssistantRequest) -> [SessionContextCandidate] {
        // A practical lifetime cannot reach this boundary, but never wrap a freshness counter.
        if turn >= Int.max - Self.userLifetimeTurns { clear() }
        turn += 1
        reconcileSource(request: request)
        let currentTurn = turn
        records.removeAll { $0.expiresAtTurn <= currentTurn }
        candidates = []
        requestIdentity = nil
        visibleRecordIDs = []
        guard Self.valid(request) else { return [] }
        requestIdentity = RequestIdentity(request)
        visibleRecordIDs = Set(records.filter { Self.visible($0.text, in: request) }.map(\.id))

        let questionDigest = Self.digest(request.prompt)
        appendSpans(request.prompt, offset: 0, kind: .userQuestion,
                    sourceID: "question-" + questionDigest, revision: 0, digest: questionDigest,
                    limit: request.sourceName == nil ? Self.maximumCandidates : 8)
        if let sourceID {
            let digest = Self.digest(request.sourceText)
            if let selection = request.selection {
                appendSpans(selection.quote, offset: selection.range.location, kind: .document,
                            sourceID: sourceID, revision: request.sourceRevision, digest: digest,
                            limit: min(candidates.count + 8, Self.maximumCandidates))
            }
            appendSpans(request.sourceText, offset: 0, kind: .document, sourceID: sourceID,
                        revision: request.sourceRevision, digest: digest, limit: Self.maximumCandidates,
                        excluding: request.selection?.range)
        }
        return candidates
    }

    /// The complete app-produced candidate snapshot must still match. Invalid mixed
    /// selections fail atomically; the caller cannot supply a replacement span or text.
    mutating func retain(candidateIDs: [String], candidates supplied: [SessionContextCandidate]) throws {
        guard requestIdentity != nil, supplied == candidates else { throw SessionContextError.staleCandidates }
        guard Self.unique(candidateIDs, maximum: Self.maximumRetainedPerTurn),
              candidateIDs.allSatisfy({ id in candidates.contains { $0.id == id } }) else {
            throw SessionContextError.invalidCandidateIDs
        }
        for id in candidateIDs {
            let candidate = candidates.first { $0.id == id }!
            // The same user text does not gain a second slot or an extended expiry.
            // Documents additionally retain their exact source identity.
            guard !records.contains(where: {
                $0.kind == candidate.kind && $0.text.utf8.elementsEqual(candidate.text.utf8)
                    && (candidate.kind == .userQuestion || $0.sourceID == candidate.sourceID)
            }) else { continue }
            let record = SessionContextRecord(id: "memory-" + String(candidate.id.dropFirst("candidate-".count)),
                text: candidate.text, kind: candidate.kind, sourceID: candidate.sourceID,
                sourceRevision: candidate.sourceRevision, sourceDigest: candidate.sourceDigest,
                range: candidate.range, createdTurn: turn,
                expiresAtTurn: turn + (candidate.kind == .userQuestion ? Self.userLifetimeTurns : Self.documentLifetimeTurns),
                lastReminderTurn: nil)
            records.append(record)
            visibleRecordIDs.insert(record.id)
        }
        if records.count > Self.maximumRecords { records.removeFirst(records.count - Self.maximumRecords) }
        visibleRecordIDs.formIntersection(Set(records.map(\.id)))
    }

    func eligibleReminders(for request: AssistantRequest) -> [SessionContextRecord] {
        guard Self.valid(request), requestIdentity == RequestIdentity(request) else { return [] }
        return eligibleRecords
    }

    /// Empty IDs mean NONE. The eligible projection and selected IDs must both be
    /// current; last-use bookkeeping is checked per record, not per selected group.
    mutating func useReminderIDs(_ ids: [String], eligible: [SessionContextRecord]) throws -> [SessionContextRecord] {
        guard requestIdentity != nil, eligible == eligibleRecords else { throw SessionContextError.staleReminders }
        guard Self.unique(ids, maximum: Self.maximumReminders),
              ids.allSatisfy({ id in eligible.contains { $0.id == id } }) else {
            throw SessionContextError.invalidReminderIDs
        }
        var selected: [SessionContextRecord] = []
        for id in ids {
            let index = records.firstIndex { $0.id == id }!
            records[index].lastReminderTurn = turn
            selected.append(records[index])
        }
        return selected
    }

    /// Call synchronously when sharing changes, independently of model turn success.
    /// Name, revision, and exact UTF-8 digest define one shared-copy identity.
    mutating func reconcileSource(request: AssistantRequest) {
        let next = Self.documentSourceID(request)
        records.removeAll { $0.kind == .document && $0.sourceID != next }
        guard next != sourceID else { return }
        sourceID = next
        candidates = []
        requestIdentity = nil
        visibleRecordIDs = []
    }

    mutating func clear() { self = Self() }

    private var eligibleRecords: [SessionContextRecord] {
        records.filter {
            $0.expiresAtTurn > turn && !visibleRecordIDs.contains($0.id)
                && ($0.kind == .userQuestion || $0.sourceID == sourceID)
                && ($0.lastReminderTurn.map { turn - $0 > Self.reminderCooldownTurns } ?? true)
        }.sorted {
            $0.createdTurn != $1.createdTurn ? $0.createdTurn > $1.createdTurn : $0.id < $1.id
        }
    }

    private mutating func appendSpans(_ text: String, offset: Int, kind: SessionContextKind,
                                      sourceID: String, revision: UInt64, digest: String,
                                      limit: Int, excluding: NSRange? = nil) {
        var start = text.startIndex, end = start, characters = 0, bytes = 0, location = offset
        func append(_ lower: String.Index, _ upper: String.Index, at location: Int) {
            guard lower < upper, candidates.count < limit else { return }
            let span = String(text[lower..<upper]), range = NSRange(location: location, length: span.utf16.count)
            guard !span.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  excluding.map({ NSIntersectionRange($0, range).length == 0 }) ?? true else { return }
            let key = "\(sessionID)/\(turn)/\(sourceID)/\(range.location)/\(range.length)"
            candidates.append(SessionContextCandidate(id: "candidate-" + Self.digest(key), text: span,
                kind: kind, sourceID: sourceID, sourceRevision: revision, sourceDigest: digest, range: range))
        }
        while end < text.endIndex && candidates.count < limit {
            let next = text.index(after: end), character = String(text[end..<next]), count = character.utf8.count
            if characters == Self.maximumCandidateCharacters || bytes + count > Self.maximumCandidateBytes {
                append(start, end, at: location)
                location += text[start..<end].utf16.count
                start = end; characters = 0; bytes = 0
            }
            // An unbounded combining sequence is one Swift Character. Omit that
            // whole grapheme rather than split it or exceed the encoded-text bound.
            if count > Self.maximumCandidateBytes {
                location += character.utf16.count; start = next; end = next
                continue
            }
            end = next; characters += 1; bytes += count
            if character.contains("\n") || character.contains("\r") {
                append(start, end, at: location)
                location += text[start..<end].utf16.count
                start = end; characters = 0; bytes = 0
            }
        }
        append(start, end, at: location)
    }

    private static func unique(_ ids: [String], maximum: Int) -> Bool {
        ids.count <= maximum && Set(ids).count == ids.count
    }

    private static func valid(_ request: AssistantRequest) -> Bool {
        request.prompt.utf8.count <= 16_000 && request.sourceText.utf8.count <= 100_000
            && request.hasValidSelection
    }

    private static func visible(_ text: String, in request: AssistantRequest) -> Bool {
        let bytes = Data(text.utf8)
        return Data(request.prompt.utf8).range(of: bytes) != nil
            || (request.sourceName != nil && Data(request.sourceText.utf8).range(of: bytes) != nil)
    }

    private static func documentSourceID(_ request: AssistantRequest) -> String? {
        guard let name = request.sourceName else { return nil }
        return "document-" + digest(digest(name) + "/" + String(request.sourceRevision) + "/" + digest(request.sourceText))
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct RequestIdentity: Equatable, Sendable {
        let questionDigest: String
        let documentID: String?
        let placementRevision: UInt64
        let selection: DocumentSelection?
        let tone: String
        let replyLength: Double

        init(_ request: AssistantRequest) {
            questionDigest = HamptonSessionContext.digest(request.prompt)
            documentID = HamptonSessionContext.documentSourceID(request)
            placementRevision = request.placementRevision
            selection = request.selection
            tone = request.tone
            replyLength = request.replyLength
        }
    }
}
