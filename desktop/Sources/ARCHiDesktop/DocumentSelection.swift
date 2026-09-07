import Foundation

/// An exact range in one immutable shared copy. Offsets use AppKit's UTF-16 units.
struct DocumentSelection: Equatable, Sendable {
    let range: NSRange
    let quote: String
    let sourceRevision: UInt64

    init?(range: NSRange, text: String, sourceRevision: UInt64) {
        let source = text as NSString
        let count = source.length
        guard range.location >= 0, range.length > 0,
              range.location <= count, range.length <= count - range.location else { return nil }
        // String.Index bridging may round a UTF-16 index inside a surrogate pair.
        // Check both scalar boundaries before using NSString's exact substring.
        for boundary in [range.location, range.location + range.length] {
            if boundary < count && (0xDC00...0xDFFF).contains(source.character(at: boundary)) { return nil }
        }
        self.range = range
        self.quote = source.substring(with: range)
        self.sourceRevision = sourceRevision
    }

    func matches(text: String, sourceRevision: UInt64) -> Bool {
        self == DocumentSelection(range: range, text: text, sourceRevision: sourceRevision)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.range == rhs.range && lhs.sourceRevision == rhs.sourceRevision
            && lhs.quote.utf8.elementsEqual(rhs.quote.utf8)
    }

    var input: JSONValue {
        .object([
            "text": .string(quote), "sourceRevision": .string(String(sourceRevision)),
            "range": .object(["unit": .string("UTF-16"),
                "location": .number(Double(range.location)), "length": .number(Double(range.length))])
        ])
    }
}
