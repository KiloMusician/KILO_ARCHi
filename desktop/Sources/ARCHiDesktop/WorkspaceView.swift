import SwiftUI

@MainActor
struct WorkspaceView: View {
    @ObservedObject var store: CompanionStore
    let playHost: HostedPlayHost
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 205, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                workspaceHeader
                Divider().opacity(0.6)
                if store.section == .context {
                    WorkTogetherWorkspace(store: store)
                } else if store.section == .play {
                    PlayWorkspace(store: store, host: playHost)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            sectionHeading
                            sectionContent
                        }
                        .frame(maxWidth: 980, alignment: .leading)
                        .padding(32)
                        .frame(maxWidth: .infinity)
                    }
                }
                Divider().opacity(0.5)
                statusBar
            }
            .background {
                LinearGradient(colors: [ArchiPalette.lilac.opacity(colorScheme == .dark ? 0.05 : 0.15), ArchiPalette.peach.opacity(0.045), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(ArchiPalette.violet)
        .preferredColorScheme(.light)
        .frame(minWidth: 880, minHeight: 640)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                CompanionArt(form: .companion, size: 36, reduceMotion: true)
                Text("ARCHi").font(.system(size: 24, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 24)

            List(selection: $store.section) {
                Section("YOUR WORKSPACE") {
                    ForEach([WorkspaceSection.context, .assistant, .play]) { section in sidebarRow(section) }
                }
                Section("MAKE IT YOURS") {
                    ForEach([WorkspaceSection.appearance, .evolution, .rhythm, .memory]) { section in sidebarRow(section) }
                }
                Section("PREFERENCES") {
                    ForEach([WorkspaceSection.connections, .accessibility, .advanced]) { section in sidebarRow(section) }
                }
            }
            .listStyle(.sidebar)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 9) {
                Label("On your desktop", systemImage: "desktopcomputer")
                    .font(.system(size: 12, weight: .medium))
                Text("A little presence.\nRoom for everything else.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }.padding(22)
        }
    }

    private func sidebarRow(_ section: WorkspaceSection) -> some View {
        Label(section.rawValue, systemImage: section.icon)
            .font(.system(size: 13))
            .padding(.vertical, 5)
            .tag(section)
    }

    private var workspaceHeader: some View {
        HStack {
            Label("Your personal workspace", systemImage: "sparkle")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            Button {
                store.isVisible ? store.hideCompanion() : store.showCompanion()
            } label: {
                Label(store.isVisible ? "Hide companion" : "Show companion", systemImage: store.isVisible ? "eye.slash" : "eye")
            }.buttonStyle(.borderless)
            Button("Return to desktop", systemImage: "arrow.up.right") {
                let workspace = NSApplication.shared.keyWindow
                playHost.setVisible(false)
                store.invalidateTextSelection(reason: "Workspace hidden; passage reference cleared.")
                store.showCompanion()
                workspace?.orderOut(nil)
            }.buttonStyle(.bordered)
        }
        .padding(.horizontal, 28).padding(.vertical, 15)
    }

    private var sectionHeading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(store.section.eyebrow.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(ArchiPalette.violet)
            Text(store.section.heading)
                .font(.system(size: 30, weight: .medium, design: .rounded))
            Text(store.section.subtitle)
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch store.section {
        case .assistant: AssistantWorkspace(store: store)
        case .play: EmptyView() // Hosted separately so the game owns its scrolling and focus.
        case .appearance: AppearanceWorkspace(store: store)
        case .evolution: EvolutionWorkspace(store: store, evolution: store.evolution)
        case .rhythm: RhythmWorkspace(store: store)
        case .memory: MemoryWorkspace(store: store)
        case .context: EmptyView() // The workbench owns its full-height document and review columns.
        case .connections: ConnectionsWorkspace(store: store)
        case .accessibility: AccessibilityWorkspace(store: store)
        case .advanced: AdvancedWorkspace(store: store)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 7) {
            Circle().fill(ArchiPalette.violet.opacity(0.65)).frame(width: 5, height: 5)
            Text(store.status).lineLimit(1)
            Spacer()
            Text("DESKTOP PREVIEW").font(.system(size: 9, weight: .medium)).tracking(1.2)
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 28).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct AssistantWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 4) {
                    CompanionPresenceArt(form: store.preferences.form, family: store.evolution.activeFamily, size: 96, reduceMotion: store.preferences.reduceMotion, treatment: store.preferences.visualTreatment, recipe: store.evolution.activeAppearanceRecipe, naturalVariation: store.evolution.naturalVariation)
                    AssistantTaskCue(activity: store.assistantActivity, quiet: store.preferences.quiet, reduceMotion: store.preferences.reduceMotion)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("A little more room to think.")
                        .font(.system(size: 21, weight: .medium, design: .rounded))
                    Text("Bring a document into your workspace, settle on a thought, and keep ARCHi nearby as you work.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                    AssistantConnectionSummary(store: store)
                }.padding(.top, 12)
                Spacer(minLength: 0)
            }.padding(.vertical, 4)

            WorkspaceCard {
                HStack {
                    Label("Shared with ARCHi", systemImage: "doc.text")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if store.sourceName != nil {
                        Button("Change document") { store.chooseDocument() }.buttonStyle(.borderless)
                        Button("Stop sharing") { store.requestStopSharing() }.buttonStyle(.borderless)
                    } else {
                        Button("Choose document…") { store.chooseDocument() }.buttonStyle(.bordered)
                    }
                }
                if let sourceName = store.sourceName {
                    Divider().padding(.vertical, 6)
                    Text(sourceName).font(.system(size: 12, weight: .medium)).foregroundStyle(ArchiPalette.violet)
                    Text(String(store.sharedText.prefix(1100)))
                        .font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                        .lineLimit(9).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Work together", systemImage: "doc.text.viewfinder") { store.section = .context }
                        .buttonStyle(.borderedProminent).padding(.top, 6)
                    Text("Excerpt from your working copy. Open Work together to select, review, and revise an exact passage. Send includes the full shared copy.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 3)
                } else {
                    Text("Choose a UTF-8 text file. You decide what comes into this workspace.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 5)
                }
            }

            AssistantReplyComposer(store: store)
        }
    }
}

@MainActor
private struct AssistantReplyComposer: View {
    @ObservedObject var store: CompanionStore
    var focusRequest = 0
    var constrained = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: constrained ? 8 : 12) {
            WorkspaceCard(fillsHeight: constrained, inset: constrained ? 16 : 22) {
                AssistantRouteSelector(store: store, compact: constrained)
                NextReplySettingsView(store: store)
                WorkReplyModePicker(store: store)
                Divider().padding(.vertical, constrained ? 4 : 8)
                HStack(spacing: 8) {
                    Image(systemName: "sparkle").foregroundStyle(ArchiPalette.violet)
                    Text("ARCHi").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    AssistantTaskCue(activity: store.assistantActivity, quiet: store.preferences.quiet, reduceMotion: store.preferences.reduceMotion)
                }
                if let selection = store.replySourceSelection {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(constrained ? "Selected passage" : "Source passage for this reply", systemImage: "text.quote")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(ArchiPalette.violet)
                        Text(selection.quote).font(.system(size: 12)).lineSpacing(4)
                            .lineLimit(constrained ? 1 : 4).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(selection.quote)
                    }
                    .padding(constrained ? 8 : 12)
                    .background(ArchiPalette.lilac.opacity(0.17), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, constrained ? 2 : 10)
                }
                if constrained {
                    ScrollView {
                        replyText
                    }
                    .frame(minHeight: 38, maxHeight: .infinity)
                    .accessibilityLabel("ARCHi reply")
                } else {
                    replyText
                }
                Divider().padding(.vertical, constrained ? 6 : 12)
                TextField("What would you like to work on?", text: $store.prompt, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(constrained ? 1...2 : 2...5)
                    .accessibilityLabel("Message to ARCHi")
                    .focused($composerFocused)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sendDisclosure).font(.system(size: constrained ? 10 : 11)).foregroundStyle(.secondary)
                        if store.connectionState != .ready && !store.isWorking {
                            Text(store.route == .compare ? "Connect both assistants before comparing." : "Connect \(store.assistantProvider.name) to send.")
                                .font(.system(size: constrained ? 10 : 11, weight: .medium)).foregroundStyle(ArchiPalette.violet)
                        }
                    }
                    Spacer()
                    if store.isWorking {
                        Button("Stop", systemImage: "stop.fill") { store.cancelWork() }
                            .buttonStyle(.bordered)
                            .keyboardShortcut(.cancelAction)
                            .help("Stop the current reply. The message already sent cannot be unsent.")
                    } else {
                        Button("Send", systemImage: "arrow.up") { store.submit() }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.connectionState != .ready || store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (store.requestsRevision && store.textSelection == nil))
                            .keyboardShortcut(.return, modifiers: .command)
                    }
                }.controlSize(constrained ? .small : .regular)
                    .padding(.top, constrained ? 4 : 12)
            }
            Text(constrained ? "Movement or context changes stop this reply." : "Moving ARCHi or changing shared context stops the current reply.")
                .font(.system(size: constrained ? 10 : 11)).foregroundStyle(.secondary)
        }
        .frame(maxHeight: constrained ? .infinity : nil, alignment: .top)
        .onChange(of: focusRequest) { _, _ in composerFocused = true }
    }

    private var replyText: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.compareResults.values.contains(where: { $0.revision != nil }) {
                Button("Review passage changes", systemImage: "doc.text.viewfinder") { store.section = .context }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("assistant.open-revision-review")
            }
            if store.route == .compare {
                ComparisonReplyPanels(store: store, compact: constrained)
            } else {
                Text(store.reply).font(.system(size: 14)).lineSpacing(5)
                if store.route == .local {
                    HamptonReplyReferences(snapshot: store.hamptonSnapshot)
                }
                EvolutionReplyFeedback(store: store, provider: store.assistantProvider)
                LessonReplyControls(store: store, provider: store.assistantProvider)
                if let receipt = store.compareResults[store.assistantProvider]?.receipt {
                    AssistantReceiptDetails(receipt: receipt)
                }
            }
        }
        .textSelection(.enabled).padding(.top, constrained ? 4 : 9)
        .frame(maxWidth: .infinity, minHeight: constrained ? 38 : 46, alignment: .topLeading)
    }

    private var sendDisclosure: String {
        if constrained {
            if store.isWorking {
                if store.replySourceSelection != nil { return "Replying using this message, full copy, and selected passage." }
                return store.sourceName == nil ? "Replying to this message." : "Replying using this message and the full shared copy."
            }
            if store.textSelection != nil { return "Send includes message, full copy, and selected passage." }
            return store.sourceName == nil ? "Send includes this message." : "Send includes this message and the full shared copy."
        }
        if store.isWorking {
            if store.replySourceSelection != nil {
                return "Sending your message, full shared copy, and selected passage, then receiving the reply."
            }
            return store.sourceName == nil ? "Sending your message and receiving the reply." : "Sending your message and full shared copy, then receiving the reply."
        }
        if store.textSelection != nil { return "Send includes your message, full shared copy, and selected passage." }
        return store.sourceName == nil ? "Send includes your message." : "Send includes your message and the full shared copy."
    }
}

@MainActor
private struct AssistantConnectionSummary: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(AssistantProvider.allCases) { provider in
                HStack(spacing: 6) {
                    Image(systemName: store.connection(for: provider) == .ready ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(ArchiPalette.violet)
                    Text("\(provider.name) · \(store.connection(for: provider).rawValue)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .help(store.message(for: provider))
            }
            Button("Manage connections") { store.open(.connections) }
                .buttonStyle(.borderless).font(.system(size: 11))
        }
        .frame(minHeight: 54, alignment: .topLeading)
    }
}

@MainActor
private struct AppearanceWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 24) {
                CompanionPresenceArt(form: store.preferences.form, family: store.evolution.activeFamily, size: 152, reduceMotion: store.preferences.reduceMotion, treatment: store.preferences.visualTreatment, recipe: store.evolution.activeAppearanceRecipe, naturalVariation: store.evolution.naturalVariation)
                    .frame(width: 200, height: 180)
                    .background(ArchiPalette.lilac.opacity(0.17), in: RoundedRectangle(cornerRadius: 28))
                VStack(alignment: .leading, spacing: 9) {
                    StatusPill(text: "Your current form", icon: "checkmark")
                    Text(store.evolution.activeFamily?.title ?? store.preferences.form.rawValue).font(.system(size: 25, weight: .medium, design: .rounded))
                    Text(store.evolution.activeFamily?.summary ?? store.preferences.form.description).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                }
                Spacer()
            }
            Text("Starting forms. Always yours to return to.").font(.system(size: 15, weight: .medium))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 115, maximum: 190), spacing: 12)], spacing: 12) {
                ForEach(CompanionForm.allCases) { form in
                    Button {
                        store.chooseStartingForm(form)
                    } label: {
                        VStack(spacing: 9) {
                            CompanionArt(form: form, size: 86, reduceMotion: true)
                            HStack(spacing: 5) {
                                Text(form.rawValue).font(.system(size: 12, weight: .medium))
                                if store.evolution.activeFamily == nil && form == store.preferences.form { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(ArchiPalette.violet) }
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(store.evolution.activeFamily == nil && form == store.preferences.form ? ArchiPalette.lilac.opacity(0.30) : ArchiPalette.lilac.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(store.evolution.activeFamily == nil && form == store.preferences.form ? ArchiPalette.violet.opacity(0.65) : .secondary.opacity(0.12), lineWidth: 1))
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Choose \(form.rawValue) form")
                        .accessibilityAddTraits(store.evolution.activeFamily == nil && form == store.preferences.form ? [.isSelected] : [])
                }
            }
            WorkspaceCard {
                if store.preferences.form == .companion && store.evolution.activeFamily == nil {
                    SettingsRow(title: "Companion finish", detail: "A softer, sculpted look. Your original stays available.", icon: "paintpalette") {
                        Picker("Companion finish", selection: $store.preferences.visualTreatment) {
                            ForEach(CompanionVisualTreatment.allCases) { treatment in
                                Text(treatment.rawValue).tag(treatment)
                            }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                        .accessibilityIdentifier("companion-visual-treatment")
                    }
                    if store.preferences.visualTreatment == .pearlStudy && CompanionVisualAsset.image == nil {
                        Text("Pearl study is unavailable. Your original is shown.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Divider().padding(.vertical, 10)
                }
                SettingsRow(title: "Desktop size", detail: "Make a little room, or a little more.", icon: "arrow.up.left.and.arrow.down.right") {
                    Slider(value: $store.preferences.size, in: 0.65...1.6)
                        .frame(width: 170).accessibilityLabel("Companion size")
                    Text(store.preferences.size, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 12).monospacedDigit()).frame(width: 43, alignment: .trailing)
                }
                Divider().padding(.vertical, 10)
                SettingsRow(title: "Gentle movement", detail: "Let the companion float softly while idle.", icon: "wind") {
                    Toggle("Gentle movement", isOn: Binding(get: { !store.preferences.reduceMotion }, set: { store.preferences.reduceMotion = !$0 })).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.vertical, 10)
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "sparkles").foregroundStyle(ArchiPalette.violet).frame(width: 24)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Adaptive appearance").font(.system(size: 13, weight: .medium))
                        Text("Let confirmed preferences and useful shared work inform a later shape. Your starting forms stay available.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    Spacer()
                    Button("Explore evolution") { store.open(.evolution) }.buttonStyle(.borderless)
                }
            }
            PreferenceFootnote(store: store)
        }
    }
}

@MainActor
private struct RhythmWorkspace: View {
    @ObservedObject var store: CompanionStore
    private let tones = ["Calm", "Direct", "Playful", "Warm"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceCard {
                Text("How we talk").font(.system(size: 16, weight: .medium))
                Text("Choose the voice you want to hear in ARCHi’s writing.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 12)
                Picker("Tone", selection: $store.preferences.tone) {
                    ForEach(tones, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented)
                Text("This preference guides the next reply from your connected assistant.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 10)
                Divider().padding(.vertical, 15)
                SettingsRow(title: "Reply length", detail: "From a quick thought to a little more detail.", icon: "text.alignleft") {
                    VStack(spacing: 5) {
                        Slider(value: $store.preferences.replyLength, in: 0...1).accessibilityLabel("Reply length")
                        HStack { Text("Brief"); Spacer(); Text("Detailed") }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(width: 210)
                }
            }
            WorkspaceCard {
                SettingsRow(title: "Quiet mode", detail: "Keep assistant task cues still while you work.", icon: "moon") {
                    Toggle("Quiet mode", isOn: $store.preferences.quiet).labelsHidden().toggleStyle(.switch)
                }
                Text("Proactive messages and scheduled quiet hours are not connected in this preview.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 12)
            }
            QuoteCard(text: "Useful when you need me. A little quieter when you don’t.", detail: "The direction for ARCHi’s timing")
            PreferenceFootnote(store: store)
        }
    }
}

@MainActor
private struct MemoryWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            KeptLessonsCard(store: store)
            WorkspaceCard {
                SettingsRow(title: "Temporary session context", detail: "Let local Qwen refer to useful excerpts from earlier questions during this visit.", icon: "text.bubble") {
                    Toggle("Temporary session context", isOn: Binding(get: { store.sessionContextEnabled }, set: { store.setSessionContextEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch).disabled(store.isShuttingDown)
                }
                Text("Off by default. Excerpts stay in this app’s memory and are cleared when you quit, turn this off, change models, or replace the shared copy. They are not used to train the models.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).padding(.top, 10)
                if store.route == .codex {
                    Text("Use Local Qwen or Compare both to include these excerpts. Codex never receives them.")
                        .font(.system(size: 11)).foregroundStyle(ArchiPalette.violet).padding(.top, 6)
                }
                Divider().padding(.vertical, 12)
                HStack {
                    Text("\(store.hamptonSnapshot.records.count) / 24 session excerpts").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Clear session context") { store.clearSessionContext() }
                        .disabled(store.isShuttingDown || (store.hamptonSnapshot.records.isEmpty && !store.isWorking))
                }
                if store.hamptonSnapshot.records.isEmpty {
                    Text("Nothing retained. Only a completed, accepted local reply can add excerpts here.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 10)
                } else {
                    ForEach(store.hamptonSnapshot.records) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.text).font(.system(size: 12)).textSelection(.enabled)
                            Text((record.kind == .document ? "Shared-copy excerpt" : "Your earlier message")
                                 + " · expires in \(max(0, record.expiresAtTurn - store.hamptonSnapshot.turn)) completed context turns")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                        Divider()
                    }
                    Text("These are source excerpts, not independently verified facts. Current instructions take precedence.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
            WorkspaceCard {
                SettingsRow(title: "Remember my preferences", detail: "Save the choices below on this Mac when you press Save.", icon: "bookmark") {
                    Toggle("Remember my preferences", isOn: $store.rememberPreferences).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.vertical, 15)
                HStack(alignment: .top, spacing: 28) {
                    PreferenceSummary(title: "Appearance", value: store.preferences.form.rawValue, detail: "Size and motion")
                    PreferenceSummary(title: "Personal rhythm", value: store.preferences.tone, detail: "Reply length and quiet mode")
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("Save preferences", systemImage: "checkmark") { store.savePreferences() }
                        .buttonStyle(.borderedProminent).disabled(!store.rememberPreferences)
                    Button("Forget saved preferences", role: .destructive) { store.forgetPreferences() }
                        .buttonStyle(.borderless)
                    Spacer()
                }.padding(.top, 16)
            }
            WorkspaceCard {
                Label("Your choices are the starting point", systemImage: "hand.raised")
                    .font(.system(size: 15, weight: .medium))
                Text("ARCHi saves the appearance, rhythm and lessons you explicitly keep in its settings file. Kept lessons go only to local Qwen when their scope matches. Temporary session context is separate. Send shares your message, the full shared document copy, and any selected passage with your connected assistant.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5).padding(.top, 7)
                Text("Turning the switch off does not erase saved choices. Forget saved preferences removes saved appearance and rhythm; withdraw lessons individually above.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
    }
}

@MainActor
struct PlacementPreviewCard: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        WorkspaceCard(fillsHeight: true, inset: 14) {
            HStack(spacing: 7) {
                Label("Beside this passage", systemImage: "arrow.up.right")
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Text(store.isRecordingSpatial ? "RECORDING" : store.spatialPreview == nil ? "LOCAL" : "PREVIEW")
                    .font(.system(size: 9, weight: .medium)).tracking(0.8)
                    .foregroundStyle(ArchiPalette.violet)
            }
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                .lineSpacing(2).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                .help(message)
                .accessibilityLabel(message)
            HStack(spacing: 10) {
                if let preview = store.spatialPreview {
                    Button(preview.candidate.staysPut ? "Stay here" : "Move here", systemImage: preview.candidate.staysPut ? "checkmark" : "arrow.up.right") {
                        store.applyPlacementPreview()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .fixedSize(horizontal: true, vertical: true)
                    .disabled(store.isWorking)
                    .accessibilityIdentifier("placement.apply")
                    Button("Dismiss") { store.dismissPlacementPreview() }
                        .buttonStyle(.borderless).controlSize(.small)
                        .fixedSize(horizontal: true, vertical: true)
                        .accessibilityLabel("Dismiss placement preview")
                        .accessibilityIdentifier("placement.dismiss")
                } else {
                    Button("Preview placement", systemImage: "viewfinder") { store.previewPlacement() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .fixedSize(horizontal: true, vertical: true)
                        .disabled(store.textSelection == nil || store.isWorking)
                        .accessibilityIdentifier("placement.preview")
                        .help("Preview a spot beside the selected passage. ARCHi moves only after you choose Move here.")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var message: String {
        if let preview = store.spatialPreview { return preview.candidate.reason }
        return store.spatialMessage.isEmpty ? "Preview a spot without moving ARCHi." : store.spatialMessage
    }
}

@MainActor
private struct ConnectionsWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkspaceCard {
                Text("Both, when you need them.")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                Text("Keep Qwen and Codex connected independently. Choose who answers each request, or compare their replies. Changing the route sends nothing.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4).padding(.top, 6)
                Divider().padding(.vertical, 12)
                AssistantRouteSelector(store: store)
            }
            AssistantProviderPanel(store: store, provider: .qwen)
            AssistantProviderPanel(store: store, provider: .codex)
            ReactorExpressionPanel(reactor: store.reactor)
            WorkspaceCard {
                ConnectionRow(icon: "desktopcomputer", title: "Desktop companion", detail: "Local window, movement, form choices, and menus.", status: "Available", available: true)
                Divider().padding(.vertical, 12)
                ConnectionRow(icon: "doc.text", title: "Local documents", detail: "Share one UTF-8 text file with this workspace.", status: "Available", available: true)
                Divider().padding(.vertical, 12)
                ConnectionRow(icon: "camera", title: "Camera & AR", detail: "Bring ARCHi into a camera view with anchored highlights.", status: "Planned", available: false)
            }
        }
    }
}

@MainActor
private struct AccessibilityWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceCard {
                SettingsRow(title: "Reduce motion", detail: "Keep ARCHi still while idle.", icon: "figure.stand") {
                    Toggle("Reduce motion", isOn: $store.preferences.reduceMotion).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.vertical, 12)
                SettingsRow(title: "Companion size", detail: "Make ARCHi easier to see on your desktop.", icon: "arrow.up.left.and.arrow.down.right") {
                    Slider(value: $store.preferences.size, in: 0.65...1.6).frame(width: 180).accessibilityLabel("Companion size")
                }
            }
            WorkspaceCard {
                Label("At your keyboard", systemImage: "keyboard").font(.system(size: 16, weight: .medium))
                KeyboardRow(action: "Move between controls", keys: "Tab / Shift Tab")
                KeyboardRow(action: "Send the composer text", keys: "⌘ Return")
                KeyboardRow(action: "Close the workspace", keys: "⌘ W")
                Divider().padding(.vertical, 10)
                Text("Use macOS Keyboard Navigation to reach all controls with Tab. Every appearance option includes a VoiceOver label.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }
            PreferenceFootnote(store: store)
        }
    }
}

@MainActor
private struct AdvancedWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceCard {
                Label("Local role receipts", systemImage: "list.bullet.clipboard")
                    .font(.system(size: 15, weight: .medium))
                Text(store.hamptonSnapshot.phase).font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Each receipt records a completed role whose output passed structural and reference checks. This does not establish that the answer is true. No raw prompts or hidden reasoning are recorded here.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).padding(.vertical, 8)
                ForEach(store.hamptonSnapshot.receipts) { receipt in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(receipt.role.rawValue) · \(receipt.model.name) · \(receipt.elapsedMilliseconds) ms")
                            .font(.system(size: 11, weight: .medium))
                        Text("Model \(receipt.model.digest.prefix(12)) · input \(receipt.inputDigest.prefix(12)) · output \(receipt.outputDigest.prefix(12))")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
            }
            WorkspaceCard {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 34, weight: .light)).foregroundStyle(ArchiPalette.violet)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ARCHi Node Lab").font(.system(size: 20, weight: .medium, design: .rounded))
                        Text("A place to inspect a workflow, replay changes, and test what happens when context moves.")
                            .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                        Button("Open Node Lab", systemImage: "arrow.up.right") { store.onOpenLab?() }
                            .buttonStyle(.borderedProminent).disabled(store.onOpenLab == nil).padding(.top, 8)
                    }
                }
                Text("The lab offers scripted replays and local imports of native placement recordings. Replay cannot move your desktop companion.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 16)
            }
            WorkspaceCard {
                Label("Record placement geometry", systemImage: "record.circle")
                    .font(.system(size: 15, weight: .medium))
                Text("Capture positions, proposals, timing, and outcomes. Document text, filenames, device identifiers, and absolute screen origins are excluded.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                HStack(spacing: 12) {
                    if store.isRecordingSpatial {
                        Button("Stop recording", systemImage: "stop.fill") { store.stopSpatialRecording() }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("recording.stop")
                    } else {
                        Button(store.spatialRecordCount == 0 ? "Start recording" : "New recording", systemImage: "record.circle") { store.startSpatialRecording() }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("recording.start")
                    }
                    Text("\(store.spatialRecordCount) / 100 previews").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.vertical, 5)
                HStack(spacing: 12) {
                    Button("Export recording…", systemImage: "square.and.arrow.up") { store.exportSpatialRecording() }
                        .disabled(store.isRecordingSpatial || store.spatialRecordCount == 0)
                        .accessibilityIdentifier("recording.export")
                    Button("Clear") { store.clearSpatialRecording() }
                        .disabled(store.isRecordingSpatial || store.spatialRecordCount == 0)
                        .accessibilityLabel("Clear placement recording")
                }
                Text(store.spatialRecordingMessage).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                if store.spatialRecordCount > 0 && !store.isRecordingSpatial {
                    Text("New recording replaces this session’s retained recording. It does not change exported files.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            WorkspaceCard {
                Label("This session", systemImage: "clock.arrow.circlepath").font(.system(size: 15, weight: .medium))
                HStack(spacing: 30) {
                    PreferenceSummary(title: "Placement", value: String(store.placementRevision), detail: "Current revision")
                    PreferenceSummary(title: "Shared source", value: String(store.sourceRevision), detail: "Current revision")
                }.padding(.vertical, 12)
                if let receipt = store.lastPlacementReceipt {
                    Divider().padding(.vertical, 8)
                    Label("Last placement check", systemImage: "viewfinder")
                        .font(.system(size: 12, weight: .medium))
                    Text("Requested: " + String(describing: receipt.requestedFrame))
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Text("Observed: " + (receipt.actualFrame.map { String(describing: $0) } ?? "Unavailable"))
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Divider().padding(.vertical, 8)
                }
                if store.activity.isEmpty {
                    Text("Desktop and context changes will appear here.").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.activity.suffix(8).enumerated()), id: \.offset) { _, entry in
                        Text(entry).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                }
            }
        }
    }
}

struct WorkspaceCard<Content: View>: View {
    var fillsHeight = false
    var inset: CGFloat = 22
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(inset).frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.065), lineWidth: 1))
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String
    let icon: String
    @ViewBuilder let control: Control
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon).foregroundStyle(ArchiPalette.violet).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            control
        }.padding(.vertical, 4)
    }
}

private struct StatusPill: View {
    let text: String
    let icon: String
    var body: some View {
        Label(text, systemImage: icon).font(.system(size: 10, weight: .medium))
            .foregroundStyle(ArchiPalette.violet)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(ArchiPalette.lilac.opacity(0.25), in: Capsule())
    }
}

private struct QuoteCard: View {
    let text: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.system(size: 20, weight: .regular, design: .rounded)).lineSpacing(4)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(ArchiPalette.lilac.opacity(0.16), in: RoundedRectangle(cornerRadius: 20))
    }
}

@MainActor
private struct PreferenceFootnote: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        HStack(spacing: 6) {
            Text("Keep these choices for next time in")
            Button("What I remember") { store.section = .memory }.buttonStyle(.borderless)
            Spacer(minLength: 0)
        }.font(.system(size: 11)).foregroundStyle(.secondary)
    }
}

private struct PreferenceSummary: View {
    let title: String
    let value: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .medium, design: .rounded))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConnectionRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: String
    let available: Bool
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon).font(.system(size: 19, weight: .light)).foregroundStyle(ArchiPalette.violet).frame(width: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            }
            Spacer(minLength: 20)
            Label(status, systemImage: available ? "checkmark.circle" : "circle.dashed")
                .font(.system(size: 11)).foregroundStyle(available ? ArchiPalette.violet : .secondary)
        }.padding(.vertical, 6)
    }
}

private struct KeyboardRow: View {
    let action: String
    let keys: String
    var body: some View {
        HStack {
            Text(action).font(.system(size: 12))
            Spacer()
            Text(keys).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
        }.padding(.top, 10)
    }
}

private extension CompanionForm {
    var description: String {
        switch self {
        case .companion: "A soft, familiar presence beside your work."
        case .light: "A small glow, with just enough personality."
        case .ribbon: "A fluid line that gives your desk a little movement."
        case .ink: "A quiet mark with a playful point of view."
        case .pixel: "A little nostalgia, one square at a time."
        }
    }
}

private extension WorkspaceSection {
    var icon: String {
        switch self {
        case .assistant: "bubble.left.and.bubble.right"
        case .play: "gamecontroller"
        case .appearance: "paintpalette"
        case .evolution: "sparkles"
        case .rhythm: "waveform"
        case .memory: "bookmark"
        case .context: "doc.text.viewfinder"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .accessibility: "accessibility"
        case .advanced: "slider.horizontal.3"
        }
    }
    var eyebrow: String {
        switch self {
        case .assistant: "A little space to think"
        case .play: "Your world of play"
        case .appearance, .evolution, .rhythm: "Make it yours"
        case .memory, .context: "Always your choice"
        case .connections, .accessibility, .advanced: "Your workspace"
        }
    }
    var heading: String {
        switch self {
        case .assistant: "Here, with you."
        case .play: "A little room to play."
        case .appearance: "A familiar presence. Your style."
        case .evolution: "A life together."
        case .rhythm: "At your pace. In your tone."
        case .memory: "What I remember"
        case .context: "Work together"
        case .connections: "A world of connections"
        case .accessibility: "Comfort comes first"
        case .advanced: "A closer look"
        }
    }
    var subtitle: String {
        switch self {
        case .assistant: "Your thoughts, your context, and a companion close by."
        case .play: "Return to your Habitat, continue your Journey, and meet in the Practice Arena."
        case .appearance: "Choose how ARCHi shows up on your desktop."
        case .evolution: "Familiar family traits. Small individual differences. Shared experiences."
        case .rhythm: "Set the kind of conversation that feels right for you."
        case .memory: "Keep the preferences you choose. Change your mind whenever you like."
        case .context: "Keep your draft in view. Review each change before it becomes your working copy."
        case .connections: "See what’s available and what’s still taking shape."
        case .accessibility: "A little more space, a little less motion, and familiar controls."
        case .advanced: "Tools for exploring how ARCHi works."
        }
    }
}
