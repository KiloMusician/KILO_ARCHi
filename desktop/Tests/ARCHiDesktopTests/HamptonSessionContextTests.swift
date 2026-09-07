import XCTest
import CryptoKit
@testable import ARCHiDesktop

final class HamptonSessionContextTests: XCTestCase {
    func testCandidatesAreBoundedExactSpansWithSelectionPriority() throws {
        let question = String(repeating: "Question line with café 👨‍👩‍👧‍👦.\n", count: 70)
        let source = String(repeating: "Document line e\u{301} 🧭.\n", count: 90)
        let selectedRange = (source as NSString).range(of: "🧭")
        let selection = try XCTUnwrap(DocumentSelection(range: selectedRange, text: source, sourceRevision: 7))
        var bank = HamptonSessionContext()
        let candidates = bank.beginTurn(request: request(question, source: source, revision: 7, selection: selection))
        XCTAssertEqual(candidates.count, 24)
        XCTAssertEqual(Set(candidates.map(\.id)).count, candidates.count)
        XCTAssertTrue(candidates.contains { $0.kind == .document && $0.range == selectedRange })
        for candidate in candidates {
            let full = candidate.kind == .userQuestion ? question : source
            XCTAssertLessThanOrEqual(candidate.text.count, 360)
            XCTAssertLessThanOrEqual(candidate.text.utf8.count, 1_440)
            let exact = try XCTUnwrap(DocumentSelection(range: candidate.range, text: full,
                                                       sourceRevision: candidate.sourceRevision))
            XCTAssertTrue(exact.quote.utf8.elementsEqual(candidate.text.utf8))
            XCTAssertEqual(candidate.sourceDigest, digest(full))
        }
    }

    func testGraphemeLimitsPreserveBytesAndSkipAnOversizedCombiningCluster() throws {
        let text = String(repeating: "👨‍👩‍👧‍👦", count: 70) + " e\u{301}\r\n" + String(repeating: "字", count: 370)
        var bank = HamptonSessionContext()
        let candidates = bank.beginTurn(request: request(text))
        XCTAssertGreaterThan(candidates.count, 2)
        XCTAssertTrue(candidates.map(\.text).joined().utf8.elementsEqual(text.utf8))
        for candidate in candidates {
            XCTAssertLessThanOrEqual(candidate.text.count, 360)
            XCTAssertLessThanOrEqual(candidate.text.utf8.count, 1_440)
            XCTAssertNotNil(Range(candidate.range, in: text), "Candidate boundaries must preserve graphemes")
        }
        let oversized = "a" + String(repeating: "\u{301}", count: 800)
        let input = "Before\n" + oversized + "\nAfter"
        let bounded = bank.beginTurn(request: request(input))
        XCTAssertFalse(bounded.contains { $0.text.utf8.count > 1_440 })
        XCTAssertTrue(bounded.contains { $0.text == "After" })
        for candidate in bounded {
            let exact = try XCTUnwrap(DocumentSelection(range: candidate.range, text: input, sourceRevision: 0))
            XCTAssertTrue(exact.quote.utf8.elementsEqual(candidate.text.utf8))
        }
    }

    func testRetentionUsesOnlyCurrentIDsAndRejectsMixedOrForgedInputAtomically() throws {
        var bank = HamptonSessionContext()
        let candidates = bank.beginTurn(request: request("One\nTwo\nThree\nFour\nFive"))
        let first = try XCTUnwrap(candidates.first)
        XCTAssertThrowsError(try bank.retain(candidateIDs: [first.id, "invented"], candidates: candidates))
        XCTAssertThrowsError(try bank.retain(candidateIDs: [first.id, first.id], candidates: candidates))
        XCTAssertThrowsError(try bank.retain(candidateIDs: candidates.map(\.id), candidates: candidates))
        let forged = SessionContextCandidate(id: first.id, text: "A model-authored memory",
            kind: first.kind, sourceID: first.sourceID, sourceRevision: first.sourceRevision,
            sourceDigest: first.sourceDigest, range: first.range)
        XCTAssertThrowsError(try bank.retain(candidateIDs: [first.id], candidates: [forged] + Array(candidates.dropFirst())))
        XCTAssertTrue(bank.records.isEmpty)
        try bank.retain(candidateIDs: [], candidates: candidates)
        XCTAssertTrue(bank.records.isEmpty)
        try bank.retain(candidateIDs: [first.id], candidates: candidates)
        XCTAssertEqual(bank.records.map(\.text), [first.text])
        XCTAssertEqual(bank.records[0].range, first.range)
        XCTAssertEqual(bank.records[0].sourceDigest, first.sourceDigest)
    }

    func testPreviousTurnAndClearedSessionCandidatesCannotBeReused() throws {
        var bank = HamptonSessionContext()
        let input = request("Use short sentences.")
        let first = bank.beginTurn(request: input)
        let second = bank.beginTurn(request: input)
        XCTAssertNotEqual(first.map(\.id), second.map(\.id))
        XCTAssertThrowsError(try bank.retain(candidateIDs: first.map(\.id), candidates: first))
        bank.clear()
        XCTAssertEqual(bank.turn, 0)
        XCTAssertTrue(bank.records.isEmpty)
        let restarted = bank.beginTurn(request: input)
        XCTAssertNotEqual(first.map(\.id), restarted.map(\.id))
        XCTAssertThrowsError(try bank.retain(candidateIDs: second.map(\.id), candidates: second))
    }

    func testDeduplicationPreservesOriginalExpiryAndDistinguishesExactUnicodeBytes() throws {
        var bank = HamptonSessionContext()
        let decomposed = "Keep cafe\u{301}."
        var candidates = bank.beginTurn(request: request(decomposed))
        try bank.retain(candidateIDs: candidates.map(\.id), candidates: candidates)
        let original = try XCTUnwrap(bank.records.first)
        candidates = bank.beginTurn(request: request(decomposed))
        try bank.retain(candidateIDs: candidates.map(\.id), candidates: candidates)
        XCTAssertEqual(bank.records, [original])
        candidates = bank.beginTurn(request: request("Keep café."))
        try bank.retain(candidateIDs: candidates.map(\.id), candidates: candidates)
        XCTAssertEqual(bank.records.count, 2)
        XCTAssertFalse(bank.records[0].text.utf8.elementsEqual(bank.records[1].text.utf8))
    }

    func testUserAndDocumentExpiryUseTheirExactTurnBoundaries() throws {
        var bank = HamptonSessionContext()
        let candidates = bank.beginTurn(request: request("Keep replies brief.", source: "The launch is Tuesday."))
        try bank.retain(candidateIDs: candidates.map(\.id), candidates: candidates)
        XCTAssertEqual(bank.records.count, 2)
        for _ in 0..<15 { _ = bank.beginTurn(request: request("Follow up", source: "The launch is Tuesday.")) }
        XCTAssertEqual(bank.turn, 16)
        XCTAssertEqual(bank.records.count, 2)
        _ = bank.beginTurn(request: request("Follow up", source: "The launch is Tuesday."))
        XCTAssertEqual(bank.turn, 17)
        XCTAssertEqual(bank.records.map(\.kind), [.userQuestion])
        for _ in 0..<15 { _ = bank.beginTurn(request: request("Follow up", source: "The launch is Tuesday.")) }
        XCTAssertEqual(bank.turn, 32)
        XCTAssertEqual(bank.records.count, 1)
        _ = bank.beginTurn(request: request("Follow up", source: "The launch is Tuesday."))
        XCTAssertEqual(bank.turn, 33)
        XCTAssertTrue(bank.records.isEmpty)
    }

    func testChangingRevisionBytesNameOrStoppingSharingRevokesOnlyDocumentRecords() throws {
        let original = request("Use concise wording.", source: "A source statement.")
        let replacements = [
            request("Use concise wording.", source: "A source statement.", revision: 2),
            request("Use concise wording.", source: "Changed source bytes."),
            request("Use concise wording.", source: "A source statement.", name: "another.txt"),
            request("Use concise wording.")
        ]
        for replacement in replacements {
            var bank = HamptonSessionContext()
            let candidates = bank.beginTurn(request: original)
            try bank.retain(candidateIDs: candidates.map(\.id), candidates: candidates)
            bank.reconcileSource(request: replacement)
            XCTAssertEqual(bank.records.map(\.kind), [.userQuestion])
            XCTAssertThrowsError(try bank.retain(candidateIDs: candidates.map(\.id), candidates: candidates))
            XCTAssertTrue(bank.eligibleReminders(for: replacement).isEmpty, "Reconciliation requires a fresh turn")
        }
    }

    func testDocumentIdentityUsesExactBytesEvenAtTheSameRevision() throws {
        var bank = HamptonSessionContext()
        let original = request("Question", source: "cafe\u{301}")
        let candidates = bank.beginTurn(request: original)
        let document = try XCTUnwrap(candidates.first { $0.kind == .document })
        try bank.retain(candidateIDs: [document.id], candidates: candidates)
        bank.reconcileSource(request: request("Question", source: "café"))
        XCTAssertTrue(bank.records.isEmpty)
    }

    func testRemindersRequireEligibleIDsAndNONEChangesNothing() throws {
        var bank = HamptonSessionContext()
        let candidates = bank.beginTurn(request: request("First constraint\nSecond constraint\nThird constraint\nFourth constraint"))
        try bank.retain(candidateIDs: candidates.map(\.id), candidates: candidates)
        let followup = request("Please continue.")
        _ = bank.beginTurn(request: followup)
        let eligible = bank.eligibleReminders(for: followup)
        XCTAssertEqual(eligible.count, 4)
        XCTAssertThrowsError(try bank.useReminderIDs(eligible.map(\.id), eligible: eligible))
        XCTAssertThrowsError(try bank.useReminderIDs([eligible[0].id, eligible[0].id], eligible: eligible))
        XCTAssertThrowsError(try bank.useReminderIDs([eligible[0].id, "invented"], eligible: eligible))
        XCTAssertEqual(try bank.useReminderIDs([], eligible: eligible), [])
        XCTAssertTrue(bank.records.allSatisfy { $0.lastReminderTurn == nil })
        let selected = try bank.useReminderIDs([eligible[0].id, eligible[1].id], eligible: eligible)
        XCTAssertEqual(selected.map(\.id), [eligible[0].id, eligible[1].id])
        XCTAssertTrue(selected.allSatisfy { $0.lastReminderTurn == 2 })
        XCTAssertThrowsError(try bank.useReminderIDs([eligible[0].id], eligible: eligible))
        let remaining = bank.eligibleReminders(for: followup)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertThrowsError(try bank.useReminderIDs([eligible[0].id, remaining[0].id], eligible: remaining),
                             "Changing the group must not bypass a per-record cooldown")
    }

    func testReminderCooldownExcludesTheNextTwoFullTurns() throws {
        var bank = HamptonSessionContext()
        let candidates = bank.beginTurn(request: request("Keep the explanation brief."))
        try bank.retain(candidateIDs: candidates.map(\.id), candidates: candidates)
        let followup = request("What comes next?")
        _ = bank.beginTurn(request: followup)
        let eligible = bank.eligibleReminders(for: followup)
        _ = try bank.useReminderIDs(eligible.map(\.id), eligible: eligible)
        for expected in [3, 4] {
            _ = bank.beginTurn(request: followup)
            XCTAssertEqual(bank.turn, expected)
            XCTAssertTrue(bank.eligibleReminders(for: followup).isEmpty)
        }
        _ = bank.beginTurn(request: followup)
        XCTAssertEqual(bank.turn, 5)
        XCTAssertEqual(bank.eligibleReminders(for: followup).map(\.id), eligible.map(\.id))
    }

    func testVisibleTextSuppressionUsesExactUTF8AndRejectsDifferentRequestSnapshots() throws {
        var bank = HamptonSessionContext()
        let text = "cafe\u{301}"
        let firstRequest = request(text, source: "Document statement.")
        let candidates = bank.beginTurn(request: firstRequest)
        try bank.retain(candidateIDs: candidates.map(\.id), candidates: candidates)
        XCTAssertTrue(bank.eligibleReminders(for: firstRequest).isEmpty)
        var current = request("Explain café", source: "Document statement.")
        _ = bank.beginTurn(request: current)
        XCTAssertEqual(bank.eligibleReminders(for: current).map(\.text), [text])
        XCTAssertTrue(bank.eligibleReminders(for: request("A different question")).isEmpty)
        current = request("Explain " + text, source: "Document statement.")
        _ = bank.beginTurn(request: current)
        XCTAssertTrue(bank.eligibleReminders(for: current).isEmpty)
        current = request("Follow up", source: "Source includes " + text)
        _ = bank.beginTurn(request: current)
        XCTAssertTrue(bank.eligibleReminders(for: current).isEmpty)
    }

    func testBankPrunesOldestRecordsWithoutKeepingAHiddenHistory() throws {
        var bank = HamptonSessionContext()
        var originalIDs: [String] = []
        for turn in 1...9 {
            let text = (1...4).map { "Constraint \(turn).\($0)\n" }.joined()
            let candidates = bank.beginTurn(request: request(text))
            try bank.retain(candidateIDs: candidates.map(\.id), candidates: candidates)
            if turn == 1 { originalIDs = bank.records.map(\.id) }
            XCTAssertLessThanOrEqual(bank.records.count, 24)
        }
        XCTAssertEqual(bank.records.count, 24)
        XCTAssertEqual(bank.records.first?.createdTurn, 4)
        XCTAssertTrue(Set(originalIDs).isDisjoint(with: bank.records.map(\.id)))
    }

    func testTentativeCopiesAndSnapshotsDoNotMutateThePublishedBank() throws {
        var published = HamptonSessionContext()
        let candidates = published.beginTurn(request: request("A user constraint."))
        var tentative = published
        try tentative.retain(candidateIDs: candidates.map(\.id), candidates: candidates)
        XCTAssertTrue(published.records.isEmpty)
        published = tentative
        let snapshot = published.records
        let followup = request("Next question")
        _ = tentative.beginTurn(request: followup)
        let eligible = tentative.eligibleReminders(for: followup)
        _ = try tentative.useReminderIDs(eligible.map(\.id), eligible: eligible)
        tentative.clear()
        XCTAssertEqual(published.records, snapshot)
        XCTAssertEqual(published.turn, 1)
        XCTAssertNil(snapshot.first?.lastReminderTurn)
        XCTAssertTrue(tentative.records.isEmpty)
    }

    func testMalformedRequestsCannotMintCandidatesOrRetainOldOnes() throws {
        var bank = HamptonSessionContext()
        let valid = bank.beginTurn(request: request("Keep this"))
        let wrongSelection = try XCTUnwrap(DocumentSelection(range: NSRange(location: 0, length: 1),
            text: "A", sourceRevision: 9))
        let malformed = [
            request(String(repeating: "x", count: 16_001)),
            request("Question", source: String(repeating: "x", count: 100_001)),
            request("Question", source: "B", selection: wrongSelection),
            request("Question", selection: wrongSelection)
        ]
        for input in malformed {
            XCTAssertTrue(bank.beginTurn(request: input).isEmpty)
            XCTAssertThrowsError(try bank.retain(candidateIDs: valid.map(\.id), candidates: valid))
            XCTAssertTrue(bank.eligibleReminders(for: input).isEmpty)
        }
    }

    private func request(_ question: String, source: String? = nil, revision: UInt64 = 1,
                         name: String = "source.txt", selection: DocumentSelection? = nil) -> AssistantRequest {
        AssistantRequest(prompt: question, sourceName: source == nil ? nil : name, sourceText: source ?? "",
            sourceRevision: revision, placementRevision: 0, tone: "Calm", replyLength: 0.3, selection: selection)
    }

    private func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
