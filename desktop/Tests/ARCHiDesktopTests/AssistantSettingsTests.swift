import Foundation
import XCTest
@testable import ARCHiDesktop

final class AssistantSettingsTests: XCTestCase {
    func testUnselectedRoleAndStyleAreAbsentFromSerializedInput() throws {
        let request = AssistantRequest(prompt: "Explain the next step", sourceName: nil, sourceText: "",
            sourceRevision: 0, placementRevision: 4, tone: "Calm", replyLength: 0.35)
        let input = try decode(request)
        XCTAssertEqual(AssistantRequest.inputContract, "native-assistant-input/v4")
        XCTAssertEqual(input["question"], .string("Explain the next step"))
        XCTAssertEqual(input["task"], .string("answer"))
        XCTAssertNil(input["revisionTarget"])
        XCTAssertTrue(request.hasValidRevisionTarget)
        XCTAssertEqual(input["tone"], .string("Calm"))
        XCTAssertEqual(input["length"], .string("moderate"))
        XCTAssertNil(input["role"])
        XCTAssertNil(input["helpStyle"])
        XCTAssertEqual(input["source"], .null)
        XCTAssertEqual(input["placementRevision"], .string("4"))
    }

    func testOptionalPreferencesSerializeIndependentlyUsingTheirStableValues() throws {
        let roles: [EvolutionRole?] = [nil, .beacon]
        let styles: [EvolutionHelpStyle?] = [nil, .stepByStep]
        for role in roles {
            for style in styles {
                let request = AssistantRequest(prompt: "Help", sourceName: nil, sourceText: "",
                    sourceRevision: 0, placementRevision: 0, tone: "Direct", replyLength: 0.2,
                    role: role, helpStyle: style)
                let input = try decode(request)
                XCTAssertEqual(input["role"], role.map { .string($0.rawValue) })
                XCTAssertEqual(input["helpStyle"], style.map { .string($0.rawValue) })
                XCTAssertEqual(input["length"], .string("brief"))
            }
        }
    }

    func testRevisionTargetBindsBothExactCopyAndExactSelectionInBothInitializers() throws {
        let source = "Same. Same."
        let selection = try XCTUnwrap(DocumentSelection(range: NSRange(location: 6, length: 5), text: source, sourceRevision: 7))
        let target = try XCTUnwrap(RevisionTarget(text: source, sourceRevision: 7, selection: selection))
        let compatible = AssistantRequest(prompt: "Make the second sentence concise.", sourceName: "draft.txt", sourceText: source,
            sourceRevision: 7, placementRevision: 2, tone: "Warm", replyLength: 0.9, selection: selection, revisionTarget: target)
        let explicit = AssistantRequest(prompt: compatible.prompt, sourceName: compatible.sourceName, sourceText: source,
            sourceRevision: 7, placementRevision: 2, settings: compatible.settings, selection: selection, revisionTarget: target)
        XCTAssertEqual(try decode(compatible), try decode(explicit))
        XCTAssertEqual(try decode(explicit)["task"], .string("revise"))
        XCTAssertEqual(try decode(explicit)["revisionTarget"], target.input)
        XCTAssertTrue(explicit.hasValidRevisionTarget)
        var otherSelection = explicit
        otherSelection.selection = DocumentSelection(range: NSRange(location: 0, length: 5), text: source, sourceRevision: 7)
        XCTAssertTrue(otherSelection.hasValidSelection)
        XCTAssertFalse(otherSelection.hasValidRevisionTarget, "An identical quote at a different range is a different target")
        let otherCopy = AssistantRequest(prompt: explicit.prompt, sourceName: explicit.sourceName, sourceText: source + " Changed.",
            sourceRevision: 7, placementRevision: 2, settings: explicit.settings, selection: selection, revisionTarget: target)
        XCTAssertTrue(otherCopy.hasValidSelection)
        XCTAssertFalse(otherCopy.hasValidRevisionTarget, "Valid passage offsets do not replace the whole-copy digest check")
        XCTAssertTrue(AssistantInstructions.passageRevisionText.contains(AssistantPreferenceGuidance.text))
    }

    func testRequestRetainsTheExactSettingsCapturedAtSend() throws {
        let captured = AssistantSettingsSnapshot(tone: "Warm", replyLength: 0.9, role: .beacon, helpStyle: .stepByStep)
        var currentSettings = captured
        let request = AssistantRequest(prompt: "Use paragraphs for this reply", sourceName: "work.txt",
            sourceText: "First draft", sourceRevision: 9, placementRevision: 12, settings: currentSettings)
        currentSettings = AssistantSettingsSnapshot(tone: "Playful", replyLength: 0.1, role: .muse, helpStyle: .exploratory)
        XCTAssertEqual(request.settings, captured)
        XCTAssertNotEqual(request.settings, currentSettings)
        XCTAssertEqual(request.tone, captured.tone)
        XCTAssertEqual(request.replyLength, captured.replyLength)
        XCTAssertEqual(request.settings.summary, "Warm · Detailed replies · Beacon · Step by step")
        let input = try decode(request)
        XCTAssertEqual(input["question"], .string("Use paragraphs for this reply"))
        XCTAssertEqual(input["tone"], .string("Warm"))
        XCTAssertEqual(input["role"], .string("beacon"))
        XCTAssertEqual(input["helpStyle"], .string("stepByStep"))
        XCTAssertEqual(input["source"]?["text"], .string("First draft"))
        XCTAssertEqual(input["source"]?["revision"], .string("9"))
    }

    func testLengthLabelsPreserveExistingBoundarySemantics() {
        for (length, label) in [(0.0, "brief"), (0.339, "brief"), (0.34, "moderate"),
                                (0.67, "moderate"), (0.671, "detailed"), (1.0, "detailed")] {
            XCTAssertEqual(AssistantSettingsSnapshot(tone: "Calm", replyLength: length).lengthLabel, label)
        }
        XCTAssertEqual(AssistantSettingsSnapshot(tone: "Calm", replyLength: 0.35).summary, "Calm · Moderate replies")
    }

    func testGroundedAndHamptonReasoningSharePreferencePrecedenceAndBoundaries() {
        let reasoning = LocalRoleRequest(id: "settings-check", role: .reasoning, input: .object([:]), outputSchema: .object([:]))
        let guidance = AssistantPreferenceGuidance.text
        XCTAssertTrue(AssistantInstructions.groundedText.contains(guidance))
        XCTAssertTrue(reasoning.systemInstruction.contains(guidance))
        XCTAssertTrue(guidance.contains("The current question takes precedence over these defaults when they conflict."))
        XCTAssertTrue(guidance.contains("Length controls the amount of detail"))
        XCTAssertTrue(guidance.contains("helpStyle changes structure"))
        XCTAssertTrue(guidance.contains("grant no tools, privileges, authority or new abilities"))
        for role in EvolutionRole.allCases {
            XCTAssertTrue(guidance.contains("\(role.rawValue): \(role.summary)"))
        }
        for style in EvolutionHelpStyle.allCases {
            XCTAssertTrue(guidance.contains(style.rawValue))
        }
        XCTAssertTrue(AssistantInstructions.groundedText.contains("No tools are available in this connection."))
        XCTAssertTrue(reasoning.systemInstruction.contains("Do not claim external actions or persistent learning."))
    }

    private func decode(_ request: AssistantRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(request.input.utf8))
    }
}
