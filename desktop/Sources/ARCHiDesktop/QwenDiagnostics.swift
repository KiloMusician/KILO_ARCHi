import Foundation

/// Explicit command-line checks use authored synthetic text only; ordinary launch never runs them.
@MainActor
enum QwenDiagnostics {
    static func run(live: Bool, cancel: Bool = false, model: String = QwenAssistant.defaultModel) async -> Bool {
        let client = QwenAssistant(model: model)
        let clock = ContinuousClock()
        let started = clock.now
        var report: [String: JSONValue] = [
            "schema": .string("archi-qwen-check/v1"), "provider": .string("ollama-loopback"),
            "model": .string(model),
            "mode": .string(cancel ? "live-cancel-on-first-update" : live ? "live-synthetic-selection" : "connection-only"),
            "startedAt": .string(ISO8601DateFormatter().string(from: Date())),
            "passed": .bool(false), "privateSourceUsed": .bool(false)
        ]
        do {
            try await client.connect()
            report["connected"] = .bool(true)
            if let metadata = client.metadata {
                report["installedModel"] = .object([
                    "name": .string(metadata.name), "family": .string(metadata.family),
                    "parameterSize": .string(metadata.parameterSize), "quantization": .string(metadata.quantization),
                    "digest": .string(metadata.digest)
                ])
            }
            if live {
                let source = "Option A: Rehearsal is Monday at 09:00 in Oak.\nOption B: Rehearsal is Friday at 15:30 in Cedar."
                let quote = "Option B: Rehearsal is Friday at 15:30 in Cedar."
                guard let selection = DocumentSelection(range: (source as NSString).range(of: quote), text: source, sourceRevision: 1) else {
                    throw QwenFailure.stopped
                }
                let request = AssistantRequest(
                    prompt: cancel ? "Explain the selected passage in several sentences." : "What are the rehearsal day, time, and room in the selected passage? Use the exact 24-hour time and answer in one short sentence.",
                    sourceName: "synthetic-selection.txt", sourceText: source,
                    sourceRevision: 1, placementRevision: 1, tone: "Direct", replyLength: cancel ? 0.5 : 0.2,
                    selection: selection)
                var result = "", updates = 0
                let sent = clock.now
                do {
                    try await client.reply(to: request) { event in
                        if case .text(let text) = event {
                            result = text; updates += 1
                            if updates == 1 { report["firstUpdateSeconds"] = .number(seconds(sent.duration(to: clock.now))) }
                            if cancel { client.disconnect() }
                        }
                    }
                    report["completed"] = .bool(true)
                } catch {
                    guard cancel, updates == 1, (error as? QwenFailure) == .stopped else { throw error }
                    report["interruptedBeforeCompletion"] = .bool(true)
                }
                report["replySeconds"] = .number(seconds(sent.duration(to: clock.now)))
                report["updates"] = .number(Double(updates))
                report["selection"] = selection.input
                if !cancel { report["reply"] = .string(result) }
                let correct = updates > 0 && ["Friday", "15:30", "Cedar"].allSatisfy(result.contains)
                    && !["Monday", "09:00", "Oak"].contains(where: result.contains)
                report["passed"] = .bool(cancel ? report["interruptedBeforeCompletion"]?.bool == true : correct)
            } else { report["passed"] = .bool(true) }
        } catch {
            report["error"] = .string((error as? LocalizedError)?.errorDescription ?? "Local Qwen check failed.")
        }
        await client.shutdown()
        report["localClientClosed"] = .bool(true)
        report["elapsedSeconds"] = .number(seconds(started.duration(to: clock.now)))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(JSONValue.object(report)) { print(String(decoding: data, as: UTF8.self)) }
        return report["passed"]?.bool == true
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
