import SwiftUI

/// Presentation for a disposable comparison supplied by the existing battle
/// engine. Native controls only choose projected intents; they never seal moves.
@MainActor
struct HostedArenaWhatIfControl: View {
    @ObservedObject var host: HostedPlayHost
    @State private var dismissedComparison: DismissedComparison?

    private struct DismissedComparison {
        let presentationID: UUID
        var attemptedRevision: String?
    }

    private var arena: HostedArenaProjection? { host.projection?.arena }
    private var isAvailable: Bool {
        host.state == .ready && host.isVisible && host.projection?.visible == true
    }
    private var openAction: HostedArenaProjection.Action? {
        arena?.actions.first { $0.id == "what-if:open" }
    }
    private func presentation(for presentationID: UUID?) -> Binding<Bool> {
        Binding(get: {
            isAvailable && arena?.whatIf != nil && presentationID != nil
                && host.whatIfPresentationID == presentationID
                && dismissedComparison?.presentationID != presentationID
        }, set: { presented in
            if !presented { dismissComparison(presentationID: presentationID) }
        })
    }

    var body: some View {
        if openAction != nil || arena?.whatIf != nil {
            let presentationID = host.whatIfPresentationID
            Button("What if?", systemImage: "arrow.triangle.branch") {
                guard isAvailable, !host.arenaCommandPending,
                      host.whatIfPresentationID == presentationID, let arena else { return }
                dismissedComparison = nil
                if let openAction { host.performArenaAction(openAction, revision: arena.revision) }
            }
            .help("Compare two possible moves before choosing and sealing your actual move.")
            .accessibilityLabel("What if? Compare first player's moves")
            .accessibilityIdentifier("native-arena-what-if-open")
            .disabled(!isAvailable || host.arenaCommandPending)
            .popover(isPresented: presentation(for: presentationID), arrowEdge: .bottom) {
                if let presentationID, host.whatIfPresentationID == presentationID,
                   let arena, let report = arena.whatIf {
                    HostedArenaWhatIfView(report: report, pending: host.arenaCommandPending,
                        actionIDs: Set(arena.actions.map(\.id)),
                        select: { performSelection($0, presentationID: presentationID) },
                        close: { dismissComparison(presentationID: presentationID) })
                }
            }
            // A native popover can finish dismissing after another report opens.
            // Keep both its view identity and callbacks bound to the retired one.
            .id(presentationID)
            .onChange(of: host.whatIfPresentationID) { _, currentID in
                if dismissedComparison?.presentationID != currentID { dismissedComparison = nil }
            }
            .onChange(of: host.arenaCommandPending) { _, pending in
                if !pending { closeDismissedComparisonIfPossible() }
            }
        }
    }

    private func performSelection(_ actionID: String, presentationID: UUID) {
        guard isAvailable, !host.arenaCommandPending, host.whatIfPresentationID == presentationID, let arena,
              arena.whatIf != nil, let action = arena.actions.first(where: { $0.id == actionID }) else { return }
        host.performArenaAction(action, revision: arena.revision)
    }

    private func dismissComparison(presentationID: UUID?) {
        guard let presentationID, host.whatIfPresentationID == presentationID, arena?.whatIf != nil else { return }
        if dismissedComparison?.presentationID != presentationID {
            dismissedComparison = DismissedComparison(presentationID: presentationID)
        }
        closeDismissedComparisonIfPossible()
    }

    /// A picker can still be awaiting its acknowledgement when the user presses
    /// Escape. Retire that same report after the command finishes. A failed close
    /// is not retried forever against an unchanged revision.
    private func closeDismissedComparisonIfPossible() {
        guard isAvailable, !host.arenaCommandPending, let arena, arena.whatIf != nil,
              var dismissed = dismissedComparison, dismissed.presentationID == host.whatIfPresentationID,
              dismissed.attemptedRevision != arena.revision,
              let action = arena.actions.first(where: { $0.id == "what-if:close" }) else { return }
        dismissed.attemptedRevision = arena.revision
        dismissedComparison = dismissed
        host.performArenaAction(action, revision: arena.revision)
    }
}

@MainActor
private struct HostedArenaWhatIfView: View {
    let report: HostedArenaProjection.WhatIf
    let pending: Bool
    let actionIDs: Set<String>
    let select: (String) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What if?").font(.headline)
                Spacer()
                Button("Done", action: close)
                    .accessibilityIdentifier("native-arena-what-if-done")
            }
            Text("Compare the first player’s moves. These are possible outcomes, not predictions. Your actual move stays unchanged.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("native-arena-what-if-explanation")
            HStack(alignment: .top, spacing: 16) {
                movePicker("First move", lane: "first", selectedID: report.firstId)
                movePicker("Compare with", lane: "second", selectedID: report.secondId)
            }
            .disabled(pending)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(report.cases, id: \.opponentId) { branch in
                        VStack(alignment: .leading, spacing: 7) {
                            Text("If they \(branch.opponentLabel)").font(.system(size: 12, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                            HStack(alignment: .top, spacing: 16) {
                                outcome(branch.first, moveID: report.firstId)
                                outcome(branch.second, moveID: report.secondId)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("native-arena-what-if-case-\(branch.opponentId)")
                        Divider()
                    }
                }
            }
            .accessibilityIdentifier("native-arena-what-if-outcomes")
            Text(pending ? "Updating the comparison…" : "Close this comparison to choose and seal your move in Practice.")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("native-arena-what-if-status")
        }
        .padding(18)
        .frame(width: 570, height: 490)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native-arena-what-if-popover")
    }

    private func movePicker(_ title: String, lane: String, selectedID: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Picker(title, selection: Binding(get: { selectedID }, set: { choice in
                select("what-if:\(lane):\(choice)")
            })) {
                ForEach(report.choices.filter { $0.id == selectedID || actionIDs.contains("what-if:\(lane):\($0.id)") }) { choice in
                    Text(choice.label).tag(choice.id)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("native-arena-what-if-\(lane)")
            if let choice = report.choices.first(where: { $0.id == selectedID }) {
                Text(choice.detail).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .help(choice.detail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func outcome(_ summary: String, moveID: String) -> some View {
        Text(summary).font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(report.choices.first(where: { $0.id == moveID })?.label ?? "Move"): \(summary)")
    }
}
