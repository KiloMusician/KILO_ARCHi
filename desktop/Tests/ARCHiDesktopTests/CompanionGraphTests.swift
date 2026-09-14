import XCTest
import Foundation
@testable import ARCHiDesktop

final class CompanionGraphTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private let lessonID = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"

    func testCompareAndRollingConversationReferencesAreRequestScoped() {
        var first = receipt(id: "first", provider: .qwen)
        first.evidence = evidence(sources: ["conversation-1"])
        first.localConversationDigest = String(repeating: "a", count: 64)
        var second = receipt(id: "second", provider: .qwen)
        second.evidence = evidence(sources: ["conversation-1"])
        second.localConversationDigest = String(repeating: "b", count: 64)
        let external = receipt(id: "first", provider: .codex)
        let graph = build([first, external, second])
        let requests = graph.nodes.filter { $0.kind == .request }
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(Set(requests.map(\.id)).count, 3)
        XCTAssertEqual(requests.filter { $0.details.contains(.init(label: "Provider", value: "Codex")) }.count, 1)
        let references = graph.nodes.filter { $0.subtitle == "conversation-1" }
        XCTAssertEqual(references.count, 2)
        XCTAssertNotEqual(references[0].id, references[1].id)
        XCTAssertEqual(Set(graph.nodes.map(\.id)).count, graph.nodes.count)
    }

    func testPreparedAndOmittedInputsDoNotBecomeDispatchedCalls() {
        var pending = receipt(id: "prepared", provider: .qwen, state: .pending)
        pending.requestStarted = false
        var details = AssistantEvidenceReceipt(contextEnabled: true)
        details.sourceIDsAvailable = ["current-question"]
        details.reasoningSourceIDsOffered = ["current-question"]
        details.omissions = [.init(kind: .candidates, reason: .budget, ids: ["candidate-not-sent"], count: 1)]
        pending.evidence = details
        let graph = build([pending])
        XCTAssertTrue(graph.edges.contains { $0.label == "prepared for" })
        XCTAssertFalse(graph.edges.contains { $0.label.contains("dispatched") })
        XCTAssertFalse(graph.nodes.contains { $0.kind == .invocation })
        let omission = graph.nodes.first { $0.kind == .omission }
        XCTAssertEqual(omission?.status, "Omitted")
        XCTAssertTrue(omission?.details.contains(.init(label: "Reason", value: "budget")) == true)
        XCTAssertEqual(graph.nodes.first { $0.kind == .answer }?.status, "Not delivered")
    }

    func testReceivedModelResponseDoesNotReviveStoppedAnswer() {
        var stopped = receipt(id: "stopped", provider: .qwen, state: .cancelled)
        stopped.localInvocationReceipts = [HamptonInvocationReceipt(id: "local-call", role: .reasoning,
            inputDigest: "input", systemDigest: "system", schemaDigest: "schema", outcome: .completed)]
        // Cancellation may retain earlier evidence. Lane outcome has precedence.
        stopped.admissionOutcome = .init(status: .accepted, stage: .publication, role: .reasoning, requestID: "local-call", reason: nil)
        let graph = build([stopped])
        XCTAssertEqual(graph.nodes.first { $0.kind == .answer }?.status, "Stopped")
        XCTAssertEqual(graph.nodes.first { $0.kind == .invocation }?.status, "Response received")
        XCTAssertEqual(graph.nodes.first { $0.kind == .invocation }?.target, .advanced)
        XCTAssertFalse(graph.nodes.contains { $0.kind == .answer && $0.status == "Response checks passed" })
    }

    func testHistoricalSourceCannotJoinAChangedCopyOrCopyItsText() {
        var old = receipt(id: "old-source", provider: .qwen)
        old.sourceDigest = LessonSource.digest(of: "old private source body")
        old.evidence = evidence(sources: ["shared-copy"])
        let changed = CompanionGraphSource(name: "notes.txt", text: "new private source body", revision: 1)
        let graph = build([old], source: changed)
        XCTAssertTrue(graph.nodes.contains { $0.title == "shared-copy" && $0.status == "Source unavailable" })
        XCTAssertFalse(graph.edges.contains { $0.label == "same captured copy" })
        XCTAssertFalse(strings(graph).contains("old private source body"))
        XCTAssertFalse(strings(graph).contains("new private source body"))

        old.sourceDigest = LessonSource.digest(of: changed.text)
        let same = build([old], source: changed)
        XCTAssertTrue(same.edges.contains { $0.label == "same captured copy" })
        let wrongRevision = CompanionGraphSource(name: changed.name, text: changed.text, revision: 2)
        XCTAssertFalse(build([old], source: wrongRevision).edges.contains { $0.label == "same captured copy" })
    }

    func testQuestionDigestIsTheRequestInputAndCopyDigestRemainsSeparate() {
        var answer = receipt(id: "different-digests", provider: .qwen)
        answer.sourceDigest = String(repeating: "b", count: 64)
        answer.evidence = evidence(sources: ["current-question", "shared-copy"])
        let graph = build([answer])
        let question = graph.nodes.first { $0.title == "current-question" }
        XCTAssertTrue(question?.details.contains(.init(label: "Request input digest", value: answer.inputDigest)) == true)
        XCTAssertFalse(question?.details.contains { $0.value == answer.sourceDigest } == true)
        let copy = graph.nodes.first { $0.title == "shared-copy" }
        XCTAssertTrue(copy?.details.contains(.init(label: "Source copy digest", value: answer.sourceDigest!)) == true)
    }

    func testDuplicateOmissionMetadataAcrossEvidenceAndLaneDrawsOnlyOnce() {
        var answer = receipt(id: "duplicate-omission", provider: .qwen)
        let omission = AssistantEvidenceOmission(kind: .lessons, reason: .budget, ids: [lessonID], count: 1)
        var details = AssistantEvidenceReceipt(contextEnabled: true)
        details.omissions = [omission]
        answer.evidence = details
        let once = build([answer])
        answer.localLessonOmissions = [omission]
        XCTAssertEqual(build([answer]), once)
        answer.localLessonOmissions.append(.init(kind: .lessons, reason: .budget, ids: [lessonID], count: nil))
        XCTAssertEqual(build([answer]).nodes.filter { $0.kind == .omission }.count, 2)
    }

    func testCurrentLessonAndCapturedReferenceRemainSeparateAcrossRevisionAndWithdrawal() {
        let original = lesson(text: "old private lesson words")
        var answer = receipt(id: "lesson-answer", provider: .qwen)
        answer.localLessons = [LessonSnapshot(lesson: original)]
        answer.evidence = evidence(memories: [answer.localLessons[0].modelID])
        let revised = lesson(text: "new current lesson words", revision: 2)
        let revisionGraph = build([answer], lessons: [revised])
        XCTAssertTrue(strings(revisionGraph).contains(revised.text))
        XCTAssertFalse(strings(revisionGraph).contains(original.text))
        XCTAssertTrue(revisionGraph.nodes.contains { $0.status == "Earlier revision" })
        XCTAssertFalse(revisionGraph.edges.contains { $0.label == "same kept version" })
        let removed = build([answer])
        XCTAssertFalse(strings(removed).contains(original.text))
        XCTAssertTrue(removed.nodes.contains { $0.status == "No longer kept" })
        XCTAssertTrue(removed.edges.contains { $0.label == "citation recorded" })
        XCTAssertFalse(removed.edges.contains { $0.label == "same kept version" })

        var expired = original
        expired.expiresAt = date.addingTimeInterval(-1)
        let expiration = build([answer], lessons: [expired])
        XCTAssertEqual(expiration.nodes.filter { $0.kind == .lesson && $0.status == "Expired" }.count, 2)
        XCTAssertFalse(expiration.edges.contains { $0.label == "same kept version" })
        XCTAssertTrue(expiration.edges.contains { $0.label == "same saved version · expired" })
    }

    func testExternalReceiptIgnoresPrivateLocalMetadata() {
        let privateLesson = lesson(text: "private relationship must stay local")
        var external = receipt(id: "external", provider: .codex)
        external.localLessons = [LessonSnapshot(lesson: privateLesson)]
        external.localInvocationReceipts = [HamptonInvocationReceipt(id: "private-call", role: .memorySelection,
            inputDigest: "private-input", systemDigest: "private-system", schemaDigest: "private-schema")]
        external.evidence = evidence(sources: ["conversation-1"], memories: [external.localLessons[0].modelID])
        external.localLessonOmissions = [.init(kind: .lessons, reason: .revoked, ids: [lessonID], count: 1)]
        let graph = build([external])
        XCTAssertFalse(graph.nodes.contains { $0.kind == .lesson || $0.kind == .context || $0.kind == .omission })
        XCTAssertFalse(strings(graph).contains(privateLesson.text))
        XCTAssertFalse(strings(graph).contains("private-input"))
        XCTAssertEqual(graph.nodes.filter { $0.kind == .invocation }.count, 1)
        XCTAssertEqual(graph.nodes.first { $0.kind == .invocation }?.title, "Codex request")
        XCTAssertEqual(graph.nodes.first { $0.kind == .invocation }?.target, .assistant)
    }

    func testTemporaryRecordsRespectTurnExpiryAndExactSourceBeforeDisplayingText() {
        let source = CompanionGraphSource(name: "today.txt", text: "valid source excerpt", revision: 1)
        let digest = LessonSource.digest(of: source.text)
        let current = record(id: "memory-current", text: source.text, digest: digest, expires: 10)
        let stale = record(id: "memory-stale", text: "stale private excerpt", digest: String(repeating: "f", count: 64), expires: 10)
        let expired = record(id: "memory-expired", text: "expired private excerpt", digest: digest, expires: 5)
        var answer = receipt(id: "record-answer", provider: .qwen)
        answer.evidence = evidence(memories: [current.id])
        let graph = CompanionGraph.build(receipts: [answer], lessons: [], source: source, now: date,
            records: [current, stale, expired], turn: 5)
        XCTAssertTrue(strings(graph).contains(current.text))
        XCTAssertFalse(strings(graph).contains(stale.text))
        XCTAssertFalse(strings(graph).contains(expired.text))
        XCTAssertFalse(graph.nodes.contains { $0.subtitle == expired.id })
        XCTAssertFalse(graph.edges.contains { $0.label == "same temporary record" })
        XCTAssertEqual(graph.edges.filter { $0.label == "excerpt of" }.count, 1)
    }

    func testReusedMemoryLabelCannotLinkHistoricalRequestToCurrentRecordText() {
        let source = CompanionGraphSource(name: "new.txt", text: "only current record content", revision: 1)
        let current = record(id: "memory-reused", text: source.text, digest: LessonSource.digest(of: source.text), expires: 10)
        var historical = receipt(id: "old-memory-reference", provider: .qwen)
        historical.evidence = evidence(memories: [current.id])
        let graph = CompanionGraph.build(receipts: [historical], lessons: [], source: source, now: date, records: [current], turn: 5)
        let reference = graph.nodes.first { $0.title == "Temporary memory reference" }!
        let currentNode = graph.nodes.first { $0.details.contains(.init(label: "Record ID", value: current.id)) }!
        XCTAssertNotEqual(reference.id, currentNode.id)
        XCTAssertFalse(reference.details.contains { $0.value.contains(source.text) })
        XCTAssertFalse(graph.edges.contains { ($0.source == reference.id && $0.target == currentNode.id)
            || ($0.source == currentNode.id && $0.target == reference.id) })
        XCTAssertTrue(reference.details.contains { $0.label == "Binding" && $0.value.contains("not retained") })
    }

    func testProjectionIsDeterministicBoundedAndHasNoDanglingEdges() {
        let receipts = (0..<80).map { index in
            var receipt = receipt(id: "request-\(index)", provider: index.isMultiple(of: 2) ? .qwen : .codex)
            receipt.evidence = evidence(sources: (0..<30).map { "conversation-\($0)" })
            return receipt
        }
        let first = build(receipts)
        let second = build(Array(receipts.reversed()))
        XCTAssertEqual(first, second)
        XCTAssertLessThanOrEqual(first.nodes.count, CompanionGraph.maximumNodes)
        XCTAssertLessThanOrEqual(first.edges.count, CompanionGraph.maximumEdges)
        XCTAssertGreaterThan(first.truncatedCount, 0)
        let nodeIDs = Set(first.nodes.map(\.id))
        XCTAssertTrue(first.edges.allSatisfy { nodeIDs.contains($0.source) && nodeIDs.contains($0.target) })
        XCTAssertEqual(Set(first.edges.map(\.id)).count, first.edges.count)
    }

    private func build(_ receipts: [AssistantLaneReceipt], lessons: [KeptLesson] = [], source: CompanionGraphSource? = nil) -> CompanionGraphSnapshot {
        CompanionGraph.build(receipts: receipts, lessons: lessons, source: source, now: date)
    }
    private func receipt(id: String, provider: AssistantProvider, state: AssistantLaneState = .complete) -> AssistantLaneReceipt {
        var receipt = AssistantLaneReceipt(requestID: id, route: .compare, provider: provider,
            context: .init(generation: 1, placement: 1, source: 1, selection: 0), inputDigest: String(repeating: "a", count: 64),
            inputContract: AssistantRequest.inputContract, deadline: date.addingTimeInterval(60), modelIdentity: nil, state: state)
        receipt.requestStarted = true
        return receipt
    }
    private func evidence(sources: [String] = [], memories: [String] = []) -> AssistantEvidenceReceipt {
        var evidence = AssistantEvidenceReceipt(contextEnabled: true)
        evidence.sourceIDsAvailable = sources
        evidence.reasoningSourceIDsOffered = sources
        evidence.reasoningSourceIDsDispatched = sources
        evidence.sourceIDsCited = sources
        evidence.reasoningMemoryIDsOffered = memories
        evidence.reasoningMemoryIDsDispatched = memories
        evidence.memoryIDsCited = memories
        return evidence
    }
    private func lesson(text: String, revision: UInt64 = 1) -> KeptLesson {
        .init(id: lessonID, revision: revision, topic: "useful topic", text: text, createdAt: date.addingTimeInterval(-100))
    }
    private func record(id: String, text: String, digest: String, expires: Int) -> SessionContextRecord {
        .init(id: id, text: text, kind: .document, sourceID: "document-source", sourceRevision: 1, sourceDigest: digest,
            range: NSRange(location: 0, length: text.utf16.count), createdTurn: 1, expiresAtTurn: expires, lastReminderTurn: nil)
    }
    private func strings(_ graph: CompanionGraphSnapshot) -> String {
        graph.nodes.flatMap { [$0.title, $0.subtitle, $0.status] + $0.details.flatMap { [$0.label, $0.value] } }.joined(separator: "\n")
    }
}
