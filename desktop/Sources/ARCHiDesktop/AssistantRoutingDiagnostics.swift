import Foundation

/// Explicit live acceptance through the production Store, using synthetic text only.
/// It neither reads the GUI's shared copy nor writes preferences or session history.
@MainActor
enum AssistantRoutingDiagnostics {
    static func run() async -> Bool {
        let store = CompanionStore(preferenceURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("archi-routing-diagnostic-\(UUID().uuidString).json"))
        var report: [String: JSONValue] = [
            "schema": .string("archi-native-routing-check/v1"),
            "privateSourceUsed": .bool(false), "passed": .bool(false),
            "startedAt": .string(ISO8601DateFormatter().string(from: Date()))
        ]
        let start = ContinuousClock.now
        do {
            let source = "Option A: Rehearsal is Monday at 09:00 in Oak.\nOption B: Rehearsal is Friday at 15:30 in Cedar."
            store.share(text: source, name: "synthetic-routing-selection.txt")
            store.selectText(range: (source as NSString).range(of: "Option B: Rehearsal is Friday at 15:30 in Cedar."),
                             sourceRevision: store.sourceRevision)
            store.preferences.tone = "Direct"
            store.preferences.replyLength = 0.2
            store.prompt = "What are the rehearsal day, exact 24-hour time, and room in the selected passage? Answer only from that passage."
            store.connectAssistant(provider: .qwen)
            store.connectAssistant(provider: .codex)
            try await wait(seconds: 60) {
                AssistantProvider.allCases.allSatisfy { store.connection(for: $0) != .connecting }
            }
            guard AssistantProvider.allCases.allSatisfy({ store.connection(for: $0) == .ready }) else {
                throw RoutingDiagnosticFailure.notReady
            }
            let originalSelection = store.textSelection
            store.setAssistantRoute(.compare)
            let retained = originalSelection != nil && store.textSelection == originalSelection
            store.submit()
            try await wait(seconds: 190) { !store.isWorking }
            var allAnswersPassed = retained && !store.sessionContextEnabled
            report["lanes"] = .array(AssistantProvider.allCases.map { provider in
                let lane = store.compareResults[provider]
                let answer = lane?.text ?? ""
                let pass = lane?.state == .complete
                    && ["Friday", "15:30", "Cedar"].allSatisfy(answer.contains)
                    && !["Monday", "09:00", "Oak"].contains(where: answer.contains)
                allAnswersPassed = allAnswersPassed && pass
                return .object([
                    "provider": .string(provider.name), "answer": .string(answer),
                    "passed": .bool(pass), "state": .string(lane?.state.rawValue ?? "absent"),
                    "status": .string(lane?.status ?? store.message(for: provider)),
                    "requestID": lane?.receipt.map { .string($0.requestID) } ?? .null,
                    "inputDigest": lane?.receipt.map { .string($0.inputDigest) } ?? .null,
                    "modelIdentity": lane?.receipt?.modelIdentity.map(JSONValue.string) ?? .null
                ])
            })
            let local = store.compareResults[.qwen]?.receipt, codex = store.compareResults[.codex]?.receipt
            let sameInput = local != nil && codex != nil && local?.requestID == codex?.requestID
                && local?.inputDigest == codex?.inputDigest && local?.context == codex?.context
            report["sameCurrentInputAndTicket"] = .bool(sameInput)
            report["selectionPreservedAcrossIdleRouteChange"] = .bool(retained)
            report["sessionContextEnabled"] = .bool(store.sessionContextEnabled)
            // An idle route change keeps both independently owned clients ready.
            store.setAssistantRoute(.local)
            let bothStillReady = AssistantProvider.allCases.allSatisfy { store.connection(for: $0) == .ready }
            report["idleRouteChangeKeepsBothReady"] = .bool(bothStillReady)
            report["passed"] = .bool(allAnswersPassed && sameInput && bothStillReady)
        } catch {
            report["error"] = .string(String(describing: error))
            report["connections"] = .array(AssistantProvider.allCases.map {
                .object(["provider": .string($0.name), "state": .string(store.connection(for: $0).rawValue),
                         "message": .string(store.message(for: $0))])
            })
        }
        await store.shutdownAssistant()
        report["ownedConnectionsClosed"] = .bool(AssistantProvider.allCases.allSatisfy { store.connection(for: $0) == .disconnected })
        let elapsed = start.duration(to: .now)
        report["elapsedSeconds"] = .number(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let data = try? encoder.encode(JSONValue.object(report)) { print(String(decoding: data, as: UTF8.self)) }
        return report["passed"]?.bool == true
    }

    private static func wait(seconds: Int, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw RoutingDiagnosticFailure.timedOut }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private enum RoutingDiagnosticFailure: Error { case notReady, timedOut }
}
