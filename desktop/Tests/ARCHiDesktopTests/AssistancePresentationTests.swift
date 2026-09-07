import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import ARCHiDesktop

final class AssistancePresentationTests: XCTestCase {
    func testQuietAndBothReduceMotionSettingsKeepEveryTaskCueStill() {
        for activity in AssistantActivity.allCases {
            XCTAssertFalse(activity.animates(quiet: true, reduceMotion: false, systemReduceMotion: false))
            XCTAssertFalse(activity.animates(quiet: false, reduceMotion: true, systemReduceMotion: false))
            XCTAssertFalse(activity.animates(quiet: false, reduceMotion: false, systemReduceMotion: true))
        }
        XCTAssertTrue(AssistantActivity.working.animates(quiet: false, reduceMotion: false, systemReduceMotion: false))
        XCTAssertTrue(AssistantActivity.responding.animates(quiet: false, reduceMotion: false, systemReduceMotion: false))
        XCTAssertFalse(AssistantActivity.ready.animates(quiet: false, reduceMotion: false, systemReduceMotion: false))
    }

    /// Real native window, retained bundled Play, and AppKit floating accessibility.
    /// The controlled assistant keeps each lifecycle stage inspectable without inference.
    @MainActor
    func testNativeActivityPreservesPlacementArtworkAndRetainedPlay() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let assets = env["ARCHI_HOSTED_ASSETS_DIR"], let directory = env["ARCHI_ASSISTANCE_UI_DIR"] else {
            throw XCTSkip("Provide native Play assets and ARCHI_ASSISTANCE_UI_DIR for native assistance acceptance.")
        }
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        let policy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(policy) }
        let client = PresentationClient()
        let store = CompanionStore(preferenceURL: output.appendingPathComponent("unused-preferences.json"), assistant: client)
        store.preferences.reduceMotion = true
        store.preferences.visualTreatment = .pearlStudy
        store.evolution.confirmRole(.beacon)
        store.evolution.confirmHelpStyle(.stepByStep)
        let panel = CompanionPanelController(store: store)
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: URL(fileURLWithPath: assets))
        store.section = .play
        let window = NSWindow(contentRect: NSRect(x: 90, y: 90, width: 880, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ARCHi · Assistance acceptance"
        let hosting = NSHostingView(rootView: WorkspaceView(store: store, playHost: host))
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        app.activate()
        var evidence: [[String: Any]] = []
        do {
            try await wait { host.state == .ready || host.state == .unavailable }
            XCTAssertEqual(host.state, .ready, host.status)
            let retained = try XCTUnwrap(host.webView)
            try await wait {
                (try? await retained.callAsyncJavaScript("return JSON.parse(window.render_game_to_text()).companion.nativeAppearance?.ready === true;",
                    arguments: [:], in: nil, contentWorld: .page)) as? Bool == true
            }
            let before = try await gameIdentity(retained)
            let art = CompanionPresenceArt.png(form: store.preferences.form, family: nil, treatment: .pearlStudy)
            let placement = store.placementRevision, frame = panel.window.frame
            let evolutionRevision = store.evolution.revision
            store.connectAssistant()
            try await wait { store.connectionState == .ready }

            func inspect(_ name: String) async throws {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(120))
                let rect = retained.convert(retained.bounds, to: nil)
                XCTAssertTrue(window.contentLayoutRect.insetBy(dx: -1, dy: -1).contains(rect))
                XCTAssertGreaterThan(rect.height, 200)
                XCTAssertTrue(host.webView === retained)
                let identity = try await gameIdentity(retained)
                XCTAssertEqual(identity, before)
                XCTAssertEqual(panel.window.frame, frame)
                XCTAssertEqual(store.placementRevision, placement)
                XCTAssertEqual(store.evolution.revision, evolutionRevision)
                XCTAssertEqual(CompanionPresenceArt.png(form: store.preferences.form, family: nil, treatment: .pearlStudy), art)
                XCTAssertEqual(panel.window.contentView?.accessibilityValue() as? String, store.assistantAccessibilityValue)
                let labels = accessibilityStrings(hosting)
                XCTAssertTrue(labels.contains(where: { $0.contains("Assistant: " + store.assistantActivity.title) }), labels.joined(separator: " | "))
                evidence.append(["stage": name, "activity": store.assistantActivity.rawValue,
                    "window": NSStringFromRect(window.contentLayoutRect), "play": NSStringFromRect(rect),
                    "placementRevision": String(placement), "gameIdentity": before,
                    "accessibility": labels])
                if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name + ".png"))
                }
            }

            try await inspect("idle-minimum")
            store.prompt = "Help with the synthetic note."
            store.submit()
            try await wait { client.pending != nil }
            XCTAssertEqual(store.assistantActivity, .working)
            try await inspect("working-minimum")
            client.emit("A useful synthetic answer.")
            XCTAssertEqual(store.assistantActivity, .responding)
            store.preferences.quiet = true
            try await inspect("responding-quiet")
            client.finish()
            try await wait { !store.isWorking }
            window.setContentSize(NSSize(width: 1080, height: 750))
            try await inspect("ready-large")
            store.section = .assistant
            try await Task.sleep(for: .milliseconds(150))
            let assistantLabels = accessibilityStrings(hosting)
            XCTAssertTrue(assistantLabels.contains(where: { $0.contains("Next reply") }))
            XCTAssertTrue(assistantLabels.contains(where: { $0.contains("Sent with") }))
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("assistant-ready.png"))
            }
            store.section = .play
            try await Task.sleep(for: .milliseconds(150))
            panel.setPresentedInHabitat(true)
            panel.setPresentedInHabitat(false)
            store.submit()
            try await wait { client.pending != nil }
            store.cancelWork()
            client.emit("Late cancelled text")
            XCTAssertEqual(store.assistantActivity, .stopped)
            try await inspect("stopped-large")
            try JSONSerialization.data(withJSONObject: ["schema": "archi-assistance-native/v1", "samples": evidence],
                options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("native-acceptance.json"))
        } catch {
            await host.shutdown(); await store.shutdownAssistant()
            window.contentView = nil; window.close(); panel.hide()
            throw error
        }
        await host.shutdown(); await store.shutdownAssistant()
        window.contentView = nil; window.close(); panel.hide()
    }

    @MainActor private func gameIdentity(_ view: WKWebView) async throws -> String {
        let value = try await view.callAsyncJavaScript("const s=JSON.parse(window.render_game_to_text()); return JSON.stringify({session:window.__ARCHI_DESKTOP_BOOTSTRAP__.sessionId,revision:s.journey.revision,appearance:s.companion.nativeAppearance.id});",
            arguments: [:], in: nil, contentWorld: .page)
        return try XCTUnwrap(value as? String)
    }

    @MainActor private func wait(_ condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !(try await condition()) {
            if Date() > deadline { throw NSError(domain: "AssistancePresentation", code: 1) }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    @MainActor private func accessibilityStrings(_ root: AnyObject, depth: Int = 0) -> [String] {
        guard depth < 30, let element = root as? NSObject else { return [] }
        func modern(_ name: String) -> Any? {
            let selector = NSSelectorFromString(name)
            return element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() : nil
        }
        let attributes = element.accessibilityAttributeNames()
        var values = [NSAccessibility.Attribute.title, .description, .value].compactMap { attribute in
            attributes.contains(attribute) ? element.accessibilityAttributeValue(attribute) as? String : nil
        }
        values += [modern("accessibilityLabel"), modern("accessibilityValue"), modern("accessibilityTitle")].compactMap { $0 as? String }
        let children = modern("accessibilityChildren") as? [Any]
            ?? (attributes.contains(.children) ? element.accessibilityAttributeValue(.children) as? [Any] ?? [] : [])
        for child in children { values += accessibilityStrings(child as AnyObject, depth: depth + 1) }
        return values
    }
}

@MainActor private final class PresentationClient: AssistantClient {
    var pending: CheckedContinuation<Void, any Error>?
    var event: (@MainActor (AssistantEvent) -> Void)?
    func connect() async throws {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        event = onEvent
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func emit(_ text: String) { event?(.text(text)) }
    func finish() { let value = pending; pending = nil; value?.resume() }
    func disconnect() { let value = pending; pending = nil; value?.resume(throwing: AssistantFailure.stopped) }
}
