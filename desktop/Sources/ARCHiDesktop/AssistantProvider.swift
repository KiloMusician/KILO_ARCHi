import Foundation

enum AssistantProvider: String, CaseIterable, Identifiable, Hashable, Sendable {
    case qwen = "Qwen · on this Mac"
    case codex = "Codex · ChatGPT"
    var id: String { rawValue }
    var name: String { self == .qwen ? "Qwen" : "Codex" }
    var detail: String {
        self == .qwen
            ? "Use an installed Qwen model through Ollama on this Mac."
            : "Optional external reference or alternative through your existing Codex account. Sending shares the current request with the provider."
    }
    var destination: String { self == .qwen ? "Qwen on this Mac" : "Codex through ChatGPT" }
}
