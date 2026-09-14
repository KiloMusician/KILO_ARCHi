import Foundation
import XCTest
@testable import ARCHiDesktop

/// Opt-in, one-generation local check. This is a scripted synthetic user review,
/// not personal-profile growth, a human usefulness judgment, or native UI QA.
final class EverydayGrowthLiveTests: XCTestCase {
    @MainActor
    func testOrdinaryChatLessonUseCanBeReviewedKeptAndReloaded() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ARCHI_EVERYDAY_GROWTH_LIVE"] == "1",
              let outputPath = environment["ARCHI_EVERYDAY_GROWTH_OUTPUT"], !outputPath.isEmpty else {
            throw XCTSkip("Set ARCHI_EVERYDAY_GROWTH_LIVE=1 and ARCHI_EVERYDAY_GROWTH_OUTPUT for one explicit local Qwen generation.")
        }
        let output = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("archi-everyday-growth-live-\(UUID())")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        let url = profile.appendingPathComponent("preferences.json")
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: Date())
        var preferences = CompanionPreferences()
        preferences.tone = "Direct"; preferences.replyLength = 0.2; preferences.reduceMotion = true
        try NativePreferenceDocument(preferences: preferences, qiMon: kin).encoded().write(to: url)
        let local = HamptonReasonsAssistant(contextEnabled: false)
        let refused = EverydayGrowthNoExternalClient()
        let store = CompanionStore(preferenceURL: url, assistant: local,
            assistantFactory: { _, _ in refused }, allowsPlay: false)
        var report: [String: Any] = [
            "schema": "archi-everyday-growth-local-demonstration/v1",
            "scope": "One synthetic ordinary conversation with scripted explicit lesson-use and body confirmations. Not real-owner learning or native UI validation.",
            "route": "local", "configuredModel": QwenAssistant.defaultModel,
            "sourceFree": true, "maximumGenerations": 1, "externalCalls": 0,
            "feedback": "scripted synthetic confirmation after checked answer and citation"
        ]
        func saveReport() throws {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("everyday-growth-live.json"), options: .atomic)
        }
        do {
            store.beginLessonCorrection()
            var draft = try XCTUnwrap(store.lessonDraft)
            draft.topic = "drawing"
            draft.text = "For drawing, I prefer starting with my blue pencil. Recommend it as my first tool unless I explicitly ask for something else."
            draft.source = nil
            try require(store.keepLesson(draft), store.lessonMessage)
            let snapshot = LessonSnapshot(lesson: try XCTUnwrap(store.keptLessons.first))
            try require(store.activeQiMon == kin, "The disposable profile must retain the same KIN identity.")
            try require(store.sourceName == nil && store.sharedText.isEmpty, "This task must remain source-free.")
            store.connectAssistant(provider: .qwen)
            try await wait(seconds: 30) { store.connection(for: .qwen) != .connecting }
            try require(store.connection(for: .qwen) == .ready, store.connectionMessage)
            store.prompt = "Which tool should I use to begin drawing today? Answer in one short sentence."
            report["question"] = store.prompt
            store.submit()
            try await wait(seconds: 180) { !store.isWorking }
            let lane = try XCTUnwrap(store.compareResults[.qwen])
            let receipt = try XCTUnwrap(lane.receipt)
            report["answer"] = lane.text
            report["state"] = lane.state.rawValue
            report["status"] = lane.status
            report["model"] = receipt.modelIdentity ?? "unavailable"
            report["requestID"] = receipt.requestID
            report["inputDigest"] = receipt.inputDigest
            report["contextDigest"] = EvolutionRequestBinding(receipt: receipt).contextDigest
            report["sourceDigest"] = receipt.sourceDigest as Any? ?? NSNull()
            report["attempts"] = receipt.localInvocations?.map(\.rawValue) ?? []
            report["elapsedMilliseconds"] = receipt.elapsedMilliseconds as Any? ?? NSNull()
            report["citedLessonIDs"] = receipt.usedLessonIDs
            try saveReport()
            try require(lane.state == .complete && receipt.state == .complete, lane.status)
            try require(receipt.sourceDigest == nil, "Ordinary chat must not carry a document fingerprint.")
            try require(receipt.localInvocations == [.reasoning], "Only one local reasoning invocation is allowed.")
            try require(refused.calls == 0 && store.compareResults[.codex] == nil, "No external route may run.")
            try require(lane.text.localizedCaseInsensitiveContains("blue pencil"), "The response did not apply the synthetic tool preference.")
            try require(store.reviewableEvolutionLessons(provider: .qwen, requestID: receipt.requestID) == [snapshot],
                        "The validated answer must cite the exact currently kept lesson.")
            try require(store.evolution.usefulReceipts.isEmpty && store.evolution.kinGrowthRecord == nil,
                        "The model alone cannot create a learning confirmation or change the body.")
            try require(store.confirmLessonHelped(provider: .qwen, requestID: receipt.requestID, snapshot: snapshot),
                        "Scripted lesson-use confirmation was not admitted.")
            let evidence = try XCTUnwrap(store.evolution.usefulReceipts.first)
            try require(evidence.requestBinding == EvolutionRequestBinding(receipt: receipt) && evidence.sourceDigest == nil,
                        "The retained evidence must bind the exact source-free request.")
            try require(store.previewKinGrowth(receiptID: evidence.requestID), "First Light invitation was not admitted.")
            try require(store.keepKinGrowth(), "Scripted body confirmation was not admitted.")
            try require(store.presentationForm == .kin && store.cursorPresentationForm == .kinSeed,
                        "First Light body and persistent Seed cursor must share KIN.")
            try require(store.evolution.save(), store.evolution.status)
            let kept = try XCTUnwrap(store.evolution.kinGrowthRecord)
            await store.shutdownAssistant()
            let reopened = CompanionStore(preferenceURL: url, assistant: refused,
                assistantFactory: { _, _ in refused }, allowsPlay: false)
            do {
                try require(reopened.evolution.load(), reopened.evolution.status)
                try require(reopened.activeQiMon == kin && reopened.evolution.kinGrowthRecord == kept,
                            "Reload must retain identity and the reviewed milestone.")
                try require(reopened.presentationForm == .kin && reopened.cursorPresentationForm == .kinSeed,
                            "Reload must preserve body/cursor continuity.")
                try require(reopened.reviewableEvolutionLessons(provider: .qwen, requestID: receipt.requestID).isEmpty,
                            "Saved history cannot recreate a live answer.")
                try require(refused.calls == 0, "Save and Load must not invoke a provider.")
                report["scriptedReviewKeepSaveReopen"] = "passed"
                report["sameKINAndSeedCursor"] = true
                report["growthRecordVersion"] = kept.version
                report["evolutionSchema"] = EvolutionStore.schema
                try saveReport()
                await reopened.shutdownAssistant()
            } catch {
                await reopened.shutdownAssistant()
                throw error
            }
        } catch {
            store.cancelWork()
            report["failure"] = error.localizedDescription
            report["externalCalls"] = refused.calls
            report["attemptsAtFailure"] = local.snapshot.attemptedInvocations.map(\.rawValue)
            try? saveReport()
            await store.shutdownAssistant()
            throw error
        }
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw NSError(domain: "EverydayGrowthLive", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
    @MainActor private func wait(seconds: Int, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "EverydayGrowthLive", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "The bounded local operation did not finish in \(seconds) seconds."])
    }
}

@MainActor private final class EverydayGrowthNoExternalClient: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.configuration
    }
    func disconnect() {}
    func shutdown() async {}
}
