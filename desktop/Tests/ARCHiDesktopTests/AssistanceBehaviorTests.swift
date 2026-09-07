import Foundation
import XCTest
@testable import ARCHiDesktop

final class AssistanceBehaviorTests: XCTestCase {
    /// Deliberate opt-in: three local sends, synthetic source, no automatic retry.
    @MainActor
    func testLocalStylesAndCurrentInstructionThroughProductionStore() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_ASSISTANCE_LIVE_DIR"] else {
            throw XCTSkip("Set ARCHI_ASSISTANCE_LIVE_DIR for the bounded on-device demonstration.")
        }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = CompanionStore(preferenceURL: output.appendingPathComponent("unused-preferences.json"))
        store.preferences.tone = "Direct"
        store.preferences.replyLength = 0.5
        store.share(text: "Juniper is a personal sketchbook project. I have 20 minutes today. I want to draw one tree and learn from the attempt. I often spend the whole session choosing supplies. My pencil and paper are ready.", name: "synthetic-sketchbook.txt")
        store.evolution.confirmRole(.beacon)
        let question = "Help me use today's time on Juniper, using the note."
        var results: [[String: Any]] = []
        func record(_ failure: String? = nil) throws {
            var report: [String: Any] = ["schema": "archi-assistance-behavior/v1", "source": "authored synthetic sketchbook note",
                "route": "local", "contextEnabled": false, "steps": results,
                "styleJudgment": "Inspect answers alongside the captured settings; transport checks alone do not establish style quality."]
            if let failure { report["failure"] = failure }
            try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
                .write(to: output.appendingPathComponent("behavior.json"))
        }
        do {
            store.connectAssistant()
            try await wait(seconds: 30) { store.connectionState != .connecting }
            guard store.connectionState == .ready else { throw NSError(domain: "AssistanceBehavior", code: 1, userInfo: [NSLocalizedDescriptionKey: store.connectionMessage]) }
            let cases: [(String, EvolutionHelpStyle, String)] = [
                ("ordered-help", .stepByStep, question),
                ("reflective-help", .reflective, question),
                ("current-override", .stepByStep, question + " For this answer, use exactly one sentence, with no list or numbered steps.")
            ]
            for (name, style, prompt) in cases {
                store.evolution.confirmHelpStyle(style)
                store.prompt = prompt
                store.submit()
                try await wait(seconds: 190) { !store.isWorking }
                let lane = try XCTUnwrap(store.compareResults[.qwen])
                let receipt = try XCTUnwrap(lane.receipt)
                results.append(["name": name, "prompt": prompt, "answer": lane.text,
                    "state": lane.state.rawValue, "activity": store.assistantActivity.rawValue,
                    "settings": receipt.settings?.summary ?? "absent", "helpStyle": receipt.settings?.helpStyle?.rawValue ?? "absent",
                    "inputContract": receipt.inputContract, "inputDigest": receipt.inputDigest,
                    "model": receipt.modelIdentity ?? "unavailable", "status": lane.status,
                    "attempts": (receipt.localInvocations ?? []).map(\.rawValue),
                    "elapsedMilliseconds": receipt.elapsedMilliseconds ?? 0])
                try record()
                XCTAssertEqual(lane.state, .complete, lane.status)
                XCTAssertEqual(store.assistantActivity, .ready)
                XCTAssertEqual(receipt.settings?.helpStyle, style)
                XCTAssertEqual(receipt.localInvocations, [.reasoning])
                XCTAssertEqual(receipt.inputContract, "native-assistant-input/v3")
                XCTAssertFalse(lane.text.isEmpty)
                XCTAssertTrue(lane.text.lowercased().contains("tree") || lane.text.lowercased().contains("draw"), lane.text)
                XCTAssertTrue(store.compareResults[.codex] == nil)
                if name == "current-override" {
                    var sentences = 0
                    lane.text.enumerateSubstrings(in: lane.text.startIndex..., options: .bySentences) { _, _, _, _ in sentences += 1 }
                    XCTAssertEqual(sentences, 1, lane.text)
                    XCTAssertFalse(lane.text.contains("\n"), lane.text)
                }
            }
            XCTAssertNotEqual(results[0]["answer"] as? String, results[1]["answer"] as? String)
            XCTAssertNotEqual(results[0]["inputDigest"] as? String, results[1]["inputDigest"] as? String)
            await store.shutdownAssistant()
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("unused-preferences.json").path))
        } catch {
            try? record(String(describing: error))
            await store.shutdownAssistant()
            throw error
        }
    }

    @MainActor private func wait(seconds: Double, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { throw NSError(domain: "AssistanceBehavior", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bounded local diagnostic timed out"]) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
