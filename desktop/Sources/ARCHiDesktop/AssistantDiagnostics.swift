import Foundation

@MainActor
enum AssistantDiagnostics {
    static func run(live: Bool, cancel: Bool = false, selection: Bool = false) async -> Bool {
        let client = CodexAssistant()
        var report: [String: JSONValue] = ["schema": .string("archi-assistant-check/v1"),
            "mode": .string(selection ? "live-synthetic-selection" : cancel ? "live-cancel-on-first-update" : live ? "live-synthetic-document" : "connection-only"),
            "startedAt": .string(ISO8601DateFormatter().string(from: Date())), "passed": .bool(false)]
        do {
            try await client.connect()
            report["connected"] = .bool(true)
            if live {
                var request = AssistantRequest(prompt: "What are the meeting day, time and room? Answer in one short sentence.",
                    sourceName: "synthetic-meeting.txt", sourceText: "The planning meeting is Tuesday at 10:30 AM in Cedar.",
                    sourceRevision: 1, placementRevision: 1, tone: "Direct", replyLength: 0.2)
                if selection {
                    let source = "Option A: Rehearsal is Monday at 09:00 in Oak.\nOption B: Rehearsal is Friday at 15:30 in Cedar."
                    let quote = "Option B: Rehearsal is Friday at 15:30 in Cedar."
                    guard let passage = DocumentSelection(range: (source as NSString).range(of: quote), text: source, sourceRevision: 1) else {
                        throw AssistantFailure.protocolError
                    }
                    request = AssistantRequest(prompt: "What are the rehearsal day, time, and room in the selected passage? Answer in one short sentence.",
                        sourceName: "synthetic-selection.txt", sourceText: source,
                        sourceRevision: 1, placementRevision: 1, tone: "Direct", replyLength: 0.2, selection: passage)
                    report["selection"] = passage.input
                }
                var result = "", updates = 0
                do {
                    try await client.reply(to: request) { event in
                        if case .text(let text) = event {
                            result = text; updates += 1
                            if cancel { client.disconnect() }
                        }
                    }
                } catch {
                    guard cancel, updates > 0, let failure = error as? AssistantFailure,
                          failure == .stopped else { throw error }
                    report["interruptedBeforeCompletion"] = .bool(true)
                }
                if !cancel { report["reply"] = .string(result) }
                report["updates"] = .number(Double(updates))
                let expected = selection ? ["Friday", "15:30", "Cedar"] : ["Tuesday", "10:30", "Cedar"]
                let correct = updates > 0 && expected.allSatisfy(result.contains)
                    && (!selection || !["Monday", "09:00", "Oak"].contains(where: result.contains))
                report["passed"] = .bool(cancel ? report["interruptedBeforeCompletion"]?.bool == true : correct)
            } else { report["passed"] = .bool(true) }
        } catch {
            report["error"] = .string((error as? AssistantFailure)?.localizedDescription ?? "Connection check failed.")
        }
        await client.shutdown()
        report["configurationChecks"] = .object(client.configurationChecks.mapValues { .bool($0) })
        report["stage"] = .string(client.diagnosticStage)
        report["ownedProcessStopped"] = .bool(true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(JSONValue.object(report)) { print(String(decoding: data, as: UTF8.self)) }
        return report["passed"]?.bool == true
    }
}
