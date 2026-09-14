import Foundation
import XCTest
@testable import ARCHiDesktop

final class AssistantConversationBehaviorTests: XCTestCase {
    /// Explicit opt-in: three synthetic local requests, no user profile or cloud lane.
    @MainActor
    func testFollowUpAndCurrentOverrideThroughProductionStore() async throws {
        guard let directory = ProcessInfo.processInfo.environment["ARCHI_CONVERSATION_LIVE_DIR"] else {
            throw XCTSkip("Set ARCHI_CONVERSATION_LIVE_DIR for three synthetic local Qwen requests.")
        }
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = CompanionStore(preferenceURL: output.appendingPathComponent("unused-synthetic-preferences.json"))
        store.setAssistantRoute(.automatic)
        let questions = [
            "Draft exactly two short sentences inviting someone to a fictional planning session at Cedar on Friday at 14:00. Include the place, day and time.",
            "Make that one short sentence. Keep the place, day and time.",
            "For this reply only, change the session to Tuesday at 16:00. Keep the same place and return one short sentence."
        ]
        var turns: [[String: Any]] = []
        var report: [String: Any] = ["scope": "Three synthetic local continuation/override tasks; not a broad quality benchmark.",
            "externalRequests": 0, "sharedDocument": false, "keptLessons": false, "temporaryExcerptSelection": false]
        func save() throws {
            report["turns"] = turns
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("behavior.json"), options: .atomic)
        }
        do {
            for (index, question) in questions.enumerated() {
                store.prompt = question; store.submit()
                let deadline = Date().addingTimeInterval(190)
                while store.isWorking && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
                let lane = try XCTUnwrap(store.compareResults[.qwen])
                let receipt = try XCTUnwrap(lane.receipt)
                turns.append(["question": question, "answer": lane.text, "state": lane.state.rawValue,
                    "elapsedMilliseconds": receipt.elapsedMilliseconds ?? 0,
                    "localInvocations": (receipt.localInvocations ?? []).map(\.rawValue),
                    "conversationCount": receipt.localConversationCount,
                    "conversationDigest": receipt.localConversationDigest ?? "none",
                    "omittedConversationCount": receipt.localConversationOmittedCount,
                    "model": receipt.modelIdentity ?? "unknown",
                    "references": store.hamptonSnapshot.proposal?.sourceIDs ?? []])
                try save()
                guard lane.state == .complete else {
                    throw NSError(domain: "ARCHiConversationLive", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: lane.status])
                }
                XCTAssertEqual(receipt.localInvocations, [.reasoning])
                XCTAssertEqual(receipt.localConversationCount, index)
                XCTAssertTrue(lane.text.localizedCaseInsensitiveContains("Cedar"), lane.text)
                if index < 2 {
                    XCTAssertTrue(lane.text.localizedCaseInsensitiveContains("Friday"), lane.text)
                    XCTAssertTrue(lane.text.contains("14:00") || lane.text.localizedCaseInsensitiveContains("2 pm") || lane.text.localizedCaseInsensitiveContains("2:00 pm"), lane.text)
                } else {
                    XCTAssertTrue(lane.text.localizedCaseInsensitiveContains("Tuesday"), lane.text)
                    XCTAssertTrue(lane.text.contains("16:00") || lane.text.localizedCaseInsensitiveContains("4 pm") || lane.text.localizedCaseInsensitiveContains("4:00 pm"), lane.text)
                    XCTAssertFalse(lane.text.localizedCaseInsensitiveContains("Friday"), lane.text)
                }
                XCTAssertEqual(store.connection(for: .codex), .disconnected)
                XCTAssertTrue(store.keptLessons.isEmpty)
            }
            report["completedRequests"] = turns.count
            report["totalLocalInvocations"] = turns.reduce(0) { $0 + ($1["localInvocations"] as? [String] ?? []).count }
            store.startNewLocalConversation()
            XCTAssertTrue(store.localConversation.exchanges.isEmpty)
            XCTAssertTrue(store.nextReplyConversation.isEmpty)
            XCTAssertEqual(store.prompt, questions.last)
            report["newConversationClearedHistoryWithoutAnotherCall"] = true
            await store.shutdownAssistant()
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("unused-synthetic-preferences.json").path))
            try save()
        } catch {
            report["failure"] = String(describing: error)
            await store.shutdownAssistant()
            try? save()
            throw error
        }
    }
}
