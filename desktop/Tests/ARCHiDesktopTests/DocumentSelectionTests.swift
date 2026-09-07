import Foundation
import Testing
@testable import ARCHiDesktop

struct DocumentSelectionTests {
    @Test func repeatedPassagesKeepTheirExactOccurrence() throws {
        let text = "Same sentence.\nSame sentence."
        let first = try #require(DocumentSelection(range: NSRange(location: 0, length: 14), text: text, sourceRevision: 1))
        let second = try #require(DocumentSelection(range: NSRange(location: 15, length: 14), text: text, sourceRevision: 1))
        #expect(first.quote == second.quote)
        #expect(first != second)
        #expect(second.matches(text: text, sourceRevision: 1))
        #expect(!second.matches(text: text, sourceRevision: 2))
        #expect(!second.matches(text: "Different text.\nChanged second", sourceRevision: 1))
    }

    @Test func exactUnicodeAndMultilineRangesUseUTF16() throws {
        let text = "😀 Before\nCafé 👨‍👩‍👧‍👦\nAfter"
        let quote = "Café 👨‍👩‍👧‍👦\nAfter"
        let range = (text as NSString).range(of: quote)
        let selected = try #require(DocumentSelection(range: range, text: text, sourceRevision: 4))
        #expect(selected.quote == quote)
        #expect(selected.range.location == 10)
        #expect(selected.input["range"]?["unit"]?.string == "UTF-16")
    }

    @Test func invalidAndOverflowingRangesAreRejected() {
        let text = "😀abc"
        for range in [NSRange(location: -1, length: 2), NSRange(location: 0, length: 0),
                      NSRange(location: NSNotFound, length: 1), NSRange(location: 1, length: Int.max),
                      NSRange(location: 0, length: 1), NSRange(location: 1, length: 1),
                      NSRange(location: 5, length: 1)] {
            #expect(DocumentSelection(range: range, text: text, sourceRevision: 1) == nil)
        }
    }

    @Test func canonicallyEquivalentTextCannotSubstituteForExactSourceBytes() throws {
        let original = try #require(DocumentSelection(range: NSRange(location: 0, length: 1), text: "Å", sourceRevision: 1))
        let normalized = try #require(DocumentSelection(range: original.range, text: "Å", sourceRevision: 1))
        #expect(original.quote == normalized.quote) // Swift's ordinary equality normalizes these scalars.
        #expect(original != normalized)
        #expect(!original.matches(text: "Å", sourceRevision: 1))
    }

    @Test func requestBindsFullCopyAndSelectedPassageWithoutInventedGeometry() throws {
        let text = "A first line.\nOnly the second line is selected."
        let selection = try #require(DocumentSelection(range: (text as NSString).range(of: "Only the second line is selected."), text: text, sourceRevision: 9))
        var request = AssistantRequest(prompt: "Explain this", sourceName: "example.txt", sourceText: text,
            sourceRevision: 9, placementRevision: 7, tone: "Calm", replyLength: 0.2, selection: selection)
        let input = try JSONDecoder().decode(JSONValue.self, from: Data(request.input.utf8))
        #expect(input["source"]?["text"]?.string == text)
        #expect(input["selection"]?["text"]?.string == selection.quote)
        #expect(input["selection"]?["sourceRevision"]?.string == "9")
        #expect(input["selection"]?["range"]?["location"] == .number(14))
        #expect(input["position"] == nil)
        #expect(request.hasValidSelection)
        request.selection = DocumentSelection(range: selection.range, text: text, sourceRevision: 8)
        #expect(!request.hasValidSelection)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(request.input.utf8))["selection"] == .null)
    }
}
