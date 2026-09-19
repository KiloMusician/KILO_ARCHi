import SwiftUI

/// The same task service is available from every assistant surface.
@MainActor
struct ARCActiveAssistantActions: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        Menu {
            Button("Solve shared or loaded task") { store.runARC(.solve) }
                .disabled(store.isWorking || store.voiceInput.isActive || store.isShuttingDown)
            Button("Propose a rule with local Qwen") { store.runARC(.propose) }
                .disabled(store.isWorking || store.voiceInput.isActive || store.isShuttingDown)
            Divider()
            Button("Manage ARC tasks and results") { store.open(.capabilities) }
        } label: {
            Label("ARC task", systemImage: "square.grid.3x3")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityIdentifier("assistant.arc-actions")
        .help("Run ARCHi’s local ARC capability on shared ARC JSON or the loaded task. Your message draft is preserved.")
    }
}

@MainActor
struct ARCActiveAssistantReply: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        if let answer = store.activeARCAnswer {
            VStack(alignment: .leading, spacing: 10) {
                Label("ARCHi · ARC", systemImage: "square.grid.3x3")
                    .font(.headline).foregroundStyle(WorkspaceTheme.accent)
                if let name = answer.inputName {
                    Text(name).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if answer.isWorking { ProgressView().controlSize(.small) }
                Text(answer.status).font(.callout).textSelection(.enabled)
                    .accessibilityIdentifier("assistant.arc-status")
                if let error = answer.error {
                    Text(error).foregroundStyle(.orange).font(.callout).textSelection(.enabled)
                }
                if let predictions = answer.predictions {
                    ForEach(predictions.indices, id: \.self) { index in
                        ARCNativeGrid(grid: predictions[index], title: "Prediction \(index + 1)",
                            identifier: "assistant.arc.prediction.\(index)")
                    }
                }
                if let summary = answer.summary {
                    Text("Checked result: \(summary.counts.exact) exact · \(summary.counts.incorrect) incorrect · \(summary.counts.missing) missing · \(summary.counts.unscored) unscored")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("assistant.arc-checker")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { links(answer) }
                    VStack(alignment: .leading, spacing: 8) { links(answer) }
                }
                Text("Predictions are checked when expected answers are available. Otherwise they are marked unscored.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).modifier(WorkspaceSurface())
            .accessibilityIdentifier("assistant.arc-result")
        }
    }

    @ViewBuilder private func links(_ answer: ARCActiveAssistantAnswer) -> some View {
        if let taskID = answer.taskID, !answer.isWorking {
            Button("Usage") { _ = store.openARCUsage(taskID: taskID) }
                .accessibilityIdentifier("assistant.arc-usage")
        }
        if let evidenceID = answer.evidenceID {
            Button("Activity map") { _ = store.openARCGraph(evidenceID: evidenceID) }
                .accessibilityIdentifier("assistant.arc-graph")
            Button("Review reasoning") {
                if store.arcCapabilities.selectRecord(id: evidenceID) { store.open(.capabilities) }
            }.accessibilityIdentifier("assistant.arc-evidence")
        }
    }
}
