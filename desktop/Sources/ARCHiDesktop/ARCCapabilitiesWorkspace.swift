import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct ARCCapabilitiesWorkspace: View {
    @ObservedObject var store: ARCCapabilitiesStore
    var onEvaluation: (ARCCapabilitiesEvent) -> Void = { _ in }
    @State private var importError: String?

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ARC capabilities").font(.system(size: 28, weight: .light))
                    Text("Check reasoning evidence against frozen grid tasks, here on your Mac.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Label("Evidence review", systemImage: "square.grid.3x3")
                        .font(.headline)
                    Text("Import a task bundle with raw predictions. ARCHi checks the full manifest again, including missing and invalid answers. Results stay proposed and do not change your companion’s growth.")
                    HStack {
                        Button("Import evaluation…", systemImage: "square.and.arrow.down", action: importBundle)
                            .accessibilityIdentifier("capabilities.import")
                        Button("Run synthetic demonstration") {
                            importError = nil
                            onEvaluation(store.runSyntheticDemonstration())
                        }.accessibilityIdentifier("capabilities.synthetic-demo")
                    }
                    Text("The demonstration uses fixed sample predictions: one correct, one incorrect. It makes no model calls and is not a benchmark score.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16).modifier(WorkspaceSurface())
                if let error = importError ?? store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).textSelection(.enabled)
                        .accessibilityIdentifier("capabilities.error")
                }
                if let notice = store.selectionNotice {
                    Label(notice, systemImage: "link.badge.plus")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("capabilities.selection-notice")
                }
                if store.records.isEmpty {
                    ContentUnavailableView("No evaluated evidence yet", systemImage: "square.grid.3x3",
                        description: Text("Import a portable ARC evaluation or run the offline demonstration."))
                }
                ForEach(store.records) { record in recordCard(record).id(record.id) }
            }.padding(28).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("capabilities.workspace")
            .onAppear { if let id = store.selectedRecordID { reader.scrollTo(id, anchor: .top) } }
            .onChange(of: store.selectedRecordID) { _, id in
                if let id { reader.scrollTo(id, anchor: .top) }
            }
        }
    }

    private func recordCard(_ record: ARCCapabilitiesRecord) -> some View {
        let summary = record.summary
        let counts = summary.counts
        return VStack(alignment: .leading, spacing: 12) {
            if store.selectedRecordID == record.id {
                Label("Selected from Node Lab", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption).foregroundStyle(WorkspaceTheme.accent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Selected ARC receipt from Node Lab")
                    .accessibilityIdentifier("capabilities.selected-record")
            }
            HStack {
                Text(summary.sourceLabel).font(.headline)
                Spacer()
                Text("Proposed · Not certified").font(.caption).foregroundStyle(.secondary)
            }
            Text(summary.sourceStatus == "synthetic-fixture" ? "Synthetic fixture · Rescored locally" : "Unverified offline snapshot · Solver provenance unattested")
                .font(.caption).foregroundStyle(.secondary)
            Text("\(counts.exact) of \(counts.totalExamples) examples exact · \(counts.exactTasks) of \(counts.totalTasks) tasks exact")
                .font(.title3).accessibilityIdentifier("capabilities.result")
            Text("Incorrect \(counts.incorrect) · Missing \(counts.missing) · Invalid \(counts.invalid) · Unscored \(counts.unscored)")
                .font(.callout)
            Text("Solver: \(summary.solverID) · \(record.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Evidence details") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Manifest: \(summary.manifestID)")
                    Text("Manifest hash: \(summary.manifestHash)")
                    Text("Bundle hash: \(record.bundleHash)")
                    Text("Application task: \(record.taskID)")
                    Text("Proposal: \(summary.proposalHash)")
                    Text("Receipt coverage: \(summary.receiptCoverageComplete ? "complete" : "incomplete") · Scored coverage: \(summary.scoredCoverageComplete ? "complete" : "incomplete")")
                    ForEach(summary.receiptHashes, id: \.self) { hash in Text("Checker receipt: \(hash)") }
                    Text("Hashes check content integrity. They do not authenticate the source or certify capability. No Journey, memory, permission, action or XP changes are granted.")
                }.font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(16).modifier(WorkspaceSurface())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capabilities.record.\(record.id)")
    }

    private func importBundle() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an archi-arc-evaluation-bundle/v1 JSON file (up to 2 MiB)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        do {
            importError = nil
            onEvaluation(try store.evaluate(fileURL: url))
        } catch { importError = error.localizedDescription }
    }
}
