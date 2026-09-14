import SwiftUI

/// Same owner and actions in all three native composers. A transcript is a
/// visible candidate; only Use text appends it, and Send remains separate.
@MainActor
struct VoiceInputControls: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject private var voice: VoiceInputController
    let surface: VoiceInputSurface

    init(store: CompanionStore, surface: VoiceInputSurface) {
        self.store = store
        self.voice = store.voiceInput
        self.surface = surface
    }

    var body: some View {
        HStack(spacing: 8) {
                switch voice.phase {
                case .idle, .failed:
                    Button("Dictate", systemImage: "mic") { store.beginVoiceInput(from: surface) }
                        .disabled(store.isWorking || store.isShuttingDown)
                        .accessibilityIdentifier("voice.start")
                        .help("Uses your current macOS language (\(Locale.current.identifier)) when on-device speech is available. Recording stops after 30 seconds. Review the text before using it; Send stays separate.")
                    Text("Local · review before Send").foregroundStyle(.secondary)
                case .authorizing:
                    Text("Checking access…").foregroundStyle(.secondary)
                case .recording:
                    Label("Recording locally", systemImage: "mic.fill").foregroundStyle(.red)
                    Spacer(minLength: 0)
                    Button("Finish") { voice.finish() }.accessibilityIdentifier("voice.finish")
                case .finalizing:
                    Text("Finishing · mic stopped").foregroundStyle(.secondary)
                case .review:
                    Button("Use text", systemImage: "text.badge.plus") { store.appendVoiceTranscript() }
                        .disabled(store.isWorking || store.isShuttingDown)
                        .accessibilityIdentifier("voice.use-text")
                    Text("Add to your draft").foregroundStyle(.secondary)
                }
                if voice.phase != .idle && voice.phase != .failed {
                    Button(voice.phase == .review ? "Discard" : "Cancel") { voice.cancel() }
                        .accessibilityIdentifier("voice.cancel")
                }
        }
        .font(.system(size: 10)).buttonStyle(.borderless).controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Local voice input")
        .onDisappear { voice.cancel(ifOwnedBy: surface) }
    }
}

/// Lives in the existing reply scroll, keeping the fixed composer controls
/// reachable even in the smallest bubble. The full candidate can be read.
@MainActor
struct VoiceTranscriptPreview: View {
    @ObservedObject var voice: VoiceInputController
    var body: some View {
        if voice.showsDetails {
            VStack(alignment: .leading, spacing: 5) {
                Text(voice.message).font(.system(size: 10)).foregroundStyle(.secondary)
                if !voice.transcript.isEmpty {
                    Text(voice.transcript).font(.system(size: 12))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(ArchiPalette.lilac.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("voice.transcript")
        }
    }
}
