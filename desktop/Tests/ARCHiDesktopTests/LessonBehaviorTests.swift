import Foundation
import XCTest
@testable import ARCHiDesktop

final class LessonBehaviorTests: XCTestCase {
    /// One local answer and explicit synthetic feedback in an isolated profile.
    /// The model's citation is never treated as the user's judgment.
    @MainActor
    func testReviewedLessonUseSurvivesReopenWithoutChangingTheParticleBody() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_LESSON_DEVELOPMENT_LIVE_DIR"] else {
            throw XCTSkip("Set ARCHI_LESSON_DEVELOPMENT_LIVE_DIR for one bounded synthetic local lesson-use demonstration.")
        }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let profile = output.appendingPathComponent("synthetic-profile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        let url = profile.appendingPathComponent("preferences.json")
        let first = CompanionStore(preferenceURL: url)
        first.beginLessonCorrection()
        var draft = try XCTUnwrap(first.lessonDraft)
        draft.topic = "drawing"
        draft.text = "For drawing, I prefer starting with my blue pencil. Recommend it as my first tool unless I explicitly ask for something else."
        XCTAssertTrue(first.keepLesson(draft), first.lessonMessage)
        let lesson = LessonSnapshot(lesson: try XCTUnwrap(first.keptLessons.first))
        await first.shutdownAssistant()

        let store = CompanionStore(preferenceURL: url)
        store.chooseStartingForm(.particle)
        store.preferences.tone = "Direct"; store.preferences.replyLength = 0.2
        store.rememberPreferences = true; store.savePreferences()
        store.share(text: "Synthetic activity: spend ten minutes drawing a leaf. Available tools are blue pencil and charcoal.", name: "drawing-exercise.txt")
        let placement = store.placementRevision, position = store.position
        var report: [String: Any] = ["scope": "One synthetic local task and scripted user confirmation, not a human learning assessment.", "source": "synthetic drawing exercise", "feedback": "scripted explicit confirmation", "route": "local"]
        func saveReport() throws {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("lesson-development-live.json"), options: .atomic)
        }
        do {
            store.connectAssistant()
            try await wait(seconds: 30) { store.connectionState != .connecting }
            guard store.connectionState == .ready else {
                throw NSError(domain: "LessonDevelopmentLive", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: store.connectionMessage])
            }
            store.prompt = "Which tool should I start with for drawing today? Give one short sentence."
            store.submit()
            try await wait(seconds: 190) { !store.isWorking }
            let lane = try XCTUnwrap(store.compareResults[.qwen]), receipt = try XCTUnwrap(lane.receipt)
            report["answer"] = lane.text; report["state"] = lane.state.rawValue
            report["model"] = receipt.modelIdentity ?? "unavailable"
            report["attempts"] = (receipt.localInvocations ?? []).map(\.rawValue)
            report["elapsedMilliseconds"] = receipt.elapsedMilliseconds ?? 0
            report["citedLessonIDs"] = receipt.usedLessonIDs
            try saveReport()
            XCTAssertEqual(lane.state, .complete, lane.status)
            XCTAssertEqual(receipt.localInvocations, [.reasoning])
            XCTAssertTrue(lane.text.localizedCaseInsensitiveContains("blue pencil"), lane.text)
            XCTAssertTrue(store.evolution.usefulReceipts.isEmpty, "An answer and citation cannot write development feedback")
            XCTAssertEqual(store.reviewableEvolutionLessons(provider: .qwen, requestID: receipt.requestID), [lesson])
            XCTAssertTrue(store.confirmLessonHelped(provider: .qwen, requestID: receipt.requestID, snapshot: lesson))
            let reference = try XCTUnwrap(store.evolution.usefulReceipts.first?.lessonUse)
            XCTAssertTrue(reference.matches(snapshot: lesson))
            XCTAssertTrue(store.evolution.save(), store.evolution.status)
            XCTAssertEqual(store.preferences.form, .particle)
            XCTAssertEqual(store.placementRevision, placement); XCTAssertEqual(store.position, position)
            XCTAssertTrue(store.evolution.history.isEmpty)
            await store.shutdownAssistant()

            let reopened = CompanionStore(preferenceURL: url)
            XCTAssertTrue(reopened.evolution.load(), reopened.evolution.status)
            XCTAssertEqual(reopened.evolution.usefulReceipts.first?.lessonUse, reference)
            XCTAssertEqual(reopened.preferences.form, .particle)
            XCTAssertEqual(reopened.keptLessons.map(LessonSnapshot.init(lesson:)), [lesson])
            reopened.evolution.withdrawLessonUse(requestID: try XCTUnwrap(reopened.evolution.usefulReceipts.first?.requestID))
            XCTAssertNil(reopened.evolution.usefulReceipts.first?.lessonUse)
            XCTAssertEqual(reopened.evolution.usefulReceipts.count, 1)
            report["explicitReviewSaveReopenWithdraw"] = "passed"
            report["sameParticleBodyAndPlacement"] = true
            try saveReport()
            await reopened.shutdownAssistant()
        } catch {
            report["failure"] = String(describing: error); try? saveReport()
            await store.shutdownAssistant()
            throw error
        }
    }

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

    /// Three opt-in calls through the real store, with disposable saved lessons.
    /// Store recreation checks disk continuity; it is not a native process-restart test.
    @MainActor
    func testReopenedLessonRevisionAndWithdrawalThroughLocalAnswers() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_LESSON_LIFECYCLE_LIVE_DIR"] else {
            throw XCTSkip("Set ARCHI_LESSON_LIFECYCLE_LIVE_DIR for three local lesson lifecycle requests.")
        }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let profile = output.appendingPathComponent("synthetic-profile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        let url = profile.appendingPathComponent("preferences.json")
        let first = CompanionStore(preferenceURL: url)
        first.beginLessonCorrection()
        var draft = try XCTUnwrap(first.lessonDraft)
        draft.topic = "drawing"
        draft.text = "For drawing, my preferred first tool is my blue pencil. Recommend it unless I explicitly ask for something else."
        XCTAssertTrue(first.keepLesson(draft), first.lessonMessage)
        let original = try XCTUnwrap(first.keptLessons.first)
        await first.shutdownAssistant()

        let store = CompanionStore(preferenceURL: url)
        XCTAssertEqual(store.keptLessons, [original])
        store.setAssistantRoute(.automatic)
        store.preferences.tone = "Direct"
        store.preferences.replyLength = 0.2
        let initialForm = store.preferences.form, initialPosition = store.position
        var steps: [[String: Any]] = []
        var report: [String: Any] = ["schema": "archi-local-lesson-lifecycle/v1",
            "scope": "Synthetic saved correction, store recreation, revision and withdrawal through production local requests. Not a native process restart or general learning benchmark.",
            "reopenedFromDisk": true, "externalRequests": 0, "userProfileTouched": false,
            "sharedDocument": false, "temporaryExcerptSelection": false]
        func save() throws {
            report["steps"] = steps
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("behavior.json"), options: .atomic)
        }
        func ask(_ name: String, _ question: String) async throws -> String {
            store.prompt = question
            store.submit()
            try await wait(seconds: 190) { !store.isWorking }
            let lane = try XCTUnwrap(store.compareResults[.qwen])
            let receipt = try XCTUnwrap(lane.receipt)
            steps.append(["step": name, "question": question, "answer": lane.text,
                "state": lane.state.rawValue, "status": lane.status,
                "lessons": receipt.localLessons.map { ["id": $0.id, "revision": String($0.revision), "text": $0.text] },
                "lessonDigest": receipt.localLessonDigest ?? "absent",
                "conversationCount": receipt.localConversationCount,
                "localInvocations": (receipt.localInvocations ?? []).map(\.rawValue),
                "elapsedMilliseconds": receipt.elapsedMilliseconds ?? 0,
                "model": receipt.modelIdentity ?? "unavailable"])
            try save()
            guard lane.state == .complete else {
                throw NSError(domain: "LessonLifecycle", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: lane.status])
            }
            XCTAssertEqual(receipt.localInvocations, [.reasoning])
            XCTAssertEqual(receipt.localConversationCount, 0, "A prior lesson's derived history must be revoked")
            XCTAssertEqual(store.connection(for: .codex), .disconnected)
            XCTAssertNil(store.compareResults[.codex])
            print("Local lesson lifecycle: \(name) · \(lane.state.rawValue)")
            return lane.text
        }
        do {
            let prompt = "Which tool should I start with for drawing today? Give one short sentence."
            let recalled = try await ask("recall-after-store-recreation", prompt)
            XCTAssertTrue(recalled.localizedCaseInsensitiveContains("blue pencil"), recalled)
            XCTAssertEqual(store.compareResults[.qwen]?.receipt?.localLessons, [LessonSnapshot(lesson: original)])
            XCTAssertEqual(store.localConversation.exchanges.count, 1)

            store.beginLessonCorrection(for: .qwen, revisingID: original.id)
            var revisedDraft = try XCTUnwrap(store.lessonDraft)
            revisedDraft.text = "For drawing, my preferred first tool is charcoal. Recommend it unless I explicitly ask for something else."
            XCTAssertTrue(store.keepLesson(revisedDraft), store.lessonMessage)
            let revised = try XCTUnwrap(store.keptLessons.first)
            XCTAssertEqual(revised.id, original.id)
            XCTAssertEqual(revised.revision, original.revision + 1)
            XCTAssertTrue(store.localConversation.exchanges.isEmpty)
            XCTAssertTrue(store.nextReplyConversation.isEmpty)
            let revisionReadback = CompanionStore(preferenceURL: url)
            XCTAssertEqual(revisionReadback.keptLessons, [revised])
            await revisionReadback.shutdownAssistant()
            report["revisionSavedAndPriorHistoryCleared"] = true
            let corrected = try await ask("revised-guidance", prompt)
            XCTAssertTrue(corrected.localizedCaseInsensitiveContains("charcoal"), corrected)
            XCTAssertFalse(corrected.localizedCaseInsensitiveContains("blue pencil"), corrected)
            XCTAssertEqual(store.compareResults[.qwen]?.receipt?.localLessons, [LessonSnapshot(lesson: revised)])
            XCTAssertEqual(store.localConversation.exchanges.count, 1)

            XCTAssertTrue(store.withdrawLesson(id: revised.id, expectedRevision: store.lessonRevision), store.lessonMessage)
            XCTAssertTrue(store.localConversation.exchanges.isEmpty)
            XCTAssertTrue(store.nextReplyConversation.isEmpty)
            let withdrawnReadback = CompanionStore(preferenceURL: url)
            XCTAssertTrue(withdrawnReadback.keptLessons.isEmpty)
            await withdrawnReadback.shutdownAssistant()
            report["withdrawalSavedAndPriorHistoryCleared"] = true
            let forgotten = try await ask("after-withdrawal",
                "Using only a kept drawing lesson, tell me my preferred first tool. If no kept drawing lesson is supplied, reply exactly: No kept preference.")
            XCTAssertEqual(forgotten.trimmingCharacters(in: .whitespacesAndNewlines), "No kept preference.")
            XCTAssertTrue(try XCTUnwrap(store.compareResults[.qwen]?.receipt).localLessons.isEmpty)
            XCTAssertNil(store.compareResults[.qwen]?.receipt?.localLessonDigest)
            XCTAssertEqual(store.preferences.form, initialForm)
            XCTAssertEqual(store.position, initialPosition)
            report["appearanceAndPlacementUnchanged"] = true
            report["completedRequests"] = steps.count
            report["totalLocalInvocations"] = steps.reduce(0) { $0 + ($1["localInvocations"] as? [String] ?? []).count }
            await store.shutdownAssistant()
            try save()
        } catch {
            report["failure"] = String(describing: error)
            await store.shutdownAssistant()
            try? save()
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
