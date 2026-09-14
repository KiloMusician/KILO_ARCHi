import SwiftUI

/// A view of the existing request owner's temporary conversation, never a
/// second chat store or a route that forwards local history to an external model.
@MainActor
struct AssistantConversationControls: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if store.route == .codex {
                Text("Codex starts a fresh question. Recent Qwen exchanges stay on this Mac.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            DisclosureGroup(summary) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use recent Qwen conversation", isOn: Binding(
                        get: { store.localConversationEnabled },
                        set: { store.setLocalConversationEnabled($0) }))
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("assistant-conversation.enabled")
                    Text("Up to 3 recent exchanges, on this Mac for this visit. Older exchanges may be omitted to fit the next reply. Only local Qwen receives them; they are not saved lessons or verified facts. This is the current window, which can differ from an earlier reply’s captured context.")
                    Text(store.localConversationNotice)
                        .accessibilityIdentifier("assistant-conversation.notice")
                    if !store.localConversation.exchanges.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(store.localConversation.exchanges.enumerated()), id: \.offset) { index, exchange in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Exchange \(index + 1)").fontWeight(.medium)
                                        Text("You: " + exchange.question)
                                        Text("Qwen · generated answer: " + exchange.answer)
                                    }.textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 150)
                        Button("New local conversation", systemImage: "plus.bubble") {
                            store.startNewLocalConversation()
                        }.buttonStyle(.borderless)
                            .accessibilityIdentifier("assistant-conversation.new")
                    }
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 5)
            }.font(.system(size: 10))
                .accessibilityIdentifier("assistant-conversation.inspect")
        }.fixedSize(horizontal: false, vertical: true)
            .disabled(store.isShuttingDown)
    }

    private var summary: String {
        if !store.localConversationEnabled { return "Recent Qwen conversation · off" }
        return "Recent Qwen conversation · \(store.localConversation.exchanges.count) exchange(s) this visit"
    }
}
