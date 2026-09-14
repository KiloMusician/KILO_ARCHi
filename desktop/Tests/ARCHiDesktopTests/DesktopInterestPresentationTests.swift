import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class DesktopInterestPresentationTests: XCTestCase {
    @MainActor
    func testNativePointReadReviewAndAdoptControlsUseTheExistingCopy() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_INTEREST_NATIVE"] == "1" else {
            throw XCTSkip("Set ARCHI_INTEREST_NATIVE=1 for the synthetic native object-of-interest controls.")
        }
        let app = NSApplication.shared, policy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer { _ = app.setActivationPolicy(policy) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-interest-ui-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = InterestPresentationReader(), assistant = InterestPresentationAssistant()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("profile.json"),
            assistant: assistant, allowsPlay: false, interestReader: reader)
        store.prompt = "Help me plan this workshop."
        let window = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 390, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ARCHi · synthetic target review"
        let host = NSHostingView(rootView: DesktopInterestCard(store: store).padding(15)
            .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.light))
        host.sizingOptions = []
        window.contentView = host
        window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(180))
        try press("interest.begin", root: window)
        XCTAssertEqual(store.desktopInterest.phase, .aiming)
        store.desktopInterest.hover(at: CGPoint(x: 120, y: 120))
        try await Task.sleep(for: .milliseconds(100))
        try press("interest.choose", root: window)
        XCTAssertEqual(reader.reads, 0)
        try await Task.sleep(for: .milliseconds(100))
        try press("interest.read", root: window)
        for _ in 0..<100 where store.desktopInterest.phase != .review {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(store.desktopInterest.phase, .review)
        XCTAssertEqual(reader.reads, 1)
        XCTAssertNil(store.sourceName)
        host.layoutSubtreeIfNeeded()
        if let path = ProcessInfo.processInfo.environment["ARCHI_INTEREST_RENDER_DIR"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to:
                URL(fileURLWithPath: path).appendingPathComponent("native-target-review.png"))
        }
        try press("interest.use", root: window)
        XCTAssertEqual(store.sharedText, "Workshop: Friday at 3 PM. Bring the revised outline.")
        XCTAssertEqual(store.prompt, "Help me plan this workshop.")
        XCTAssertEqual(store.section, .context)
        XCTAssertEqual(store.desktopInterest.phase, .idle)
        let play = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let workspace = WorkspaceView.makeHostingView(store: store, playHost: play)
        window.contentView = workspace
        WorkspaceView.applyWindowMinimum(to: window)
        window.setContentSize(CGSize(width: 880, height: 640))
        store.setAssistantRoute(.codex)
        try await Task.sleep(for: .milliseconds(200))
        workspace.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(workspace.bounds.width, 881)
        XCTAssertLessThanOrEqual(workspace.bounds.height, 641)
        XCTAssertFalse(store.canShareDesktopInterestWithRoute)
        try press("interest.allow-external", root: window)
        XCTAssertTrue(store.canShareDesktopInterestWithRoute)
        if let path = ProcessInfo.processInfo.environment["ARCHI_INTEREST_RENDER_DIR"],
           let bitmap = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds) {
            workspace.cacheDisplay(in: workspace.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to:
                URL(fileURLWithPath: path).appendingPathComponent("work-together-880.png"))
        }
        XCTAssertNil(play.webView)
        XCTAssertEqual(assistant.calls, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        await store.shutdownAssistant()
        await play.shutdown()
    }

    @MainActor private func nodes(_ root: NSObject) -> [NSObject] {
        var found: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ node: NSObject, depth: Int) {
            guard depth < 35, found.count < 2000, seen.insert(ObjectIdentifier(node)).inserted else { return }
            found.append(node)
            let selector = NSSelectorFromString("accessibilityChildren")
            if node.responds(to: selector), let children = node.perform(selector)?.takeUnretainedValue() as? [NSObject] {
                for child in children { visit(child, depth: depth + 1) }
            }
            if node.accessibilityAttributeNames().contains(.children) {
                for child in node.accessibilityAttributeValue(.children) as? [NSObject] ?? [] { visit(child, depth: depth + 1) }
            }
            if let window = node as? NSWindow, let content = window.contentView { visit(content, depth: depth + 1) }
            if let view = node as? NSView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        visit(root, depth: 0); return found
    }
    @MainActor private func press(_ identifier: String, root: NSObject) throws {
        let node = try XCTUnwrap(nodes(root).first {
            let selector = NSSelectorFromString("accessibilityIdentifier")
            return ($0.responds(to: selector) ? $0.perform(selector)?.takeUnretainedValue() as? String : nil) == identifier
                || ($0.accessibilityAttributeNames().contains(.identifier)
                    && $0.accessibilityAttributeValue(.identifier) as? String == identifier)
        }, "Missing native control \(identifier)")
        let selector = NSSelectorFromString("accessibilityPerformPress")
        XCTAssertTrue(node.responds(to: selector))
        guard node.responds(to: selector) else { return }
        let action = unsafeBitCast(node.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
        XCTAssertTrue(action(node, selector))
    }
}

@MainActor private final class InterestPresentationReader: DesktopInterestReading {
    var reads = 0
    let selected = DesktopInterestTarget(windowID: 991, processID: 999,
        appName: "Synthetic Notes", title: "Workshop", frame: CGRect(x: 100, y: 100, width: 600, height: 420),
        observedAt: Date(timeIntervalSince1970: 1_800_000_000))
    func target(at point: CGPoint) -> DesktopInterestTarget? { selected }
    func isCurrent(_ target: DesktopInterestTarget) -> Bool { target == selected }
    func read(_ target: DesktopInterestTarget) async throws -> DesktopInterestCapture {
        reads += 1
        return DesktopInterestCapture(target: selected,
            text: "Workshop: Friday at 3 PM. Bring the revised outline.", method: "Synthetic app-exposed text fixture", capturedAt: selected.observedAt)
    }
}
@MainActor private final class InterestPresentationAssistant: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1 }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws { calls += 1 }
}
