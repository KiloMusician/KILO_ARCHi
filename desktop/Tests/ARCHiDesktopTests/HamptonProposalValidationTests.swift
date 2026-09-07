import Foundation
import Testing
@testable import ARCHiDesktop

struct HamptonProposalValidationTests {
    @Test func schemasBindRequestsCloseObjectsAndConstrainReferences() throws {
        for role in [LocalModelRole.memorySelection, .memoryReminder, .reasoning] {
            let schema = HamptonProposalValidator.schema(for: role, requestID: "request-1",
                sourceIDs: ["s2", "s1"], memoryIDs: ["m1"], candidateIDs: ["c1"])
            #expect(schema["additionalProperties"] == .bool(false))
            #expect(schema["properties"]?["requestID"]?["const"] == .string("request-1"))
            let keys = try #require(schema["properties"]?.object?.keys)
            #expect(Set(schema["required"]?.array?.compactMap(\.string) ?? []) == Set(keys))
        }
        let reasoning = HamptonProposalValidator.schema(for: .reasoning, requestID: "r", sourceIDs: ["s2", "s1", "s1"])
        #expect(reasoning["properties"]?["sourceIDs"]?["items"]?["enum"] == .array([.string("s1"), .string("s2")]))
        #expect(reasoning["properties"]?["sourceIDs"]?["uniqueItems"] == .bool(true))
        #expect(reasoning["properties"]?["memoryIDs"]?["maxItems"] == .number(0))
        #expect(reasoning["properties"]?["memoryIDs"]?["items"]?["enum"] == nil)
        let reminder = HamptonProposalValidator.schema(for: .memoryReminder, requestID: "r")
        #expect(reminder["properties"]?["decision"]?["const"] == .string("NONE"))
        #expect(reminder["properties"]?["memoryIDs"]?["maxItems"] == .number(0))
        let choices = HamptonProposalValidator.schema(for: .memoryReminder, requestID: "r", memoryIDs: ["m1"])
        #expect(choices["oneOf"] == nil)
        #expect(choices["additionalProperties"] == .bool(false))
        #expect(choices["required"] == .array(["decision", "memoryIDs", "requestID", "schema"].map(JSONValue.string)))
        #expect(choices["properties"]?["decision"]?["enum"] == .array([.string("NONE"), .string("SELECT")]))
        #expect(choices["properties"]?["memoryIDs"]?["items"]?["enum"] == .array([.string("m1")]))
        #expect(choices["properties"]?["memoryIDs"]?["maxItems"] == .number(3))
        #expect(choices["properties"]?["memoryIDs"]?["uniqueItems"] == .bool(true))
    }

    @Test func selectionPreservesAllowedOrderAndPermitsNoCandidates() throws {
        let request = request(.memorySelection)
        #expect(try HamptonProposalValidator.parseSelection(result(selection(["c2", "c1"])), request: request,
            allowedCandidateIDs: ["c1", "c2"]) == ["c2", "c1"])
        #expect(try HamptonProposalValidator.parseSelection(result(selection([])), request: request,
            allowedCandidateIDs: []).isEmpty)
    }

    @Test func reminderDecisionMustAgreeWithSelectedReferences() throws {
        let request = request(.memoryReminder)
        #expect(try HamptonProposalValidator.parseReminder(result(reminder("NONE", []), role: .memoryReminder), request: request,
            allowedMemoryIDs: []).isEmpty)
        #expect(try HamptonProposalValidator.parseReminder(result(reminder("SELECT", ["m1"]), role: .memoryReminder), request: request,
            allowedMemoryIDs: ["m1"]) == ["m1"])
        for payload in [reminder("NONE", ["m1"]), reminder("SELECT", [])] {
            #expect(throws: HamptonProposalValidationError.inconsistentDecision) {
                try HamptonProposalValidator.parseReminder(result(payload, role: .memoryReminder), request: request, allowedMemoryIDs: ["m1"])
            }
        }
        #expect(throws: HamptonProposalValidationError.invalidShape) {
            try HamptonProposalValidator.parseReminder(result(reminder("COMMIT", []), role: .memoryReminder), request: request, allowedMemoryIDs: [])
        }
    }

    @Test func partialReminderObservedFromLocalSchemaLoweringIsRejected() {
        let request = LocalRoleRequest(id: "r", role: .memoryReminder, input: .object([:]),
            outputSchema: HamptonProposalValidator.schema(for: .memoryReminder, requestID: "r", memoryIDs: ["m1"]))
        #expect(throws: HamptonProposalValidationError.invalidShape) {
            try HamptonProposalValidator.parseReminder(rawResult(#"{"decision":"SELECT"}"#, role: .memoryReminder),
                request: request, allowedMemoryIDs: ["m1"])
        }
    }

    @Test func reasoningKindsAndInclusiveUnicodeBoundsAreAdmitted() throws {
        for kind in ["ANSWER", "CLARIFY", "ABSTAIN"] {
            let proposal = try parseReason(reason(kind: kind, answer: String(repeating: "🌙", count: 1200),
                uncertainty: String(repeating: "é", count: 320)))
            #expect(proposal.kind.rawValue == kind)
            #expect(proposal.answer.unicodeScalars.count == 1200)
            #expect(proposal.uncertainty.unicodeScalars.count == 320)
            #expect(proposal.sourceIDs == ["s1"])
            #expect(proposal.memoryIDs == ["m1"])
        }
    }

    @Test func invalidOrBlankReasonTextCannotBecomeAnAnswer() {
        for text in ["", " \n\t", String(repeating: "a", count: 1201), String(repeating: "e\u{301}", count: 601)] {
            #expect(throws: HamptonProposalValidationError.invalidText) { try parseReason(reason(answer: text)) }
        }
        #expect(throws: HamptonProposalValidationError.invalidText) {
            try parseReason(reason(uncertainty: String(repeating: "a", count: 321)))
        }
        #expect(throws: HamptonProposalValidationError.invalidShape) { try parseReason(reason(kind: "EXECUTE")) }
    }

    @Test func missingUnknownAndAuthorityFieldsAreRejected() {
        for field in ["schema", "requestID", "kind", "answer", "uncertainty", "sourceIDs", "memoryIDs"] {
            var payload = reason()
            payload.removeValue(forKey: field)
            #expect(throws: HamptonProposalValidationError.invalidShape) { try parseReason(payload) }
        }
        for field in ["action", "permissionGrant", "memoryWritable", "canonWritable", "tool_calls", "extra"] {
            var payload = reason()
            payload[field] = .bool(true)
            #expect(throws: HamptonProposalValidationError.invalidShape) { try parseReason(payload) }
        }
        var wrongSchema = reason()
        wrongSchema["schema"] = .string("archi-reason-proposal/v2")
        #expect(throws: HamptonProposalValidationError.invalidShape) { try parseReason(wrongSchema) }
    }

    @Test func envelopeAndPayloadMustMatchTheExactRoleAndRequest() {
        let reasonResult = result(reason(), role: .reasoning)
        #expect(throws: HamptonProposalValidationError.wrongRole) {
            try HamptonProposalValidator.parseReason(reasonResult, request: request(.memorySelection), allowedSourceIDs: ["s1"], allowedMemoryIDs: ["m1"])
        }
        #expect(throws: HamptonProposalValidationError.wrongRole) {
            try HamptonProposalValidator.parseReason(result(reason(), role: .memoryReminder), request: request(.reasoning), allowedSourceIDs: ["s1"], allowedMemoryIDs: ["m1"])
        }
        #expect(throws: HamptonProposalValidationError.wrongRequest) {
            try HamptonProposalValidator.parseReason(result(reason(), role: .reasoning, requestID: "old"), request: request(.reasoning), allowedSourceIDs: ["s1"], allowedMemoryIDs: ["m1"])
        }
        var stale = reason()
        stale["requestID"] = .string("old")
        #expect(throws: HamptonProposalValidationError.wrongRequest) { try parseReason(stale) }
    }

    @Test func inventedDuplicateAndExcessiveReferencesAreRejectedAcrossRoles() {
        for ids in [["invented"], ["c1", "c1"], ["c1", "c2", "c3", "c4", "c5"]] {
            #expect(throws: HamptonProposalValidationError.self) {
                try HamptonProposalValidator.parseSelection(result(selection(ids)), request: request(.memorySelection), allowedCandidateIDs: ["c1", "c2", "c3", "c4", "c5"])
            }
        }
        for ids in [["invented"], ["m1", "m1"], ["m1", "m2", "m3", "m4"]] {
            #expect(throws: HamptonProposalValidationError.self) {
                try HamptonProposalValidator.parseReminder(result(reminder("SELECT", ids), role: .memoryReminder), request: request(.memoryReminder), allowedMemoryIDs: ["m1", "m2", "m3", "m4"])
            }
        }
        for field in ["sourceIDs", "memoryIDs"] {
            for value in [JSONValue.array([.string("invented")]), .array([.string(field == "sourceIDs" ? "s1" : "m1"), .string(field == "sourceIDs" ? "s1" : "m1")]), .array([.number(1)]), .null] {
                var payload = reason()
                payload[field] = value
                #expect(throws: HamptonProposalValidationError.self) { try parseReason(payload) }
            }
        }
    }

    @Test func duplicateLiteralEscapedAndNestedKeysAreRejectedBeforeDictionaryDecoding() {
        for raw in [
            #"{"schema":"archi-session-selection/v1","requestID":"r","candidateIDs":[],"candidateIDs":["c1"]}"#,
            #"{"schema":"archi-session-selection/v1","requestID":"r","candidateIDs":[],"\u0063andidateIDs":[]}"#,
            #"{"schema":"archi-session-selection/v1","requestID":"r","candidateIDs":[],"extra":{"same":1,"same":2}}"#
        ] {
            #expect(throws: HamptonProposalValidationError.duplicateKey) {
                try HamptonProposalValidator.parseSelection(rawResult(raw), request: request(.memorySelection), allowedCandidateIDs: ["c1"])
            }
        }
    }

    @Test func quotedBracesEscapesAndUnicodeAreOrdinaryAnswerData() throws {
        let text = #"The source says {"answer":"one","answer":"two"}; a quoted string is not an object. 🌙"#
        #expect(try parseReason(reason(answer: text)).answer == text)
        let raw = " \r\n" + result(reason(answer: "Café\n\\\"quoted\""), role: .reasoning).text + "\t\n"
        #expect(try HamptonProposalValidator.parseReason(rawResult(raw, role: .reasoning), request: request(.reasoning), allowedSourceIDs: ["s1"], allowedMemoryIDs: ["m1"]).answer == "Café\n\\\"quoted\"")
    }

    @Test func malformedNonObjectsTruncationAndTrailingValuesAreRejected() {
        for raw in ["", "[]", "null", "true", "```json\n{}\n```", "{} {}", "{", #"{"a":"\uD800"}"#,
                    #"{"schema":"archi-session-selection/v1","requestID":"r","candidateIDs":[,]}"#,
                    #"{"schema":"archi-session-selection/v1","requestID":"r","candidateIDs":[],}"#] {
            #expect(throws: HamptonProposalValidationError.self) {
                try HamptonProposalValidator.parseSelection(rawResult(raw), request: request(.memorySelection), allowedCandidateIDs: [])
            }
        }
    }

    @Test func rawByteLimitIncludesWhitespaceAndMultibyteText() throws {
        let valid = result(selection([])).text
        let padding = HamptonProposalValidator.maximumRawBytes - valid.utf8.count
        let exactlyBounded = String(repeating: " ", count: padding) + valid
        #expect(try HamptonProposalValidator.parseSelection(rawResult(exactlyBounded), request: request(.memorySelection), allowedCandidateIDs: []).isEmpty)
        #expect(throws: HamptonProposalValidationError.oversized) {
            try HamptonProposalValidator.parseSelection(rawResult(exactlyBounded + " "), request: request(.memorySelection), allowedCandidateIDs: [])
        }
        #expect(throws: HamptonProposalValidationError.oversized) {
            try HamptonProposalValidator.parseSelection(rawResult(String(repeating: "🌙", count: 4097)), request: request(.memorySelection), allowedCandidateIDs: [])
        }
    }

    @Test func deepUnknownStructuresCannotExhaustTheDecoderStack() {
        let raw = String(repeating: "[", count: 1000) + "0" + String(repeating: "]", count: 1000)
        #expect(throws: HamptonProposalValidationError.malformedJSON) {
            try HamptonProposalValidator.parseSelection(rawResult(raw), request: request(.memorySelection), allowedCandidateIDs: [])
        }
    }

    @Test func referenceAndRequestIdentityDoNotUseUnicodeCanonicalEquivalence() {
        let composed = "caf\u{00E9}", decomposed = "cafe\u{301}"
        #expect(composed == decomposed) // Swift equality alone is insufficient here.
        #expect(throws: HamptonProposalValidationError.unknownReference) {
            try HamptonProposalValidator.parseSelection(result(selection([decomposed])), request: request(.memorySelection), allowedCandidateIDs: [composed])
        }
        #expect(throws: HamptonProposalValidationError.wrongRequest) {
            try HamptonProposalValidator.parseSelection(rawResult("{}", requestID: decomposed), request: request(.memorySelection, id: composed), allowedCandidateIDs: [])
        }
    }

    private func request(_ role: LocalModelRole, id: String = "r") -> LocalRoleRequest {
        LocalRoleRequest(id: id, role: role, input: .object([:]), outputSchema: HamptonProposalValidator.schema(for: role, requestID: id))
    }

    private func result(_ payload: [String: JSONValue], role: LocalModelRole = .memorySelection, requestID: String = "r") -> LocalRoleResult {
        rawResult(String(decoding: try! JSONEncoder().encode(JSONValue.object(payload)), as: UTF8.self), role: role, requestID: requestID)
    }

    private func rawResult(_ text: String, role: LocalModelRole = .memorySelection, requestID: String = "r") -> LocalRoleResult {
        LocalRoleResult(requestID: requestID, role: role, text: text,
            model: QwenModelMetadata(name: "fixture", family: "fixture", parameterSize: "fixture", quantization: "fixture", digest: "fixture"), elapsedMilliseconds: 0)
    }

    private func selection(_ ids: [String]) -> [String: JSONValue] {
        ["schema": .string("archi-session-selection/v1"), "requestID": .string("r"), "candidateIDs": .array(ids.map(JSONValue.string))]
    }

    private func reminder(_ decision: String, _ ids: [String]) -> [String: JSONValue] {
        ["schema": .string("archi-session-reminder/v1"), "requestID": .string("r"), "decision": .string(decision), "memoryIDs": .array(ids.map(JSONValue.string))]
    }

    private func reason(kind: String = "ANSWER", answer: String = "The source says Option B.", uncertainty: String = "") -> [String: JSONValue] {
        ["schema": .string("archi-reason-proposal/v1"), "requestID": .string("r"), "kind": .string(kind),
         "answer": .string(answer), "uncertainty": .string(uncertainty),
         "sourceIDs": .array([.string("s1")]), "memoryIDs": .array([.string("m1")])]
    }

    private func parseReason(_ payload: [String: JSONValue]) throws -> HamptonReasonProposal {
        try HamptonProposalValidator.parseReason(result(payload, role: .reasoning), request: request(.reasoning), allowedSourceIDs: ["s1"], allowedMemoryIDs: ["m1"])
    }
}
