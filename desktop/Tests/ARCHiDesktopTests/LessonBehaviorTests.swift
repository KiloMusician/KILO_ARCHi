import Foundation
import XCTest
@testable import ARCHiDesktop

final class LessonBehaviorTests: XCTestCase {
    /// Three deliberate local calls. All lesson/question content is synthetic;
    /// no user settings, transcript, hosted provider or model download is used.
    @MainActor
    func testKeptCorrectionAfterReopenOverrideAndUnrelatedQuestion() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_LESSON_LIVE_DIR"] else {
            throw XCTSkip("Set ARCHI_LESSON_LIVE_DIR for the bounded local correction demonstration.")
        }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let preferenceURL = output.appendingPathComponent("synthetic-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: preferenceURL) }
        let first = CompanionStore(preferenceURL: preferenceURL)
        first.beginLessonCorrection()
        var draft = try XCTUnwrap(first.lessonDraft)
        draft.topic = "drawing"
        draft.text = "For drawing, I prefer starting with my blue pencil. Recommend it as my first tool unless I explicitly ask for something else."
        draft.reason = "I already have this tool ready and choosing supplies costs me time."
        XCTAssertTrue(first.keepLesson(draft), first.lessonMessage)
        let kept = try XCTUnwrap(first.keptLessons.first)
        await first.shutdownAssistant()

        let reopened = CompanionStore(preferenceURL: preferenceURL)
        XCTAssertEqual(reopened.keptLessons, [kept])
        reopened.preferences.tone = "Direct"
        reopened.preferences.replyLength = 0.2
        var results: [[String: Any]] = []
        func saveReport(failure: String? = nil) throws {
            var report: [String: Any] = ["schema": "archi-local-lesson-demonstration/v1",
                "route": "local", "source": "synthetic user-authored drawing preference",
                "reopenedFromDisk": true, "temporaryContextEnabled": false, "steps": results,
                "scope": "One literal-topic correction, a current override and an unrelated task. This is not a general memory-quality benchmark."]
            if let failure { report["failure"] = failure }
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("behavior.json"), options: .atomic)
        }
        do {
            reopened.connectAssistant()
            try await wait(seconds: 30) { reopened.connectionState != .connecting }
            guard reopened.connectionState == .ready else {
                throw NSError(domain: "LessonBehavior", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: reopened.connectionMessage])
            }
            let cases = [
                ("recall-after-reopen", "Which tool should I start with for drawing today? Give one short sentence."),
                ("current-override", "For drawing today, recommend charcoal instead of my usual pencil. Give one short sentence."),
                ("unrelated-task", "What is 2 plus 2? Reply with just the numeral.")
            ]
            let selectedCase = ProcessInfo.processInfo.environment["ARCHI_LESSON_LIVE_CASE"]
            for (name, prompt) in cases where selectedCase == nil || selectedCase == name {
                reopened.prompt = prompt
                reopened.submit()
                try await wait(seconds: 190) { !reopened.isWorking }
                let lane = try XCTUnwrap(reopened.compareResults[.qwen])
                let receipt = try XCTUnwrap(lane.receipt)
                results.append(["name": name, "question": prompt, "answer": lane.text,
                    "state": lane.state.rawValue, "status": lane.status,
                    "includedLessons": receipt.localLessons.map { ["topic": $0.topic, "revision": String($0.revision)] },
                    "localLessonDigest": receipt.localLessonDigest ?? "absent", "citedLessonIDs": receipt.usedLessonIDs,
                    "model": receipt.modelIdentity ?? "unavailable",
                    "attempts": (receipt.localInvocations ?? []).map(\.rawValue),
                    "elapsedMilliseconds": receipt.elapsedMilliseconds ?? 0])
                try saveReport()
                print("Local correction demonstration: \(name) · \(lane.state.rawValue)")
                XCTAssertEqual(lane.state, .complete, lane.status)
                XCTAssertEqual(receipt.localInvocations, [.reasoning])
                XCTAssertNil(reopened.compareResults[.codex])
                switch name {
                case "recall-after-reopen":
                    XCTAssertEqual(receipt.localLessons.map(\.id), [kept.id])
                    XCTAssertTrue(lane.text.localizedCaseInsensitiveContains("blue"), lane.text)
                    XCTAssertTrue(lane.text.localizedCaseInsensitiveContains("pencil"), lane.text)
                case "current-override":
                    XCTAssertEqual(receipt.localLessons.map(\.id), [kept.id])
                    XCTAssertTrue(lane.text.localizedCaseInsensitiveContains("charcoal"), lane.text)
                    // Judge the recommendation, not a harmless acknowledgement
                    // of the superseded preference (e.g. "Use charcoal today,
                    // overriding your usual blue pencil preference").
                    XCTAssertNotNil(lane.text.range(of: #"^(Use|Choose|Try|Start with) charcoal\b"#,
                        options: [.regularExpression, .caseInsensitive]), lane.text)
                default:
                    XCTAssertTrue(receipt.localLessons.isEmpty)
                    XCTAssertNil(receipt.localLessonDigest)
                    XCTAssertEqual(lane.text.trimmingCharacters(in: .whitespacesAndNewlines), "4")
                }
            }
            XCTAssertTrue(reopened.withdrawLesson(id: kept.id, expectedRevision: reopened.lessonRevision))
            XCTAssertTrue(CompanionStore(preferenceURL: preferenceURL).keptLessons.isEmpty)
            await reopened.shutdownAssistant()
        } catch {
            try? saveReport(failure: String(describing: error))
            await reopened.shutdownAssistant()
            throw error
        }
    }

    @MainActor private func wait(seconds: Double, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { throw NSError(domain: "LessonBehavior", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Bounded local correction demonstration timed out"]) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
