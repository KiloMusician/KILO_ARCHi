import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import ARCHiDesktop

final class HostedArenaReadbackWebKitTests: XCTestCase {
    @MainActor
    func testActualNativeMatchReadbackKeepAndReload() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let assets = env["ARCHI_HOSTED_ASSETS_DIR"], let directory = env["ARCHI_ARENA_STATUS_FIXTURES_DIR"] else {
            throw XCTSkip("Provide bundled assets and ARCHI_ARENA_STATUS_FIXTURES_DIR for native match acceptance.")
        }
        let output = URL(fileURLWithPath: directory).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared, policy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer { _ = app.setActivationPolicy(policy) }
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: URL(fileURLWithPath: assets))
        let store = CompanionStore(preferenceURL: output.appendingPathComponent("unused-preferences.json"))
        store.section = .play
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 880, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "ARCHi · Battle readback acceptance"
        let hosting = NSHostingView(rootView: WorkspaceView(store: store, playHost: host))
        window.contentView = hosting; window.makeKeyAndOrderFront(nil); app.activate()
        host.setVisible(true); host.start()
        defer { window.contentView = nil; window.close() }
        var originalStorage: String?
        do {
            try await wait("Bundled game ready") { host.state == .ready || host.state == .unavailable }
            XCTAssertEqual(host.state, .ready, host.status)
            host.setVisible(true)
            try await wait("Visible Journey ready") { host.projection?.visible == true && host.projection?.readiness == .ready }
            let view = try XCTUnwrap(host.webView)
            originalStorage = try await text(view, "return JSON.stringify(localStorage.getItem('archi.journey.v3'));")
            let originalRevision = host.projection?.revision, originalCount = try XCTUnwrap(host.projection?.eventCount)
            let originalSession = host.sessionID
            try await act("start", host: host)
            XCTAssertEqual(host.projection?.version, 4)
            XCTAssertNil(host.projection?.arena?.readback?.result)
            XCTAssertEqual(host.projection?.arena?.readback?.rounds.count, 0)
            try await assertReadback(host, view: view)
            hosting.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            // Activation and SwiftUI's AX proxies settle asynchronously after a
            // prior UI test; a fixed delay is not a readiness signal.
            window.makeKeyAndOrderFront(nil); app.activate()
            try await wait("Native window active") { app.isActive && window.isKeyWindow }
            try await wait("Native controls exposed") {
                accessibilityNodes(window).contains { $0["AXIdentifier"] as? String == "native-arena-details-open" }
            }
            let rect = view.convert(view.bounds, to: nil)
            XCTAssertGreaterThan(rect.height, 200, "The native scoreboard must leave the existing game usable.")
            XCTAssertTrue(window.contentLayoutRect.insetBy(dx: -1, dy: -1).contains(rect))
            try screenshot(hosting, to: output.appendingPathComponent("arena-minimum.png"))
            let activeAX = accessibilityNodes(window)
            try writeAX(activeAX, to: output.appendingPathComponent("active-accessibility.json"))
            let identifiers = activeAX.compactMap { $0["AXIdentifier"] as? String }
            XCTAssertTrue(identifiers.contains("native-arena-team-one"))
            XCTAssertTrue(identifiers.contains("native-arena-team-two"))
            XCTAssertTrue(identifiers.contains("native-arena-details-open"))

            // Open/close actual native controls through their AppKit accessibility
            // actions. This is a control test, not a physical VoiceOver session.
            try press("native-arena-details-open", in: window)
            try await wait("Native match details opened") {
                NSApp.windows.contains { self.accessibilityNodes($0).contains { $0["AXIdentifier"] as? String == "native-arena-details" } }
            }
            XCTAssertEqual(host.projection?.arena?.round, 1)
            XCTAssertEqual(host.projection?.revision, originalRevision)
            let detailsWindow = try XCTUnwrap(NSApp.windows.first {
                accessibilityNodes($0).contains { $0["AXIdentifier"] as? String == "native-arena-details-done" }
            })
            try writeAX(accessibilityNodes(detailsWindow), to: output.appendingPathComponent("details-accessibility.json"))
            try press("native-arena-details-done", in: detailsWindow)
            try await Task.sleep(for: .milliseconds(250))

            // Command-Return uses the production button shortcut and default Pulse.
            let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            XCTAssertTrue(window.performKeyEquivalent(with: key), "The native Play shortcut should handle Command-Return.")
            try await wait("First native round resolved") { host.projection?.arena?.readback?.rounds.count == 1 }
            try await assertReadback(host, view: view)
            for _ in 0..<20 where host.projection?.arena?.phase != .finished {
                try await act("one:pulse", host: host)
                try await assertReadback(host, view: view)
                XCTAssertEqual(host.projection?.revision, originalRevision)
                XCTAssertEqual(host.projection?.eventCount, originalCount)
            }
            let complete = try XCTUnwrap(host.projection?.arena)
            XCTAssertEqual(complete.phase, .finished)
            XCTAssertEqual(complete.readback?.rounds.count, complete.round)
            XCTAssertEqual(complete.readback?.result?.retention, .unsaved)
            let keep = try XCTUnwrap(complete.actions.first { $0.id == "keep" })
            let completedID = try XCTUnwrap(complete.battleId)
            try screenshot(hosting, to: output.appendingPathComponent("result-before-keep.png"))

            // Hold the real commit lock in this disposable profile so native
            // visibility cancellation can be observed before any save happens.
            _ = try await text(view, """
                let ready; const acquired = new Promise(resolve => { ready = resolve; });
                navigator.locks.request('archi.journey.commit', async () => {
                  await new Promise(resolve => { window.__arenaStatusRelease = resolve; ready(); });
                });
                await acquired; return 'held';
                """)
            try await act("keep", host: host)
            try await wait("Keep waiting for lock") { host.projection?.arena?.readback?.result?.retention == .saving }
            host.setVisible(false)
            try await wait("Hidden Keep cancelled") {
                host.projection?.visible == false && host.projection?.arena?.readback?.result?.retention == .unsaved
            }
            XCTAssertEqual(host.projection?.eventCount, originalCount)
            XCTAssertTrue(host.projection?.arena?.readback?.result?.message.contains("cancelled") == true)
            _ = try await text(view, "window.__arenaStatusRelease(); delete window.__arenaStatusRelease; return 'released';")
            host.setVisible(true)
            try await wait("Visible after cancelled Keep") { host.projection?.visible == true }
            try await act("keep", host: host)
            try await wait("Practice kept") { host.projection?.arena?.readback?.result?.retention == .saved }
            XCTAssertEqual(host.projection?.eventCount, originalCount + 1)
            XCTAssertEqual(host.projection?.practices?.filter { $0.battleId == completedID }.count, 1)
            XCTAssertFalse(host.projection?.arena?.actions.contains { $0.id == "keep" } ?? true)
            host.performArenaAction(keep, revision: complete.revision)
            XCTAssertFalse(host.arenaCommandPending, "A stale Keep command must not save twice.")
            XCTAssertEqual(host.projection?.eventCount, originalCount + 1)
            let keptRevision = host.projection?.revision
            try screenshot(hosting, to: output.appendingPathComponent("result-kept.png"))
            try await act("leave", host: host)
            XCTAssertTrue(host.webView === view)
            XCTAssertEqual(host.sessionID, originalSession)
            XCTAssertNil(host.projection?.arena?.readback)
            XCTAssertEqual(host.projection?.revision, keptRevision)

            // An early end remains temporary and does not add another Journey event.
            try await act("start", host: host)
            try await act("one:surrender", host: host)
            XCTAssertEqual(host.projection?.arena?.readback?.result?.reason, .surrender)
            XCTAssertEqual(host.projection?.arena?.readback?.result?.retention, .unavailable)
            XCTAssertFalse(host.projection?.arena?.actions.contains { $0.id == "keep" } ?? true)
            XCTAssertEqual(host.projection?.eventCount, originalCount + 1)
            try await act("leave", host: host)

            view.reload()
            try await wait("Reloaded Journey") {
                host.sessionID != originalSession && host.projection?.readiness == .ready && host.projection?.revision == keptRevision
            }
            host.setVisible(true)
            XCTAssertEqual(host.projection?.eventCount, originalCount + 1)
            XCTAssertEqual(host.projection?.practices?.filter { $0.battleId == completedID }.count, 1)
            let receipt: [String: Any] = ["scope": "isolated acceptance profile; bundled native WKWebView", "projectionVersion": 4,
                "rounds": complete.round, "keptOnce": true, "reloadRetainedPractice": true,
                "surrenderTemporary": true, "cancelledKeepPreservedJourney": true, "nativeAXControls": true, "syntheticCommandReturn": true,
                "minimumWindow": "880x640", "embeddedGameHeight": rect.height,
                "limits": ["No physical keyboard or VoiceOver session", "No ordinary Review app replacement", "No model or external provider calls", "Reload verified; whole-app relaunch not tested here"]]
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("acceptance.json"))
            try await restore(originalStorage, view: view)
            await host.shutdown(); await store.shutdownAssistant()
        } catch {
            try? Data("\(error)\nactive=\(app.isActive), keyWindow=\(window.isKeyWindow)\n\(host.status)\n\(String(describing: host.projection))".utf8).write(to: output.appendingPathComponent("failure.txt"))
            if let view = host.webView { try? await restore(originalStorage, view: view) }
            await host.shutdown(); await store.shutdownAssistant()
            throw error
        }
    }

    @MainActor private func assertReadback(_ host: HostedPlayHost, view: WKWebView) async throws {
        let raw = try await text(view, "return JSON.stringify(JSON.parse(window.render_game_to_text()).battle);")
        let battle = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        let teams = try XCTUnwrap(battle["teams"] as? [[String: Any]])
        let readback = try XCTUnwrap(host.projection?.arena?.readback)
        for (index, team) in readback.teams.enumerated() {
            XCTAssertEqual(team.id.rawValue, teams[index]["id"] as? String)
            XCTAssertEqual(team.spark, teams[index]["spark"] as? Int)
            let roster = try XCTUnwrap(teams[index]["roster"] as? [[String: Any]])
            for (position, member) in team.roster.enumerated() {
                XCTAssertEqual(member.id, roster[position]["id"] as? String)
                XCTAssertEqual(member.integrity, roster[position]["integrity"] as? Int)
                XCTAssertEqual(member.maximumIntegrity, roster[position]["maximumIntegrity"] as? Int)
                XCTAssertEqual(member.exposed, roster[position]["exposed"] as? Bool)
                XCTAssertEqual(member.active, member.id == teams[index]["activeQiMonId"] as? String)
            }
        }
        XCTAssertEqual(readback.rounds.count, (battle["history"] as? [Any])?.count)
    }
    @MainActor private func act(_ id: String, host: HostedPlayHost) async throws {
        try await wait("Previous native command settled") { !host.arenaCommandPending }
        let arena = try XCTUnwrap(host.projection?.arena)
        let action = try XCTUnwrap(arena.actions.first { $0.id == id }, "Missing \(id): \(arena.actions.map(\.id))")
        let sequence = host.projection?.sequence
        host.performArenaAction(action, revision: arena.revision)
        try await wait("Native action \(id)") { !host.arenaCommandPending && host.projection?.sequence != sequence }
    }
    @MainActor private func wait(_ label: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(25)
        while !condition() {
            guard Date() < deadline else { throw NSError(domain: "ArenaReadback", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
            try await Task.sleep(for: .milliseconds(30))
        }
    }
    @MainActor private func text(_ view: WKWebView, _ script: String) async throws -> String {
        let result = try await view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        return try XCTUnwrap(result as? String)
    }
    @MainActor private func restore(_ storage: String?, view: WKWebView) async throws {
        guard let storage else { return }
        _ = try await view.callAsyncJavaScript("window.__arenaStatusRelease?.(); delete window.__arenaStatusRelease; const value=JSON.parse(saved); if(value===null) localStorage.removeItem('archi.journey.v3'); else localStorage.setItem('archi.journey.v3',value);",
            arguments: ["saved": storage], in: nil, contentWorld: .page)
    }
    @MainActor private func screenshot(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded(); view.window?.displayIfNeeded()
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
    @MainActor private func accessibilityObjects(_ root: NSObject) -> [NSObject] {
        var objects: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ node: NSObject, depth: Int) {
            guard depth < 25, objects.count < 1200, seen.insert(ObjectIdentifier(node)).inserted else { return }
            objects.append(node)
            let children = nativeValue(node, "accessibilityChildren") as? [NSObject]
                ?? node.accessibilityAttributeValue(.children) as? [NSObject] ?? []
            for child in children { visit(child, depth: depth + 1) }
            // A prior NSApplication test can leave a window's ignored container
            // cached without AX children. Inspect its actual AppKit content as
            // well; all labels/actions still come from native accessibility.
            if let window = node as? NSWindow, let content = window.contentView { visit(content, depth: depth + 1) }
            if let view = node as? NSView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        visit(root, depth: 0); return objects
    }
    @MainActor private func accessibilityNodes(_ root: NSObject) -> [[String: String]] {
        accessibilityObjects(root).map { node in
            var record: [String: String] = [:]
            for attr in [NSAccessibility.Attribute.role, .title, .description, .value, .identifier] {
                if let value = node.accessibilityAttributeValue(attr) as? String { record[attr.rawValue] = value }
            }
            for (key, selector) in [("AXIdentifier", "accessibilityIdentifier"), ("AXLabel", "accessibilityLabel"),
                ("AXTitle", "accessibilityTitle"), ("AXValue", "accessibilityValue")] {
                if let value = nativeValue(node, selector) as? String { record[key] = value }
            }
            return record
        }
    }
    @MainActor private func press(_ id: String, in root: NSObject) throws {
        let node = try XCTUnwrap(accessibilityObjects(root).first {
            (nativeValue($0, "accessibilityIdentifier") as? String ?? $0.accessibilityAttributeValue(.identifier) as? String) == id
        }, "Native control \(id) missing")
        if let control = node as? NSAccessibilityProtocol {
            XCTAssertTrue(control.accessibilityPerformPress())
        } else {
            // SwiftUI AX proxies may implement the native selector without
            // declaring the protocol. Call its BOOL signature, not NSObject.perform.
            let selector = NSSelectorFromString("accessibilityPerformPress")
            guard node.responds(to: selector) else {
                XCTFail("Native control \(id) does not support Press"); return
            }
            let press = unsafeBitCast(node.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
            XCTAssertTrue(press(node, selector))
        }
    }
    @MainActor private func nativeValue(_ node: NSObject, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() : nil
    }
    private func writeAX(_ nodes: [[String: String]], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: nodes, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }
}
