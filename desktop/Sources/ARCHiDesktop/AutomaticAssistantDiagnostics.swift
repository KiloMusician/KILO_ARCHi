import Foundation

/// Explicit local-only acceptance of the production request owner. The success
/// scenario uses local Qwen; the outage and external probe never call providers.
@MainActor
enum AutomaticAssistantDiagnostics {
    static func run() async -> Bool {
        var steps: [JSONValue] = []
        for forceLocalUnavailable in [false, true] {
            let externalProbe = ExternalDiagnosticProbe()
            let store = CompanionStore(preferenceURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("archi-auto-check-\(UUID().uuidString).json"),
                assistant: forceLocalUnavailable ? UnavailableDiagnosticAssistant() : HamptonReasonsAssistant(),
                assistantFactory: { provider, model in
                    if provider == .qwen { return HamptonReasonsAssistant(model: model) }
                    return externalProbe
                })
            store.setAssistantRoute(.automatic)
            store.share(text: "The rehearsal is Friday at 15:30 in Cedar.", name: "synthetic-automatic.txt")
            store.prompt = "Give the rehearsal day, exact 24-hour time, and room in one sentence."
            store.preferences.tone = "Direct"
            store.preferences.replyLength = 0.2
            let started = ContinuousClock.now
            store.submit()
            let deadline = started.advanced(by: .seconds(185))
            while store.isWorking && ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if store.isWorking { store.cancelWork(reason: "Synthetic check reached its deadline.") }
            let result = store.compareResults[.qwen]
            let answer = result?.text ?? ""
            let noExternalWork = externalProbe.connectionAttempts == 0 && externalProbe.requestAttempts == 0
                && store.compareResults[.codex] == nil && store.assistantProvider == .qwen
            let expectedOutcome = forceLocalUnavailable
                ? result?.state == .failed && answer.isEmpty && result?.receipt?.requestStarted == false
                : result?.state == .complete && ["Friday", "15:30", "Cedar"].allSatisfy(answer.contains)
                    && result?.receipt?.admissionOutcome?.status == .accepted
            steps.append(.object([
                "scenario": .string(forceLocalUnavailable ? "injected-local-unavailable-stays-local" : "real-local-success-no-external"),
                "passed": .bool(expectedOutcome && noExternalWork), "answer": .string(answer),
                "provider": .string(AssistantProvider.qwen.name),
                "externalConnectionAttempts": .number(Double(externalProbe.connectionAttempts)),
                "externalRequestAttempts": .number(Double(externalProbe.requestAttempts)),
                "lanes": .array(store.resultProviders.compactMap { item in
                    guard let lane = store.compareResults[item] else { return nil }
                    return .object(["provider": .string(item.name), "state": .string(lane.state.rawValue),
                        "status": .string(lane.status), "attempted": .bool(lane.receipt?.requestStarted == true),
                        "calls": .string(lane.receipt?.workSummary ?? "Unavailable"),
                        "routingReason": .string(lane.receipt?.routingReason ?? ""),
                        "admission": lane.receipt?.admissionOutcome.map { .string($0.summary) } ?? .null])
                })]))
            await store.shutdownAssistant()
        }
        let passed = steps.allSatisfy { $0["passed"]?.bool == true }
        let report: JSONValue = .object(["schema": .string("archi-automatic-assistant-check/v2"),
            "privateSourceUsed": .bool(false), "savedProfileUsed": .bool(false),
            "liveExternalProvidersUsed": .bool(false),
            "passed": .bool(passed), "steps": .array(steps)])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let data = try? encoder.encode(report) { print(String(decoding: data, as: UTF8.self)) }
        return passed
    }
}

@MainActor
private final class UnavailableDiagnosticAssistant: AssistantClient {
    func connect() async throws { throw QwenFailure.unavailable }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        throw QwenFailure.unavailable
    }
    func disconnect() {}
}

/// Fail closed even if a future regression attempts an external lane during a
/// local-only smoke check. The counters expose the regression without disclosure.
@MainActor
private final class ExternalDiagnosticProbe: AssistantClient {
    private(set) var connectionAttempts = 0
    private(set) var requestAttempts = 0
    func connect() async throws {
        connectionAttempts += 1
        throw AssistantFailure.configuration
    }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requestAttempts += 1
        throw AssistantFailure.configuration
    }
    func disconnect() {}
}
