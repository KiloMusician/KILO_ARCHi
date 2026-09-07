import Foundation
import XCTest
@testable import ARCHiDesktop

/// Explicit diagnostic only: one installed local Qwen reasoning invocation,
/// synthetic input, no Codex, retries, downloads, or durable memory changes.
final class RevisionBehaviorTests: XCTestCase {
    @MainActor
    func testInstalledLocalModelProposesOneSourceBoundPassageRevision() async throws {
        guard let directory = ProcessInfo.processInfo.environment["ARCHI_REVISION_LIVE_DIR"], !directory.isEmpty else {
            throw XCTSkip("Set ARCHI_REVISION_LIVE_DIR only for an explicitly authorized local model check")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("revision-local.json")
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw XCTSkip("This diagnostic directory already contains its one revision receipt")
        }
        let source = "The Harbor launch review will take place on Friday at 14:00. Please bring the revised agenda."
        let selection = try XCTUnwrap(DocumentSelection(range: NSRange(location: 0, length: source.utf16.count), text: source, sourceRevision: 1))
        let target = try XCTUnwrap(RevisionTarget(text: source, sourceRevision: 1, selection: selection))
        let request = AssistantRequest(prompt: "Rewrite this as a concise, friendly invitation. Preserve Harbor, Friday, 14:00, and the request to bring the revised agenda.",
            sourceName: "synthetic-harbor-invitation.txt", sourceText: source, sourceRevision: 1, placementRevision: 0,
            tone: "Warm", replyLength: 0.35, selection: selection, revisionTarget: target)
        let client = HamptonReasonsAssistant(contextEnabled: false)
        let started = Date()
        var revisions: [PassageRevisionProposal] = [], unexpectedText: [String] = [], failure: String?
        do {
            try await client.connect()
            try await client.reply(to: request) { event in
                switch event {
                case .revision(let proposal): revisions.append(proposal)
                case .text(let text): unexpectedText.append(text)
                }
            }
        } catch { failure = String(describing: error) }
        let snapshot = client.snapshot
        await client.shutdown()
        let proposal = revisions.first
        let evidence: JSONValue = .object([
            "schema": .string("archi-local-revision-behavior/v1"),
            "status": .string(failure == nil && proposal != nil ? "proposal-accepted-for-review" : "no-proposal-accepted"),
            "inputContract": .string(AssistantRequest.inputContract),
            "request": try JSONDecoder().decode(JSONValue.self, from: Data(request.input.utf8)),
            "source": .string(source), "target": target.input,
            "failure": failure.map(JSONValue.string) ?? .null,
            "elapsedMilliseconds": .number(Date().timeIntervalSince(started) * 1000),
            "contextEnabled": .bool(false), "unexpectedText": .array(unexpectedText.map(JSONValue.string)),
            "eventCount": .number(Double(revisions.count)),
            "proposal": proposal.map { .object([
                "decision": .string($0.decision.rawValue), "replacement": .string($0.replacement),
                "explanation": .string($0.explanation), "sourceIDs": .array($0.sourceIDs.map(JSONValue.string)),
                "memoryIDs": .array($0.memoryIDs.map(JSONValue.string)), "target": $0.target.input
            ]) } ?? .null,
            "snapshot": .object([
                "phase": .string(snapshot.phase), "turn": .number(Double(snapshot.turn)),
                "recordCount": .number(Double(snapshot.records.count)),
                "attemptedInvocations": .array(snapshot.attemptedInvocations.map { .string($0.rawValue) }),
                "receipts": .array(snapshot.receipts.map { .object([
                    "requestID": .string($0.id), "role": .string($0.role.rawValue),
                    "model": .string($0.model.name), "modelDigest": .string($0.model.digest),
                    "policyVersion": .string($0.policyVersion), "inputDigest": .string($0.inputDigest),
                    "outputDigest": .string($0.outputDigest), "schemaDigest": .string($0.schemaDigest),
                    "systemDigest": .string($0.systemDigest), "elapsedMilliseconds": .number(Double($0.elapsedMilliseconds))
                ]) })
            ]),
            "workingCopyApplied": .bool(false)
        ])
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(evidence).write(to: output, options: .atomic)
        XCTAssertNil(failure)
        XCTAssertTrue(unexpectedText.isEmpty)
        XCTAssertEqual(snapshot.attemptedInvocations, [.reasoning])
        XCTAssertTrue(snapshot.records.isEmpty)
        XCTAssertEqual(revisions.count, 1)
        let accepted = try XCTUnwrap(proposal)
        XCTAssertEqual(accepted.target, target)
        XCTAssertEqual(accepted.decision, .propose)
        XCTAssertFalse(accepted.replacement.isEmpty)
        for detail in ["Harbor", "Friday", "14:00", "agenda"] {
            XCTAssertTrue(accepted.replacement.contains(detail), "Synthetic factual detail missing: \(detail)")
        }
    }
}
