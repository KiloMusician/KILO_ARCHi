import Foundation

enum AssistantRoute: String, CaseIterable, Identifiable, Sendable {
    case local, codex, compare
    var id: String { rawValue }
    var title: String {
        switch self { case .local: "Local answer"; case .codex: "Codex answer"; case .compare: "Compare both" }
    }
    var disclosure: String {
        switch self {
        case .local: "Your message and shared copy go only to Qwen on this Mac."
        case .codex: "Your message and shared copy go to Codex through ChatGPT."
        case .compare: "Your message and shared copy go to both assistants. Local session excerpts stay with Qwen."
        }
    }
    var providers: [AssistantProvider] {
        switch self { case .local: [.qwen]; case .codex: [.codex]; case .compare: [.qwen, .codex] }
    }
    var primaryProvider: AssistantProvider { self == .codex ? .codex : .qwen }
}

enum AssistantLaneState: String, Equatable, Sendable { case pending, complete, failed, cancelled }

/// A receipt identifies the dispatched current input and its outcome, not the
/// semantic truth of either answer. Local role inputs have separate receipts.
struct AssistantLaneReceipt: Equatable, Sendable {
    let requestID: String
    let route: AssistantRoute
    let provider: AssistantProvider
    let context: ContextTicket
    let inputDigest: String
    var sourceDigest: String? = nil
    let inputContract: String
    let deadline: Date
    var modelIdentity: String?
    var state: AssistantLaneState
    var settings: AssistantSettingsSnapshot? = nil
    var requestStarted = false
    var localInvocations: [LocalModelRole]? = nil
    var elapsedMilliseconds: Int? = nil
    var localLessons: [LessonSnapshot] = []
    var localLessonDigest: String? = nil
    var usedLessonIDs: [String] = []
}

struct AssistantLaneResult: Equatable, Sendable {
    var text: String
    var status: String
    var state: AssistantLaneState
    var receipt: AssistantLaneReceipt?
    var revision: PassageRevisionProposal? = nil
}
