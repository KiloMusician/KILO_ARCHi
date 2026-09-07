import Foundation
import XCTest
@testable import ARCHiDesktop

final class WorkingCopyRevisionTests: XCTestCase {
    func testTargetCapturesExactOccurrenceFullCopyAndRevision() throws {
        let text = "Repeat this.\nRepeat this."
        let first = try target(text, range: NSRange(location: 0, length: 12))
        let second = try target(text, range: NSRange(location: 13, length: 12))
        XCTAssertEqual(first.selection.quote, second.selection.quote)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.matches(text: text, sourceRevision: 3))
        XCTAssertFalse(second.matches(text: text, sourceRevision: 4))
        XCTAssertFalse(second.matches(text: "Change this.\nRepeat this.", sourceRevision: 3),
                       "An edit outside the selected passage still invalidates the complete source binding.")
        XCTAssertEqual(second.input["sourceDigest"]?.string, WorkingCopyEditReceipt.digest(text))
        XCTAssertEqual(second.input["selection"]?["range"]?["location"], .number(13))
        let proposal = try parse(target: second, replacement: "Revise this.")
        XCTAssertEqual(try WorkingCopyEditReceipt.applying(proposal: proposal, to: text, sourceRevision: 3),
                       "Repeat this.\nRevise this.")
    }

    func testTargetRejectsStaleSelectionInvalidIDAndOversizedCopy() throws {
        let selection = try XCTUnwrap(DocumentSelection(range: NSRange(location: 0, length: 4), text: "Text", sourceRevision: 3))
        XCTAssertNil(RevisionTarget(text: "Next", sourceRevision: 3, selection: selection))
        XCTAssertNil(RevisionTarget(text: "Text", sourceRevision: 4, selection: selection))
        XCTAssertNil(RevisionTarget(text: "Text", sourceRevision: 3, selection: selection, id: "unbound"))
        XCTAssertNil(RevisionTarget(text: "Text" + String(repeating: "x", count: 100_000), sourceRevision: 3, selection: selection))
    }

    func testUTF16ScalarBoundariesAndUnicodeByteIdentityStayExact() throws {
        let text = "😀 Before\nCafe\u{301} 👨‍👩‍👧‍👦\nAfter"
        for range in [NSRange(location: 0, length: 1), NSRange(location: 1, length: 1),
                      NSRange(location: NSNotFound, length: 1), NSRange(location: 2, length: Int.max)] {
            XCTAssertNil(DocumentSelection(range: range, text: text, sourceRevision: 3))
        }
        let selection = (text as NSString).range(of: "Cafe\u{301} 👨‍👩‍👧‍👦")
        let value = try target(text, range: selection)
        let proposal = try parse(target: value, replacement: "Café with family")
        XCTAssertEqual(try WorkingCopyEditReceipt.applying(proposal: proposal, to: text, sourceRevision: 3),
                       "😀 Before\nCafé with family\nAfter")
        XCTAssertFalse(value.matches(text: text.precomposedStringWithCanonicalMapping, sourceRevision: 3))
        let composed = try target("Å")
        let normalization = try parse(target: composed, replacement: "Å")
        XCTAssertEqual(normalization.replacement, composed.selection.quote, "Swift equality normalizes these characters.")
        XCTAssertFalse(normalization.replacement.utf8.elementsEqual(composed.selection.quote.utf8))
    }

    func testClosedSchemaHasTargetAndAllowedReferences() throws {
        let value = try target("Original")
        let schema = PassageRevisionValidator.schema(target: value, sourceIDs: ["shared-copy", "shared-copy"], memoryIDs: [])
        XCTAssertEqual(schema["additionalProperties"], .bool(false))
        let fields = try XCTUnwrap(schema["properties"]?.object)
        XCTAssertEqual(Set(fields.keys), ["schema", "targetID", "decision", "replacement", "explanation", "sourceIDs", "memoryIDs"])
        XCTAssertEqual(fields["schema"]?["const"], .string("native-passage-revision/v1"))
        XCTAssertEqual(fields["targetID"]?["const"], .string(value.id))
        XCTAssertEqual(fields["replacement"]?["maxLength"], .number(8_000))
        XCTAssertEqual(fields["explanation"]?["maxLength"], .number(600))
        XCTAssertEqual(fields["explanation"]?["minLength"], .number(1))
        XCTAssertEqual(fields["memoryIDs"]?["maxItems"], .number(0))
        XCTAssertEqual(fields["sourceIDs"]?["maxItems"], .number(1))
        XCTAssertEqual(fields["sourceIDs"]?["items"]?["enum"], .array([.string("shared-copy")]))
        XCTAssertEqual(schema["required"]?.array?.count, 7)
    }

    func testProposalKeepsExactReplacementAndReferences() throws {
        let value = try target("Original")
        let proposal = try parse(target: value, replacement: "  Revised.\n", explanation: "Simplifies the wording.",
            sources: ["selected-passage"], memories: ["kept-example-r1"])
        XCTAssertEqual(proposal.target, value)
        XCTAssertEqual(proposal.decision, .propose)
        XCTAssertEqual(proposal.replacement, "  Revised.\n", "Validation must not trim an authored replacement.")
        XCTAssertEqual(proposal.explanation, "Simplifies the wording.")
        XCTAssertEqual(proposal.sourceIDs, ["selected-passage"])
        XCTAssertEqual(proposal.memoryIDs, ["kept-example-r1"])
    }

    func testClarifyAndAbstainNeverCarryApplicableReplacement() throws {
        let value = try target("Original")
        for decision in [RevisionDecision.clarify, .abstain] {
            let proposal = try parse(target: value, decision: decision, replacement: "", explanation: "Please clarify the intended audience.")
            XCTAssertEqual(proposal.decision, decision)
            XCTAssertThrowsError(try WorkingCopyEditReceipt.applying(proposal: proposal, to: "Original", sourceRevision: 3))
            XCTAssertThrowsError(try parse(target: value, decision: decision, replacement: "Unexpected edit"))
        }
        XCTAssertThrowsError(try parse(target: value, replacement: ""))
        XCTAssertThrowsError(try parse(target: value, replacement: "Original"))
    }

    func testScalarBoundsRejectGraphemeAndUTF8LimitConfusion() throws {
        let value = try target("Original")
        XCTAssertNoThrow(try parse(target: value, replacement: String(repeating: "😀", count: 8_000),
                                  explanation: String(repeating: "é", count: 600)))
        XCTAssertThrowsError(try parse(target: value, replacement: String(repeating: "a", count: 8_001)))
        let oneGrapheme = "a" + String(repeating: "\u{301}", count: 8_000)
        XCTAssertEqual(oneGrapheme.count, 1)
        XCTAssertThrowsError(try parse(target: value, replacement: oneGrapheme))
        XCTAssertThrowsError(try parse(target: value, replacement: "Revised", explanation: String(repeating: "a", count: 601)))
        XCTAssertThrowsError(try parse(target: value, replacement: "Revised", explanation: ""))
        XCTAssertThrowsError(try parse(target: value, decision: .clarify, replacement: "", explanation: " \n "))
    }

    func testMalformedUnknownDuplicateAndMismatchedPayloadsAreRejected() throws {
        let value = try target("Original")
        let good = try payload(target: value)
        for raw in ["not JSON", "[\(good)]", good + " trailing", String(repeating: " ", count: PassageRevisionValidator.maximumRawBytes + 1)] {
            XCTAssertThrowsError(try PassageRevisionValidator.parse(raw, target: value, sourceIDs: [], memoryIDs: []))
        }
        let variants = [
            good.replacingOccurrences(of: "\"targetID\":", with: "\"unexpected\":true,\"targetID\":"),
            good.replacingOccurrences(of: "\"replacement\":", with: "\"replacement\":\"shadow\",\"replacem\\u0065nt\":"),
            good.replacingOccurrences(of: value.id, with: UUID().uuidString),
            good.replacingOccurrences(of: "native-passage-revision/v1", with: "native-passage-revision/v2"),
            good.replacingOccurrences(of: "PROPOSE", with: "APPLY")
        ]
        for raw in variants {
            XCTAssertNotEqual(raw, good)
            XCTAssertThrowsError(try PassageRevisionValidator.parse(raw, target: value, sourceIDs: [], memoryIDs: []))
        }
    }

    func testReferencesRejectUnknownDuplicateWrongTypeAndNormalizedSubstitution() throws {
        let value = try target("Original")
        for (references, allowed) in [(["unknown"], ["shared-copy"]), (["shared-copy", "shared-copy"], ["shared-copy"]),
                                      (["cafe\u{301}"], ["café"])] {
            let raw = try payload(target: value, sources: references)
            XCTAssertThrowsError(try PassageRevisionValidator.parse(raw, target: value, sourceIDs: allowed, memoryIDs: []))
        }
        let wrongType = try payload(target: value).replacingOccurrences(of: "\"sourceIDs\":[]", with: "\"sourceIDs\":[42]")
        XCTAssertThrowsError(try PassageRevisionValidator.parse(wrongType, target: value, sourceIDs: [], memoryIDs: []))
        let memory = try payload(target: value, memories: ["old-revision"])
        XCTAssertThrowsError(try PassageRevisionValidator.parse(memory, target: value, sourceIDs: [], memoryIDs: ["new-revision"]))
        let tooMany = (0...PassageRevisionValidator.maximumReferences).map { "memory-\($0)" }
        let oversized = try payload(target: value, memories: tooMany)
        XCTAssertThrowsError(try PassageRevisionValidator.parse(oversized, target: value, sourceIDs: [], memoryIDs: tooMany))
    }

    func testApplyRequiresCurrentTargetAndLeavesAllOtherBytesUntouched() throws {
        let text = "Start\r\nChange me\r\nEnd 😀"
        let value = try target(text, range: (text as NSString).range(of: "Change me"))
        let proposal = try parse(target: value, replacement: "Changed")
        let after = try WorkingCopyEditReceipt.applying(proposal: proposal, to: text, sourceRevision: 3)
        XCTAssertTrue(after.utf8.elementsEqual("Start\r\nChanged\r\nEnd 😀".utf8))
        XCTAssertThrowsError(try WorkingCopyEditReceipt.applying(proposal: proposal, to: text, sourceRevision: 4))
        XCTAssertThrowsError(try WorkingCopyEditReceipt.applying(proposal: proposal, to: text + "!", sourceRevision: 3))
        let noOp = PassageRevisionProposal(target: value, decision: .propose, replacement: value.selection.quote,
            explanation: "", sourceIDs: [], memoryIDs: [])
        XCTAssertThrowsError(try WorkingCopyEditReceipt.applying(proposal: noOp, to: text, sourceRevision: 3))
    }

    func testFinalCopyUsesUTF8ByteBudgetAndRevisionCannotWrap() throws {
        let text = "x" + String(repeating: "y", count: 99_999)
        let value = try target(text, range: NSRange(location: 0, length: 1))
        let tooLarge = try parse(target: value, replacement: "😀")
        XCTAssertThrowsError(try WorkingCopyEditReceipt.applying(proposal: tooLarge, to: text, sourceRevision: 3))
        let fits = try parse(target: value, replacement: "z")
        XCTAssertEqual(try WorkingCopyEditReceipt.applying(proposal: fits, to: text, sourceRevision: 3).utf8.count, 100_000)
        for revision in [UInt64.max - 1, UInt64.max] {
            let last = try target("Original", revision: revision)
            let overflow = try parse(target: last, replacement: "Revised")
            XCTAssertThrowsError(try WorkingCopyEditReceipt.applying(proposal: overflow, to: "Original", sourceRevision: revision))
        }
        let lastReversible = try target("Original", revision: UInt64.max - 2)
        let reversible = try parse(target: lastReversible, replacement: "Revised")
        let after = try WorkingCopyEditReceipt.applying(proposal: reversible, to: "Original", sourceRevision: UInt64.max - 2)
        let undo = WorkingCopyEditReceipt(before: "Original", afterDigest: WorkingCopyEditReceipt.digest(after), afterRevision: UInt64.max - 1)
        XCTAssertTrue(undo.canUndo(text: after, revision: UInt64.max - 1))
    }

    func testUndoRequiresExactAfterBytesAndRevisionAndPreservesBefore() throws {
        let before = "Original Å\r\n"
        let after = "Revised Å\r\n"
        let receipt = WorkingCopyEditReceipt(before: before, afterDigest: WorkingCopyEditReceipt.digest(after), afterRevision: 4)
        XCTAssertTrue(receipt.canUndo(text: after, revision: 4))
        XCTAssertFalse(receipt.canUndo(text: after, revision: 5))
        XCTAssertFalse(receipt.canUndo(text: "Revised Å\r\n", revision: 4))
        XCTAssertFalse(receipt.canUndo(text: after + "!", revision: 4))
        XCTAssertTrue(receipt.before.utf8.elementsEqual(before.utf8))
        let invalid = WorkingCopyEditReceipt(before: String(repeating: "x", count: 100_001),
            afterDigest: WorkingCopyEditReceipt.digest(after), afterRevision: 4)
        XCTAssertFalse(invalid.canUndo(text: after, revision: 4))
        let finalRevision = WorkingCopyEditReceipt(before: before, afterDigest: WorkingCopyEditReceipt.digest(after), afterRevision: UInt64.max)
        XCTAssertFalse(finalRevision.canUndo(text: after, revision: UInt64.max), "Undo must leave room to advance the source revision.")
    }

    private func target(_ text: String, range: NSRange? = nil, revision: UInt64 = 3) throws -> RevisionTarget {
        let selected = try XCTUnwrap(DocumentSelection(range: range ?? NSRange(location: 0, length: text.utf16.count),
                                                       text: text, sourceRevision: revision))
        return try XCTUnwrap(RevisionTarget(text: text, sourceRevision: revision, selection: selected))
    }

    private func parse(target: RevisionTarget, decision: RevisionDecision = .propose, replacement: String = "Revised",
                       explanation: String = "Simplifies the wording.", sources: [String] = [], memories: [String] = []) throws -> PassageRevisionProposal {
        try PassageRevisionValidator.parse(payload(target: target, decision: decision, replacement: replacement,
            explanation: explanation, sources: sources, memories: memories), target: target, sourceIDs: sources, memoryIDs: memories)
    }

    private func payload(target: RevisionTarget, decision: RevisionDecision = .propose, replacement: String = "Revised",
                         explanation: String = "Simplifies the wording.", sources: [String] = [], memories: [String] = []) throws -> String {
        let object: JSONValue = .object(["schema": .string(PassageRevisionValidator.schemaName),
            "targetID": .string(target.id), "decision": .string(decision.rawValue), "replacement": .string(replacement),
            "explanation": .string(explanation), "sourceIDs": .array(sources.map(JSONValue.string)),
            "memoryIDs": .array(memories.map(JSONValue.string))])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(object), as: UTF8.self)
    }
}
