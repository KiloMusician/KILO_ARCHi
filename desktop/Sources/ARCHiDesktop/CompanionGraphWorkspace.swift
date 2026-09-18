import SwiftUI

@MainActor
extension CompanionStore {
    /// A current projection of existing owners. Reading the graph never dispatches,
    /// saves, moves the companion or reconstructs withdrawn historical text.
    func companionGraphSnapshot(at now: Date = Date()) -> CompanionGraphSnapshot {
        CompanionGraph.build(
            receipts: compareResults.values.compactMap(\.receipt),
            lessons: keptLessons,
            source: sourceName.map { CompanionGraphSource(name: $0, text: sharedText, revision: sourceRevision) },
            now: now, records: hamptonSnapshot.records, turn: hamptonSnapshot.turn,
            arcRecords: arcCapabilities.records, arcError: arcCapabilities.lastError,
            accountingTasks: tokenSteward.tasks, accountingError: tokenSteward.loadError)
    }

    func openGraphTarget(_ target: CompanionGraphTarget) {
        switch target {
        case .assistant: open(.assistant)
        case .context: open(.context)
        case .memory: open(.memory)
        case .advanced: open(.advanced)
        case .capabilities: open(.capabilities)
        case .steward: open(.steward)
        case .stewardTask(let taskID): openARCUsage(taskID: taskID)
        case .arcEvidence(let proposalHash):
            arcCapabilities.selectRecord(id: proposalHash)
            open(.capabilities)
        }
    }
}

@MainActor
struct CompanionGraphWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(spacing: 0) {
            // Expiry gets a bounded refresh even when no other store event occurs.
            // This clock does not animate nodes or invoke any model.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                CompanionGraphView(snapshot: store.companionGraphSnapshot(at: context.date),
                    onOpen: store.openGraphTarget, initialSelectionID: store.selectedGraphNodeID)
                    .id(store.selectedGraphNodeID)
            }
            HStack(spacing: 10) {
                Label("Assistant: " + store.assistantActivity.title,
                    systemImage: "bubble.left.and.bubble.right")
                Spacer()
                if store.isWorking {
                    Button("Stop request", systemImage: "stop.fill") { store.cancelWork() }
                        .accessibilityIdentifier("node-lab.stop")
                }
                Button("Ask ARCHi") { store.open(.assistant) }
                    .accessibilityIdentifier("node-lab.ask")
            }
            .font(.system(size: 11))
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("node-lab.workspace")
    }
}
