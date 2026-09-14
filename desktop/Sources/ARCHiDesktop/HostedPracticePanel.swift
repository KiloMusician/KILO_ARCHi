import SwiftUI

/// Keyboard and VoiceOver controls for the same Arena shown below. The game
/// supplies every available intent and its explanation.
@MainActor
struct HostedPracticePanel: View {
    @ObservedObject var host: HostedPlayHost
    @ObservedObject var evolution: EvolutionStore
    var openEvolution: () -> Void
    @State private var selectedActionID = ""
    @State private var reviewExpanded = false
    @State private var matchDetailsID: UUID?
    @State private var coachingSelection: (id: String, reason: String)?

    private var arena: HostedArenaProjection? { host.projection?.arena }
    private var actions: [HostedArenaProjection.Action] {
        arena?.actions.filter { $0.id != "leave" && !$0.id.hasPrefix("what-if:") } ?? []
    }
    private var selected: HostedArenaProjection.Action? { actions.first { $0.id == selectedActionID } ?? actions.first }

    private func matchDetailsPresentation(_ id: UUID?) -> Binding<Bool> {
        Binding(get: { id != nil && matchDetailsID == id }, set: { showing in
            if !showing { closeMatchDetails(id) }
        })
    }
    private func closeMatchDetails(_ id: UUID?) {
        guard let id, matchDetailsID == id else { return }
        matchDetailsID = nil
    }

    var body: some View {
        if host.state == .ready, let projection = host.projection, [2, 3, 4].contains(projection.version),
           projection.originDigest != nil || arena != nil || !(projection.practices ?? []).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let origin = projection.originDigest {
                    HStack(spacing: 12) {
                        Label("Your Journey", systemImage: "person.crop.circle")
                            .font(.system(size: 12, weight: .medium))
                        Text(evolution.practiceJourneyOriginDigest == origin ? "Personal history connected" : "Its individual details are already present.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if evolution.practiceJourneyOriginDigest != origin {
                            Button(evolution.practiceJourneyOriginDigest == nil ? "Connect personal history" : "Use this Journey history") {
                                guard host.isVisible, host.projection?.originDigest == origin else { return }
                                evolution.observeJourneyOrigin(origin)
                                evolution.bindPracticeJourney(origin)
                            }
                            .help("Link reviewed experiences to this Journey. Its natural appearance needs no setup; your saved Journey is unchanged.")
                            .accessibilityIdentifier("native-practice-bind")
                        } else {
                            Button("Evolution", action: openEvolution)
                                .accessibilityIdentifier("native-journey-evolution")
                        }
                    }
                }
                if let arena {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: arena.phase == .finished ? "flag.checkered" : "sparkles.rectangle.stack")
                            .foregroundStyle(ArchiPalette.violet).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(arena.readback?.result != nil ? arena.readback!.resultTitle : arena.phase == .entry ? "Practice together" : "QiMon practice · Round \(arena.round)")
                                .font(.system(size: 12, weight: .semibold))
                            Text(arena.readback?.result.map { "\($0.retentionTitle). \($0.message)" } ?? arena.readback?.latestRound.map { "Round \($0.round): \($0.summary)" } ?? arena.summary)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("native-practice-summary")
                        }
                        Spacer(minLength: 0)
                    }
                    if let readback = arena.readback {
                        HostedArenaScoreboard(readback: readback)
                    }
                    HStack(spacing: 12) {
                        if let readback = arena.readback {
                            let presentationID = matchDetailsID
                            Button(readback.result == nil ? "Match details" : "Result & rounds", systemImage: "list.bullet.rectangle") {
                                matchDetailsID = UUID()
                            }
                            .accessibilityIdentifier("native-arena-details-open")
                            .popover(isPresented: matchDetailsPresentation(presentationID), arrowEdge: .bottom) {
                                HostedArenaReadbackView(readback: readback) { closeMatchDetails(presentationID) }
                            }
                            .id(presentationID)
                        }
                        HostedArenaWhatIfControl(host: host)
                            .disabled(host.coaching.session != nil)
                        HostedArenaCoachingControl(host: host, selectedActionID: selected?.id ?? "") { action, reason in
                            selectedActionID = action.id
                            coachingSelection = (action.id, reason)
                        }
                        Spacer(minLength: 0)
                        if let leave = arena.actions.first(where: { $0.id == "leave" }) {
                            Button(leave.label) { host.performArenaAction(leave, revision: arena.revision) }
                                .help(leave.detail).accessibilityIdentifier("native-practice-leave")
                        }
                    }
                    if let selected {
                        HStack(spacing: 10) {
                            if actions.count > 1 {
                                Picker("Practice action", selection: Binding(get: { selected.id }, set: {
                                    selectedActionID = $0; coachingSelection = nil
                                })) {
                                    ForEach(actions) { Text($0.label).tag($0.id) }
                                }.labelsHidden().frame(maxWidth: 240)
                                    .accessibilityIdentifier("native-practice-action")
                                    .disabled(host.coaching.session != nil)
                            }
                            Text(selected.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                            Button(selected.id.hasPrefix("one:") || selected.id.hasPrefix("two:") ? "Play \(selected.label)" : selected.label) {
                                host.performArenaAction(selected, revision: arena.revision)
                            }
                                .buttonStyle(.borderedProminent).tint(ArchiPalette.violet)
                                .keyboardShortcut(.return, modifiers: .command)
                                .help("Perform the selected practice action · Command-Return")
                                .accessibilityIdentifier("native-practice-perform")
                                .disabled(host.coaching.session != nil || matchDetailsID != nil)
                        }
                    }
                    if let coachingSelection, coachingSelection.id == selected?.id {
                        Text("Coach’s move selected. Press Play when you’re ready.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .help(coachingSelection.reason)
                            .accessibilityLabel("Coach’s move selected, not played. \(coachingSelection.reason)")
                            .accessibilityIdentifier("native-arena-coach-selected")
                    }
                }
                if !host.arenaStatus.isEmpty {
                    Text(host.arenaStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("native-practice-command-status")
                }
                if let origin = projection.originDigest, let practice = projection.practices?.first {
                    DisclosureGroup("Saved practice · shared history", isExpanded: $reviewExpanded) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(practice.rounds) rounds · \(practice.outcome.rawValue.capitalized)")
                                    .font(.system(size: 12, weight: .medium))
                                Text("An experience together. Reviewing it does not unlock a body or measure growth.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if evolution.practiceJourneyOriginDigest != origin {
                                Text("Connect personal history above to review its practice.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            } else {
                                let reviewed = evolution.reviewedPractices.contains { $0.id == practice.id }
                                Button(reviewed ? "Added to shared history" : "Keep in shared history") {
                                    guard host.isVisible, host.projection?.originDigest == origin,
                                          host.projection?.practices?.contains(practice) == true else { return }
                                    evolution.reviewPractice(practice, currentOriginDigest: origin)
                                }.disabled(reviewed).accessibilityIdentifier("native-practice-useful")
                                if reviewed {
                                    Button("Your companion", action: openEvolution)
                                        .accessibilityIdentifier("native-practice-open-evolution")
                                }
                            }
                        }.padding(.top, 7)
                    }.font(.system(size: 11)).accessibilityIdentifier("native-practice-review")
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(ArchiPalette.violet.opacity(0.055))
            .disabled(host.arenaCommandPending || !projection.visible)
            .onChange(of: arena?.revision) { _, _ in
                matchDetailsID = nil
                coachingSelection = nil
                if !actions.contains(where: { $0.id == selectedActionID }) { selectedActionID = "" }
            }
            .onDisappear { coachingSelection = nil }
            .onChange(of: host.sessionID) { _, _ in matchDetailsID = nil }
            .onChange(of: projection.visible) { _, visible in if !visible { matchDetailsID = nil } }
            .onDisappear { matchDetailsID = nil }
        }
    }
}
