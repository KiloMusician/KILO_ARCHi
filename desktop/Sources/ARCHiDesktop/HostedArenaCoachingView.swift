import SwiftUI

/// Nearby advice stays in the native presentation. Only the player's existing
/// Practice action can submit a move to the game.
@MainActor
struct HostedArenaCoachingControl: View {
    @ObservedObject var host: HostedPlayHost
    let selectedActionID: String
    var accept: (HostedArenaProjection.Action, String) -> Void

    private func presentation(_ id: UUID?) -> Binding<Bool> {
        Binding(get: { id != nil && host.coaching.session?.id == id && host.isVisible },
            set: { shown in if !shown, let id { host.dismissCoaching(sessionID: id) } })
    }

    var body: some View {
        if host.projection?.arena?.phase == .planning && !host.coachingChoices.isEmpty {
            let id = host.coaching.session?.id
            Button("Coach together", systemImage: "person.2") { host.beginCoaching() }
                .disabled(!host.canBeginCoaching && id == nil)
                .help("A person beside you can suggest a move. You decide whether to use it.")
                .accessibilityIdentifier("native-arena-coach-open")
                .popover(isPresented: presentation(id), arrowEdge: .bottom) {
                    if let session = host.coaching.session, session.id == id {
                        HostedArenaCoachingView(session: session, selectedActionID: selectedActionID,
                            offer: { action, reason in
                                host.offerCoaching(sessionID: session.id, actionID: action, reason: reason)
                            }, accept: {
                                let reason = session.offer?.reason ?? ""
                                if let action = host.acceptCoaching(sessionID: session.id) { accept(action, reason) }
                            }, dismiss: { host.dismissCoaching(sessionID: session.id) })
                    }
                }
                // An old native dismissal must not close a replacement offer.
                .id(id)
        }
    }
}

@MainActor
private struct HostedArenaCoachingView: View {
    let session: HostedArenaCoaching.Session
    let selectedActionID: String
    var offer: (String, String) -> Bool
    var accept: () -> Void
    var dismiss: () -> Void
    @State private var choiceID = ""
    @State private var reason = ""
    @State private var error = ""
    @FocusState private var reasonFocused: Bool

    private var selected: HostedArenaProjection.Action? {
        session.choices.first { $0.id == choiceID }
            ?? session.choices.first { $0.id == selectedActionID } ?? session.choices.first
    }
    private var canOffer: Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return selected != nil && !trimmed.isEmpty && reason.count <= 240
            && HostedArenaCoaching.normalizedReason(reason) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Nearby coach", systemImage: "person.2").font(.headline)
                Spacer()
                Button(session.offer == nil ? "Cancel" : "Dismiss", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("native-arena-coach-dismiss")
            }
            if let suggestion = session.offer {
                Text("Your coach suggests \(suggestion.action.label)").font(.title3.weight(.semibold))
                    .accessibilityIdentifier("native-arena-coach-suggestion")
                Text(suggestion.action.detail).font(.callout).foregroundStyle(.secondary)
                ScrollView {
                    Text(suggestion.reason).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("native-arena-coach-offered-reason")
                }.frame(maxHeight: 110)
                Text("Use this move to select it. You still decide when to play.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Use this move", action: accept)
                        .buttonStyle(.borderedProminent).tint(ArchiPalette.violet)
                        .accessibilityIdentifier("native-arena-coach-accept")
                }
            } else {
                Text("Pass the controls to someone beside you. They can offer one move and a short reason.")
                    .font(.callout).foregroundStyle(.secondary)
                if let selected {
                    Picker("Suggested move", selection: Binding(get: { selected.id }, set: { choiceID = $0 })) {
                        ForEach(session.choices) { Text($0.label).tag($0.id) }
                    }.accessibilityIdentifier("native-arena-coach-move")
                    Text(selected.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Why this move?", text: $reason)
                        .textFieldStyle(.roundedBorder).focused($reasonFocused)
                        .accessibilityIdentifier("native-arena-coach-reason")
                    Text("\(reason.count)/240 characters · advice for this round")
                        .font(.caption).foregroundStyle(reason.count > 240 ? .red : .secondary)
                }
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
                HStack {
                    Text("Offering advice does not play a move.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Offer suggestion") {
                        guard let selected else { return }
                        if !offer(selected.id, reason) { error = "This offer is no longer available. Close it and try again." }
                    }
                    .buttonStyle(.borderedProminent).tint(ArchiPalette.violet)
                    .disabled(!canOffer)
                    .accessibilityIdentifier("native-arena-coach-offer")
                }
            }
        }
        .padding(18).frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native-arena-coach-popover")
        .onAppear { if session.offer == nil { reasonFocused = true } }
    }
}
