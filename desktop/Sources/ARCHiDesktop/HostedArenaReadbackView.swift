import SwiftUI

/// Native presentation of the existing game's public state. Reading a round
/// has no command, save, or character-growth side effect.
@MainActor
struct HostedArenaScoreboard: View {
    let readback: HostedArenaReadback

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(readback.teams) { team in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(team.label).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("Spark \(team.spark)/3").font(.system(size: 11)).monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        ProgressView(value: Double(team.integrity), total: Double(team.maximumIntegrity))
                            .tint(ArchiPalette.violet).accessibilityHidden(true)
                            // Initialize at the current value after each round;
                            // do not interpolate an old fill beside new numbers.
                            .id(team.integrity)
                        Text("\(team.integrity)/\(team.maximumIntegrity) Integrity")
                            .font(.system(size: 10)).monospacedDigit()
                    }
                    Text(memberSummary(team)).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).help(memberSummary(team))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(team.label). Integrity \(team.integrity) of \(team.maximumIntegrity). Spark \(team.spark) of 3. \(memberSummary(team))")
                .accessibilityIdentifier("native-arena-team-\(team.id.rawValue)")
            }
        }
    }

    private func memberSummary(_ team: HostedArenaReadback.Team) -> String {
        let active = team.roster.first { $0.active }.map { "Active: \($0.name)\($0.exposed ? ", exposed" : "")" } ?? "No active member"
        let ready = team.roster.filter { !$0.active && $0.integrity > 0 }.count
        let settled = team.roster.filter { $0.integrity == 0 }.count
        return "\(active) · \(ready) reserve\(ready == 1 ? "" : "s") ready" + (settled > 0 ? " · \(settled) settled" : "")
    }
}

@MainActor
struct HostedArenaReadbackView: View {
    let readback: HostedArenaReadback
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(readback.result == nil ? "Match details" : readback.resultTitle).font(.headline)
                Spacer()
                Button("Done", action: close).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("native-arena-details-done")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let result = readback.result {
                        Text(readback.resultExplanation).font(.callout)
                        Label(result.retentionTitle, systemImage: result.retention == .saved ? "checkmark.circle" : "tray")
                            .font(.subheadline.weight(.medium))
                        Text(result.message).font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(readback.teams) { team in
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(team.label) · \(team.integrity)/\(team.maximumIntegrity) Integrity · \(team.spark)/3 Spark")
                                .font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                            ForEach(team.roster) { member in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.name).font(.callout.weight(.medium))
                                        Text("\(member.role.rawValue.capitalized) · \(member.active ? "Active" : member.integrity == 0 ? "Settled" : "Reserve")\(member.exposed ? " · Exposed: +3 next damaging impact" : "")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(member.integrity)/\(member.maximumIntegrity) Integrity").font(.callout).monospacedDigit()
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("native-arena-member-\(member.id)")
                            }
                        }
                        Divider()
                    }
                    Text("Resolved rounds").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    if readback.rounds.isEmpty {
                        Text("Choose and play a move to resolve the first round.").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(readback.rounds.reversed()) { round in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Round \(round.round)").font(.callout.weight(.semibold))
                            Text(round.summary).font(.callout).textSelection(.enabled)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("native-arena-round-\(round.round)")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Integrity is the whole team’s remaining strength. Spark is shared by the team.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(width: 540, height: 470)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native-arena-details")
    }
}

extension HostedArenaReadback {
    var resultTitle: String {
        guard let result else { return "Practice in progress" }
        if result.winner == .draw { return "Practice complete · Draw" }
        let label = teams.first { $0.id.rawValue == result.winner.rawValue }?.label ?? "Winning side"
        return "\(label) wins"
    }
    var resultExplanation: String {
        guard let result else { return "" }
        switch result.reason {
        case .surrender: return "The practice ended when a player chose to leave early."
        case .eliminated: return "The practice ended when a team had no Integrity remaining."
        case .roundLimit: return "The 20-round limit was reached. Remaining team Integrity decides the result, then Spark breaks a tie. Equal Integrity and Spark means a draw."
        }
    }
}

extension HostedArenaReadback.Result {
    var retentionTitle: String {
        switch retention {
        case .unsaved: return "Not kept yet"
        case .saving: return "Keeping practice…"
        case .saved: return "Kept in Journey"
        case .sessionOnly: return "Kept for this test session"
        case .unavailable: return "Temporary result"
        }
    }
}
