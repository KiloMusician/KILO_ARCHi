import AppKit
import SwiftUI

@MainActor
struct DesktopInterestCard: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var session: DesktopInterestSession

    init(store: CompanionStore) { self.store = store; self.session = store.desktopInterest }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Object of interest", systemImage: "viewfinder")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(ArchiPalette.violet)
            if let target = session.target {
                Text(target.appName + " · " + target.title)
                    .font(.system(size: 12, weight: .medium)).lineLimit(2)
            }
            Text(session.message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("interest.status")
            if let capture = session.capture, session.phase == .review {
                Text(capture.method).font(.system(size: 10)).foregroundStyle(.secondary)
                ScrollView {
                    Text(capture.text).font(.system(size: 12)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                .frame(height: 130).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("interest.snapshot")
                Text("\(capture.text.utf8.count.formatted()) bytes · captured \(capture.capturedAt.formatted(date: .omitted, time: .shortened)) · local copy")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Button("Use in Work together", systemImage: "doc.text") { store.useDesktopInterestCapture() }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("interest.use")
            }
            HStack {
                switch session.phase {
                case .targeted:
                    Button("Read this window", systemImage: "text.viewfinder") { session.read() }
                        .accessibilityIdentifier("interest.read")
                case .aiming:
                    Button("Choose highlighted window") { session.finishAim() }
                        .disabled(session.target == nil).accessibilityIdentifier("interest.choose")
                case .reading:
                    ProgressView().controlSize(.small).accessibilityLabel("Reading selected window locally")
                case .idle, .failed, .review:
                    Button("Point at a window", systemImage: "scope") { store.beginDesktopInterest() }
                        .accessibilityIdentifier("interest.begin")
                }
                Spacer(minLength: 0)
                if session.phase != .idle {
                    Button(session.phase == .reading ? "Stop" : "Clear") { session.cancel() }
                        .accessibilityIdentifier("interest.clear")
                }
            }.buttonStyle(.bordered).controlSize(.small)
            if session.phase == .failed {
                HStack {
                    Button("Accessibility settings") { openPrivacy("Privacy_Accessibility") }
                    Button("Screen Recording settings") { openPrivacy("Privacy_ScreenCapture") }
                }.buttonStyle(.link).font(.system(size: 10))
            }
            Text("Reads app text or visible text with local OCR. Images are not saved or sent. Original apps are not edited.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain).accessibilityIdentifier("interest.card")
    }

    private func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
struct DesktopInterestSharingNotice: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        if let source = store.desktopInterestSource {
            VStack(alignment: .leading, spacing: 5) {
                Label("Window snapshot · " + source.method, systemImage: "viewfinder")
                    .font(.system(size: 11, weight: .medium))
                Text("Captured \(source.capturedAt.formatted(date: .abbreviated, time: .shortened)). The original window can change; this copy does not refresh automatically.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                if !store.canShareDesktopInterestWithRoute {
                    Text("This copy is local. Your selected route includes Codex.").font(.system(size: 11))
                    Button("Allow this copy with \(store.route.title)") { store.allowDesktopInterestWithExternalRoute() }
                        .buttonStyle(.bordered).controlSize(.small).accessibilityIdentifier("interest.allow-external")
                } else {
                    Text(store.route == .local || store.route == .automatic
                         ? "Only Local Qwen receives this copy when you press Send."
                         : "This exact copy may be sent to your selected route when you press Send.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain).accessibilityIdentifier("interest.sharing")
        }
    }
}

/// Click-through native outline. A rectangle is a selection cue, not a captured
/// image or a claim that the model has already observed this window.
@MainActor
final class DesktopInterestOutline {
    private let panel: NSPanel
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "ARCHi selected window"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.level = .floating
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: RoundedRectangle(cornerRadius: 9)
            .stroke(Color.mint, lineWidth: 4).padding(3).accessibilityHidden(true))
    }
    func show(_ frame: CGRect?) {
        guard let frame, !frame.isEmpty, [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) else {
            panel.orderOut(nil); return
        }
        panel.setFrame(frame, display: true, animate: false)
        panel.orderFrontRegardless()
    }
}
