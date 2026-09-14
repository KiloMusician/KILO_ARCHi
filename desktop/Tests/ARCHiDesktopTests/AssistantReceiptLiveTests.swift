import Foundation
import XCTest
@testable import ARCHiDesktop

/// Opt-in, one-generation receipt demonstration through the production store.
/// Uses only a disposable synthetic profile. This is not native UI qualification
/// or a reasoning benchmark, and it never invokes a hosted route.
final class AssistantReceiptLiveTests: XCTestCase {
    @MainActor
    func testOneLocalAnswerCarriesTerminalMetricsAndEvidenceDecisions() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ARCHI_RECEIPT_LIVE"] == "1",
              let outputPath = environment["ARCHI_RECEIPT_LIVE_OUTPUT"], !outputPath.isEmpty else {
            throw XCTSkip("Set ARCHI_RECEIPT_LIVE=1 and ARCHI_RECEIPT_LIVE_OUTPUT for one explicit local Qwen generation.")
        }
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("archi-receipt-live-\(UUID())")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        let preferenceURL = profile.appendingPathComponent("preferences.json")
        var preferences = CompanionPreferences()
        preferences.tone = "Direct"; preferences.replyLength = 0.2; preferences.reduceMotion = true
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: Date())
        try NativePreferenceDocument(preferences: preferences, qiMon: kin).encoded().write(to: preferenceURL)
        let local = HamptonReasonsAssistant(contextEnabled: false)
        let refused = AssistantReceiptNoExternalClient()
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: local,
            assistantFactory: { _, _ in refused }, allowsPlay: false)
        var checks: [String: Bool] = [:]
        var report: [String: Any] = [
            "schema": "archi-assistant-receipt-local-demonstration/v1",
            "scope": "One synthetic 2+2 question through the production store; receipt accounting only, not native UI QA or a reasoning benchmark.",
            "route": "local", "configuredModel": QwenAssistant.defaultModel,
            "maximumGenerations": 1, "contextEnabled": false, "sourceFree": true,
            "receiptAccountingPassed": NSNull(), "currentInstructionFollowed": NSNull()
        ]
        func verify(_ name: String, _ condition: Bool, fatal: Bool = false) throws {
            checks[name] = condition
            if fatal && !condition {
                throw NSError(domain: "AssistantReceiptLive", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Receipt check failed: \(name)"])
            }
        }
        func saveReport() throws {
            report["checks"] = checks
            report["externalCalls"] = refused.calls
            report["attemptedRoles"] = local.snapshot.attemptedInvocations.map(\.rawValue)
            report["invocationCount"] = local.snapshot.invocations.count
            report["validatedReceiptCount"] = local.snapshot.receipts.count
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("assistant-receipt-live.json"), options: .atomic)
        }
        do {
            try verify("isolatedSyntheticProfile", store.activeQiMon == kin && store.keptLessons.isEmpty, fatal: true)
            try verify("noSharedSource", store.sourceName == nil && store.sharedText.isEmpty, fatal: true)
            try verify("contextInitiallyDisabled", !local.contextEnabled, fatal: true)
            store.connectAssistant(provider: .qwen)
            try await wait(seconds: 30) { store.connection(for: .qwen) != .connecting }
            try verify("localConnectionReady", store.connection(for: .qwen) == .ready, fatal: true)
            store.prompt = "What is 2 + 2? For this current question, return exactly 4 as your answer."
            store.submit()
            try await wait(seconds: 180) { !store.isWorking }

            let lane = try XCTUnwrap(store.compareResults[.qwen])
            let receipt = try XCTUnwrap(lane.receipt)
            let snapshot = local.snapshot
            report["answer"] = lane.text
            report["laneState"] = lane.state.rawValue
            report["requestID"] = receipt.requestID
            report["inputDigest"] = receipt.inputDigest
            report["contextDigest"] = EvolutionRequestBinding(receipt: receipt).contextDigest
            report["sourceDigest"] = receipt.sourceDigest as Any? ?? NSNull()
            report["taskElapsedMilliseconds"] = receipt.elapsedMilliseconds as Any? ?? NSNull()
            try verify("laneAndReceiptComplete", lane.state == .complete && receipt.state == .complete)
            try verify("answerIsFour", lane.text.trimmingCharacters(in: .whitespacesAndNewlines) == "4")
            report["currentInstructionFollowed"] = checks["answerIsFour"]!
            try verify("oneLocalReasoningCall", receipt.localInvocations == [.reasoning]
                && snapshot.attemptedInvocations == [.reasoning])
            try verify("oneValidatedReasoningReceipt", snapshot.receipts.count == 1
                && snapshot.receipts.first?.role == .reasoning)
            try verify("oneCompletedInvocation", snapshot.invocations.count == 1
                && snapshot.invocations.first?.role == .reasoning
                && snapshot.invocations.first?.outcome == .completed)
            try verify("laneCapturedInvocation", receipt.localInvocationReceipts == snapshot.invocations)
            try verify("admissionAccepted", receipt.admissionOutcome?.status == .accepted)
            try verify("noExternalRoute", refused.calls == 0 && store.compareResults[.codex] == nil)

            let invocation = try XCTUnwrap(snapshot.invocations.first)
            let roleReceipt = try XCTUnwrap(snapshot.receipts.first)
            let model = try XCTUnwrap(invocation.model)
            let metrics = try XCTUnwrap(invocation.metrics)
            report["model"] = ["name": model.name, "family": model.family,
                "parameterSize": model.parameterSize, "quantization": model.quantization, "digest": model.digest]
            report["invocation"] = [
                "requestID": invocation.id, "outcome": invocation.outcome.rawValue,
                "inputDigest": invocation.inputDigest, "outputDigest": invocation.outputDigest as Any? ?? NSNull(),
                "systemDigest": invocation.systemDigest, "schemaDigest": invocation.schemaDigest,
                "policyVersion": invocation.policyVersion, "contextTokenLimit": invocation.contextTokenLimit,
                "outputTokenLimit": invocation.outputTokenLimit, "temperature": invocation.temperature,
                "elapsedMilliseconds": invocation.elapsedMilliseconds as Any? ?? NSNull()
            ]
            report["metrics"] = [
                "inputTokens": metrics.inputTokens as Any? ?? NSNull(),
                "outputTokens": metrics.outputTokens as Any? ?? NSNull(),
                "totalNanoseconds": metrics.totalNanoseconds as Any? ?? NSNull(),
                "loadNanoseconds": metrics.loadNanoseconds as Any? ?? NSNull(),
                "promptEvaluationNanoseconds": metrics.promptEvaluationNanoseconds as Any? ?? NSNull(),
                "evaluationNanoseconds": metrics.evaluationNanoseconds as Any? ?? NSNull(),
                "malformedFields": metrics.malformedFields
            ]
            try verify("positiveMeasuredInputAndOutputTokens", (metrics.inputTokens ?? 0) > 0 && (metrics.outputTokens ?? 0) > 0)
            try verify("noMalformedMetrics", metrics.malformedFields.isEmpty)
            try verify("validatedReceiptRetainsMetrics", roleReceipt.id == invocation.id && roleReceipt.metrics == metrics)
            try verify("validatedReceiptRetainsModel", roleReceipt.model == model)

            let evidence = try XCTUnwrap(receipt.evidence)
            report["evidence"] = [
                "version": evidence.version, "contextEnabled": evidence.contextEnabled,
                "candidateDispatchedCount": evidence.candidates.dispatchedIDs.count,
                "reminderDispatchedCount": evidence.reminders.dispatchedIDs.count,
                "reasoningSourceCount": evidence.reasoningSourceIDsDispatched.count,
                "reasoningMemoryCount": evidence.reasoningMemoryIDsDispatched.count,
                "conversationDispatchedCount": evidence.conversationDispatchedCount as Any? ?? NSNull(),
                "sourceCitationCount": evidence.sourceIDsCited.count,
                "memoryCitationCount": evidence.memoryIDsCited.count,
                "omissionReasons": evidence.omissions.map { $0.kind.rawValue + ":" + $0.reason.rawValue }
            ]
            try verify("contextDisabledInEvidence", !evidence.contextEnabled
                && evidence.omissions.contains { $0.kind == .context && $0.reason == .disabled })
            try verify("noOptionalSelectors", evidence.candidates.dispatchedIDs.isEmpty
                && evidence.reminders.dispatchedIDs.isEmpty)
            try verify("noRetainedOrConversationInputs", evidence.reasoningMemoryIDsDispatched.isEmpty
                && evidence.lessonIDsAvailable.isEmpty && evidence.conversationDispatchedCount == 0
                && snapshot.records.isEmpty && receipt.sourceDigest == nil)
            try verify("noAutomaticGrowth", store.evolution.usefulReceipts.isEmpty && store.evolution.kinGrowthRecord == nil)
            // A formatting/instruction failure must not hide the accounting that
            // this run was intended to inspect. Keep the strict answer check,
            // collect all receipt evidence, then fail for every false check.
            let failedChecks = checks.filter { !$0.value }.map(\.key).sorted()
            report["receiptAccountingPassed"] = !checks.contains { $0.key != "answerIsFour" && !$0.value }
            report["failedChecks"] = failedChecks
            guard failedChecks.isEmpty else {
                throw NSError(domain: "AssistantReceiptLive", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Receipt checks failed: \(failedChecks.joined(separator: ", "))"])
            }
            report["result"] = "passed"
            try saveReport()
            await store.shutdownAssistant()
        } catch {
            report["result"] = "failed"
            report["failure"] = error.localizedDescription
            try? saveReport()
            store.cancelWork()
            await store.shutdownAssistant()
            throw error
        }
    }

    @MainActor private func wait(seconds: Int, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "AssistantReceiptLive", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "The bounded local operation did not finish in \(seconds) seconds."])
    }
}

@MainActor private final class AssistantReceiptNoExternalClient: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.configuration
    }
    func disconnect() {}
    func shutdown() async {}
}
