import AppKit
import ApplicationServices
import WebKit
import CryptoKit
import XCTest
@testable import ARCHiDesktop

/// Opt-in integration against the bundled production game. Ordinary SwiftPM
/// tests explicitly skip this test; they do not establish actual WebKit behavior.
final class HostedPlayWebKitTests: XCTestCase {
    @MainActor private var dispatchedAppKitEvents: [String: Int] = [:]

    @MainActor
    func testProductionBattleNativeAccessibilityDiagnostic() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let assetPath = environment["ARCHI_HOSTED_ASSETS_DIR"],
              let fixturePath = environment["ARCHI_HOSTED_FIXTURES_DIR"] else {
            throw XCTSkip("Set bundled assets and fixture paths for actual battle WebKit accessibility diagnostics.")
        }
        let originalAssets = URL(fileURLWithPath: assetPath, isDirectory: true)
        _ = try HostedPlayAssets(directory: originalAssets)
        let output = URL(fileURLWithPath: fixturePath, isDirectory: true)
            .appendingPathComponent("battle-ax-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let namedRegionProbe = environment["ARCHI_AX_COMBAT_REGION_PROBE"] == "1"
        let pointerEventsProbe = environment["ARCHI_AX_COMBAT_POINTER_PROBE"] == "1"
        let reinsertProbe = environment["ARCHI_AX_COMBAT_REINSERT_PROBE"] == "1"
        let stylesProbe = environment["ARCHI_AX_COMBAT_STYLES_PROBE"] == "1"
        guard [namedRegionProbe, pointerEventsProbe, reinsertProbe, stylesProbe].filter({ $0 }).count <= 1 else {
            throw NSError(domain: "HostedPlayWebKitTests", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Run one accessibility asset probe at a time"])
        }
        let assets: URL
        if namedRegionProbe || pointerEventsProbe {
            assets = output.appendingPathComponent("candidate-assets", isDirectory: true)
            try FileManager.default.copyItem(at: originalAssets, to: assets)
            let target: URL
            let original: String
            let before: String
            let after: String
            if namedRegionProbe {
                target = assets.appendingPathComponent("index.html")
                original = try String(contentsOf: target, encoding: .utf8)
                before = "<div class=\"battle-combat\" id=\"battle-combat\" hidden>"
                after = "<div class=\"battle-combat\" id=\"battle-combat\" role=\"region\" aria-label=\"Battle commands and status\" hidden>"
            } else {
                let styles = try FileManager.default.contentsOfDirectory(at: assets.appendingPathComponent("assets"), includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "css" }
                guard styles.count == 1, let stylesheet = styles.first else {
                    throw NSError(domain: "HostedPlayWebKitTests", code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Expected one bundled stylesheet for the isolated pointer-events probe"])
                }
                target = stylesheet
                original = try String(contentsOf: target, encoding: .utf8)
                let pattern = try NSRegularExpression(pattern: #"\.battle-combat\{[^}]*pointer-events:none[^}]*\}"#)
                guard let match = pattern.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)),
                      let range = Range(match.range, in: original) else {
                    throw NSError(domain: "HostedPlayWebKitTests", code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Missing exact combat pointer-events rule"])
                }
                before = String(original[range])
                after = before.replacingOccurrences(of: "pointer-events:none", with: "pointer-events:auto")
            }
            guard original.components(separatedBy: before).count == 2 else {
                throw NSError(domain: "HostedPlayWebKitTests", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "The candidate must change exactly one known rule or opening tag"])
            }
            let candidate = original.replacingOccurrences(of: before, with: after)
            try Data(candidate.utf8).write(to: target)
            let probe: [String: Any] = ["schema": "archi-test-only-ax-asset-probe/v1", "before": before, "after": after,
                "variant": namedRegionProbe ? "named-combat-region" : "combat-pointer-events-auto", "file": target.lastPathComponent,
                "sourceAssets": originalAssets.path, "originalSHA256": SHA256.hash(data: Data(original.utf8)).map { String(format: "%02x", $0) }.joined(),
                "candidateSHA256": SHA256.hash(data: Data(candidate.utf8)).map { String(format: "%02x", $0) }.joined(),
                "scope": "Cold-load test asset copy only; runtime visibility, game state, and production files unchanged."]
            try JSONSerialization.data(withJSONObject: probe, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("probe-input.json"))
        } else { assets = originalAssets }
        let application = NSApplication.shared
        let oldPolicy = application.activationPolicy()
        guard application.setActivationPolicy(.regular) else {
            throw NSError(domain: "HostedPlayWebKitTests", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not enable native test-window activation"])
        }
        defer { _ = application.setActivationPolicy(oldPolicy) }
        application.finishLaunching()
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 960, height: 720),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi · Isolated Battle Accessibility Diagnostic"
        window.isReleasedWhenClosed = false
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: assets)
        var stage = "start-native-host"
        var documentProbe: [String: Any] = [:]
        do {
            host.setVisible(true); host.start()
            try await wait("Native diagnostic view") { host.webView != nil || host.state == .unavailable }
            let view = try XCTUnwrap(host.webView, host.status)
            attach(view, to: window)
            // Exercise the same public activation request used by the app.
            // Visibility is still independently required and never overridden.
            application.activate(ignoringOtherApps: true)
            dispatchPendingAppKitEvents()
            window.orderFrontRegardless()
            dispatchPendingAppKitEvents()
            window.makeFirstResponder(view)
            try await wait("Production diagnostic readiness") { host.state == .ready || host.state == .unavailable }
            XCTAssertEqual(host.state, .ready, host.status)
            try await recordBattleAccessibility(view, name: "01-initial", output: output)
            stage = "require-real-document-visibility"
            try await waitForVisibleDocument(view) { documentProbe = $0 }
            let savedBefore = try await js(view, "return localStorage.getItem('archi.journey.v3');") as? String
            stage = "open-production-arena-setup"
            _ = try await js(view, "document.getElementById('battle-button').click(); return true;")
            try await waitJS(view, "return !document.getElementById('battle-panel').hidden && !document.getElementById('battle-setup').hidden;", label: "Arena setup opened")
            try await recordBattleAccessibility(view, name: "02-setup", output: output)
            stage = "open-production-battle-field"
            _ = try await js(view, "document.getElementById('battle-start').click(); return true;")
            try await waitJS(view, "return !document.getElementById('battle-combat').hidden;", label: "Battle combat opened")
            try await Task.sleep(for: .milliseconds(300))
            try await recordBattleAccessibility(view, name: "03-combat", output: output)
            stage = "inspect-production-focused-command"
            // startBattle already focuses this native HTML select. Inspect that
            // focus rather than fabricating an accessibility element or action.
            try await waitJS(view, "return document.activeElement?.id === 'battle-one-action';", label: "Production command focus")
            try await recordBattleAccessibility(view, name: "04-focused-command", output: output)
            if reinsertProbe {
                stage = "reinsert-same-visible-combat-node"
                let receipt = try await js(view, """
                    const node = document.getElementById('battle-combat');
                    if (!node || node.hidden || node.closest('[inert]')) throw new Error('Combat must already be visibly active');
                    const parent = node.parentNode, next = node.nextSibling, markup = node.outerHTML;
                    const command = document.getElementById('battle-one-action');
                    node.remove();
                    try {
                      await new Promise((resolve, reject) => {
                        const timeout = setTimeout(() => reject(new Error('Rendering interval timed out')), 1500);
                        requestAnimationFrame(() => requestAnimationFrame(() => { clearTimeout(timeout); resolve(); }));
                      });
                    } finally { parent.insertBefore(node, next); }
                    command.focus({preventScroll: true});
                    return {sameCombatNode: node === document.getElementById('battle-combat'),
                      sameCommandNode: command === document.getElementById('battle-one-action'),
                      sameMarkup: markup === node.outerHTML, sameParent: node.parentNode === parent,
                      sameSiblingPosition: node.nextSibling === next, hidden: node.hidden, connected: node.isConnected};
                    """)
                let identity = try XCTUnwrap(receipt as? [String: Any])
                for key in ["sameCombatNode", "sameCommandNode", "sameMarkup", "sameParent", "sameSiblingPosition", "connected"] {
                    XCTAssertEqual(identity[key] as? Bool, true, key)
                }
                XCTAssertEqual(identity["hidden"] as? Bool, false)
                try JSONSerialization.data(withJSONObject: identity, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("same-node-reinsertion.json"))
                try await Task.sleep(for: .milliseconds(300))
                try await recordBattleAccessibility(view, name: "05-reinserted-combat", output: output)
            }
            if stylesProbe {
                stage = "disable-stylesheets-only"
                let disabled = try await js(view, """
                    const combat = document.getElementById('battle-combat'), command = document.getElementById('battle-one-action');
                    const sheets = Array.from(document.styleSheets).map(sheet => ({sheet, disabled: sheet.disabled}));
                    if (!sheets.length || combat.hidden) throw new Error('An active styled combat page is required');
                    window.__archiTestStyleProbe = {sheets, combat, command, markup: combat.outerHTML, x: scrollX, y: scrollY};
                    for (const entry of sheets) entry.sheet.disabled = true;
                    return {stylesheetCount: sheets.length, changedOnlyStylesheetDisabled: true};
                    """)
                try await Task.sleep(for: .milliseconds(300))
                try await recordBattleAccessibility(view, name: "05-styles-disabled", output: output)
                let targetInView = try await js(view, """
                    const command = document.getElementById('battle-one-action');
                    command.scrollIntoView({block: 'center', inline: 'nearest'});
                    const rect = command.getBoundingClientRect();
                    return rect.top >= 0 && rect.bottom <= innerHeight && rect.left >= 0 && rect.right <= innerWidth;
                    """)
                XCTAssertEqual(targetInView as? Bool, true, "Keep the unstyled control in the viewport for the AX comparison")
                try await Task.sleep(for: .milliseconds(300))
                try await recordBattleAccessibility(view, name: "05b-styles-disabled-command-in-view", output: output)
                stage = "restore-same-stylesheets"
                let restored = try await restoreStyleProbe(view)
                let restoration = try XCTUnwrap(restored as? [String: Any])
                for key in ["present", "restoredDisabledStates", "sameCombatNode", "sameCommandNode", "sameMarkup"] {
                    XCTAssertEqual(restoration[key] as? Bool, true, key)
                }
                try await Task.sleep(for: .milliseconds(300))
                try await recordBattleAccessibility(view, name: "06-styles-restored", output: output)
                let unstyledCommands = try nativeBattleCommandLabels(output.appendingPathComponent("05b-styles-disabled-command-in-view.json"))
                var styleReceipt: [String: Any] = ["disabled": disabled ?? NSNull(), "restored": restored ?? NSNull(),
                    "unstyledTargetInViewport": targetInView ?? NSNull(),
                    "unstyledCommandLabels": unstyledCommands,
                    "restoredCommandLabels": try nativeBattleCommandLabels(output.appendingPathComponent("06-styles-restored.json"))]
                if !unstyledCommands.isEmpty {
                    // A new production document avoids carrying a broad CSS
                    // invalidation into the targeted grid-only comparison.
                    stage = "reload-before-grid-only-comparison"
                    let previousValue = try await js(view, "return window.__ARCHI_DESKTOP_BOOTSTRAP__.sessionId;")
                    let previous = try XCTUnwrap(previousValue as? String)
                    _ = try XCTUnwrap(UUID(uuidString: previous))
                    view.reload()
                    try await waitJS(view, "return window.__ARCHI_DESKTOP_BOOTSTRAP__?.sessionId !== '\(previous)' && document.readyState === 'complete';", label: "Fresh production document for grid comparison")
                    try await wait("Reloaded production readiness") { host.state == .ready && host.projection?.mode == .habitat }
                    try await waitForVisibleDocument(view) { documentProbe = $0 }
                    _ = try await js(view, "document.getElementById('battle-button').click(); document.getElementById('battle-start').click(); return true;")
                    try await waitJS(view, "return !document.getElementById('battle-combat').hidden;", label: "Fresh production combat")
                    try await recordBattleAccessibility(view, name: "07-grid-fresh-baseline", output: output)
                    stage = "override-only-combat-grid-display"
                    _ = try await js(view, """
                        const combat = document.getElementById('battle-combat');
                        window.__archiTestGridProbe = {combat, style: combat.getAttribute('style')};
                        combat.style.setProperty('display', 'block'); return true;
                        """)
                    try await Task.sleep(for: .milliseconds(300))
                    try await recordBattleAccessibility(view, name: "08-combat-display-block", output: output)
                    styleReceipt["gridOnlyCommandLabels"] = try nativeBattleCommandLabels(output.appendingPathComponent("08-combat-display-block.json"))
                    _ = try await restoreGridProbe(view)
                    try await Task.sleep(for: .milliseconds(300))
                    try await recordBattleAccessibility(view, name: "09-combat-grid-restored", output: output)
                    styleReceipt["gridRestoredCommandLabels"] = try nativeBattleCommandLabels(output.appendingPathComponent("09-combat-grid-restored.json"))
                }
                try JSONSerialization.data(withJSONObject: styleReceipt, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("stylesheet-bisection.json"))
            }
            let savedAfter = try await js(view, "return localStorage.getItem('archi.journey.v3');") as? String
            XCTAssertEqual(savedAfter, savedBefore, "Arena setup and command inspection cannot mutate Journey")
            let report: [String: Any] = ["schema": "archi-native-battle-ax-diagnostic/v1",
                "profile": "acceptance", "productionDOM": !namedRegionProbe,
                "assetVariant": namedRegionProbe ? "test-only-named-combat-region" : pointerEventsProbe ? "test-only-combat-pointer-events-auto" : "production",
                "structuralProbe": reinsertProbe ? "detach-and-reinsert-same-visible-node" : "none",
                "stylesheetProbe": stylesProbe,
                "foregroundStrategy": "own-app-activation-event-dispatch-and-orderFrontRegardless",
                "realDocumentVisibility": true,
                "journeyBytesUnchanged": savedBefore == savedAfter,
                "nativeWindow": nativeWindowEvidence(application, window: window, view: view),
                "limits": ["Direct in-process NSAccessibility traversal; compare separately with CUA and assistive-technology behavior.",
                    "This diagnostic does not declare an empty or unsupported native subtree accessible."]]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("report.json"))
            print("Battle accessibility diagnostic artifacts: \(output.path)")
            await host.shutdown()
            window.contentView = nil; window.close()
        } catch {
            if let view = host.webView {
                _ = try? await restoreStyleProbe(view)
                _ = try? await restoreGridProbe(view)
                try? await recordBattleAccessibility(view, name: "failure-state", output: output)
            }
            let failure: [String: Any] = ["schema": "archi-native-battle-ax-diagnostic-failure/v1", "stage": stage,
                "error": String(describing: error), "document": documentProbe,
                "foregroundStrategy": "own-app-activation-event-dispatch-and-orderFrontRegardless",
                "nativeWindow": nativeWindowEvidence(application, window: window, view: host.webView),
                "hostState": host.state.rawValue, "note": "No environment cause or accessibility success is inferred."]
            try? JSONSerialization.data(withJSONObject: failure, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("failure.json"))
            print("Battle accessibility diagnostic failed at \(stage); artifacts: \(output.path)")
            await host.shutdown()
            window.contentView = nil; window.close()
            throw error
        }
    }

    @MainActor
    func testProductionWebKitLocksVisibilityAndPersistentJourneyAcrossHostRecreation() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let assetPath = environment["ARCHI_HOSTED_ASSETS_DIR"], !assetPath.isEmpty,
              let fixturePath = environment["ARCHI_HOSTED_FIXTURES_DIR"], !fixturePath.isEmpty else {
            throw XCTSkip("Set ARCHI_HOSTED_ASSETS_DIR and ARCHI_HOSTED_FIXTURES_DIR to run actual bundled-game WebKit acceptance.")
        }
        let assets = URL(fileURLWithPath: assetPath, isDirectory: true)
        _ = try HostedPlayAssets(directory: assets)
        let output = URL(fileURLWithPath: fixturePath, isDirectory: true).appendingPathComponent("webkit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // SwiftPM's unbundled test executable does not have the production
        // app's activation policy or launch lifecycle. AppKit defaults such
        // executables to .prohibited, so ordering a window alone is inadequate.
        let application = NSApplication.shared
        let originalActivationPolicy = application.activationPolicy()
        guard application.setActivationPolicy(.accessory) else {
            throw NSError(domain: "HostedPlayWebKitTests", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not enable a native test-window activation policy"])
        }
        defer { _ = application.setActivationPolicy(originalActivationPolicy) }
        application.finishLaunching()
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: assets)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 960, height: 720),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi · Isolated WebKit Acceptance"
        window.isReleasedWhenClosed = false
        var other: WKWebView?
        var reopened: HostedPlayHost?
        var stage = "start-native-host"
        var documentProbe: [String: Any] = ["status": "not-yet-inspected"]
        do {
            host.setVisible(true); host.start()
            try await wait("First native web view") { host.webView != nil || host.state == .unavailable }
            let view = try XCTUnwrap(host.webView, host.status)
            attach(view, to: window)
            application.activate()
            stage = "wait-production-game-ready"
            try await wait("Actual production game readiness") { host.state == .ready || host.state == .unavailable }
            XCTAssertEqual(host.state, .ready, host.status)
            XCTAssertEqual(host.projection?.storage, .localBrowser)
            stage = "check-document-visibility"
            try await waitForVisibleDocument(view) { documentProbe = $0 }
            stage = "read-secure-context-and-lock-capabilities"
            let capabilities = try await js(view, "return {secure: window.isSecureContext, locks: typeof navigator.locks?.request === 'function', qa: new URL(location.href).searchParams.has('qa'), origin: location.origin};")
            let flags = try XCTUnwrap(capabilities as? [String: Any])
            XCTAssertEqual(flags["secure"] as? Bool, true)
            XCTAssertEqual(flags["locks"] as? Bool, true)
            XCTAssertEqual(flags["qa"] as? Bool, false)
            XCTAssertEqual(flags["origin"] as? String, "http://127.0.0.1:43823")
            let baseline = try XCTUnwrap(host.projection?.eventCount)
            stage = "commit-production-care-control"
            _ = try await js(view, "document.getElementById('care-greet').click(); return true;")
            try await wait("A real production care event is published") { host.projection?.eventCount == baseline + 1 }
            let savedValue = try await js(view, "return localStorage.getItem('archi.journey.v3');")
            let saved = try XCTUnwrap(savedValue as? String)

            // A second actual WebKit page in the same persistent data store and
            // exact origin contends for the production Journey commit lock.
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: HostedPlayProfile.acceptance.dataStoreIdentifier)
            let sink = HostedPlayAcceptanceSink()
            configuration.userContentController.add(sink, name: "archiJourneyProjection")
            let bootstrap = "window.__ARCHI_DESKTOP_BOOTSTRAP__ = {version:1,host:'archi-desktop',sessionId:'\(UUID().uuidString)',visible:false};"
            configuration.userContentController.addUserScript(WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            let second = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
            other = second
            view.addSubview(second)
            second.load(URLRequest(url: HostedPlayProfile.acceptance.origin))
            stage = "wait-second-webkit-page-ready"
            try await wait("Second actual WebKit page readiness") { sink.ready }
            stage = "hold-real-cross-page-lock"
            _ = try await js(second, "window.__acceptanceLockHeld = false; window.__acceptanceRelease = null; navigator.locks.request('archi.journey.commit', async () => { window.__acceptanceLockHeld = true; await new Promise(resolve => { window.__acceptanceRelease = resolve; }); window.__acceptanceLockHeld = false; }); return true;")
            try await waitJS(second, "return window.__acceptanceLockHeld === true;", label: "Second WebKit page holds real lock")
            stage = "queue-production-care-behind-lock"
            _ = try await js(view, "document.getElementById('care-greet').click(); return true;")
            try await waitJS(view, "return (await navigator.locks.query()).pending.some(lock => lock.name === 'archi.journey.commit');", label: "Care queued behind another actual WebKit page")
            stage = "hide-show-queued-care"
            host.setVisible(false)
            try await wait("Native hide reached the production bridge") { host.projection?.visible == false }
            host.setVisible(true)
            try await wait("Native show reached the production bridge") { host.projection?.visible == true }
            stage = "release-lock-and-verify-cancelled-care"
            _ = try await js(second, "window.__acceptanceRelease(); return true;")
            try await waitJS(second, "return window.__acceptanceLockHeld === false;", label: "The real lock is released")
            try await Task.sleep(for: .milliseconds(400))
            let afterCancelledValue = try await js(view, "return localStorage.getItem('archi.journey.v3');")
            let afterCancelled = try XCTUnwrap(afterCancelledValue as? String)
            XCTAssertEqual(afterCancelled, saved, "Hide permanently cancels the queued care intent even after resume and lock release")
            XCTAssertEqual(host.projection?.eventCount, baseline + 1)
            try Data(saved.utf8).write(to: output.appendingPathComponent("before-host-reopen.json"))
            second.stopLoading(); second.removeFromSuperview()
            second.configuration.userContentController.removeScriptMessageHandler(forName: "archiJourneyProjection")
            other = nil
            window.contentView = nil
            stage = "shutdown-first-native-host"
            await host.shutdown()
            XCTAssertEqual(host.state, .stopped)
            let replacement = HostedPlayHost(profile: .acceptance, assetDirectory: assets)
            reopened = replacement
            stage = "recreate-native-host"
            replacement.setVisible(true); replacement.start()
            try await wait("Recreated native host web view") { replacement.webView != nil || replacement.state == .unavailable }
            let newView = try XCTUnwrap(replacement.webView, replacement.status)
            attach(newView, to: window)
            application.activate()
            try await wait("Persistent Journey readiness after host recreation") { replacement.state == .ready || replacement.state == .unavailable }
            XCTAssertEqual(replacement.state, .ready, replacement.status)
            XCTAssertEqual(replacement.projection?.storage, .localBrowser)
            XCTAssertEqual(replacement.projection?.eventCount, baseline + 1)
            stage = "check-recreated-document-visibility"
            try await waitForVisibleDocument(newView) { documentProbe = $0 }
            stage = "compare-persisted-bytes-after-recreation"
            let reopenedValue = try await js(newView, "return localStorage.getItem('archi.journey.v3');")
            let reopenedBytes = try XCTUnwrap(reopenedValue as? String)
            XCTAssertEqual(reopenedBytes, saved)
            try Data(reopenedBytes.utf8).write(to: output.appendingPathComponent("after-host-reopen.json"))
            let report: [String: Any] = ["schema": "archi-hosted-webkit-acceptance/v1", "mode": "actual-wkwebview-production-game",
                "profile": "acceptance", "origin": "http://127.0.0.1:43823", "qaMode": false,
                "secureContext": true, "realCrossWebViewLock": true, "hiddenQueuedCareCancelled": afterCancelled == saved,
                "sameSavedBytesAfterHostRecreation": reopenedBytes == saved,
                "testWindowLifecycle": nativeWindowEvidence(application, window: window, view: newView),
                "document": documentProbe,
                "journeyBytes": saved.utf8.count, "sha256": SHA256.hash(data: Data(saved.utf8)).map { String(format: "%02x", $0) }.joined(),
                "limits": ["Host recreation within this test process; actual app relaunch is separate acceptance.", "Native file panels and battle interactions are separate UI acceptance."]]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("report.json"))
            print("Actual WebKit acceptance artifacts: \(output.path)")
            await replacement.shutdown()
            window.contentView = nil; window.close()
        } catch {
            let failure: [String: Any] = ["schema": "archi-hosted-webkit-failure/v1", "stage": stage,
                "error": String(describing: error), "hostState": host.state.rawValue, "hostStatus": host.status,
                "projectionReady": host.projection?.readiness.rawValue ?? "none",
                "storage": host.projection?.storage.rawValue ?? "none", "nativeVisible": host.isVisible,
                "windowVisible": window.isVisible,
                "testWindowLifecycle": nativeWindowEvidence(application, window: window, view: reopened?.webView ?? host.webView),
                "document": documentProbe,
                "note": "This records runtime evidence only; it does not infer a Mac-lock cause."]
            try? JSONSerialization.data(withJSONObject: failure, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("failure.json"))
            print("WebKit acceptance failed at \(stage); artifacts: \(output.path)")
            if let other {
                _ = try? await js(other, "if (window.__acceptanceRelease) window.__acceptanceRelease(); return true;")
                other.stopLoading(); other.removeFromSuperview()
            }
            await reopened?.shutdown(); await host.shutdown()
            window.contentView = nil; window.close()
            throw error
        }
    }

    @MainActor
    private func attach(_ view: WKWebView, to window: NSWindow) {
        let content = NSView(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size))
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        view.frame = content.bounds
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
        content.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
    }

    @MainActor
    private func restoreStyleProbe(_ view: WKWebView) async throws -> Any? {
        try await js(view, """
            const probe = window.__archiTestStyleProbe; if (!probe) return {present: false};
            for (const entry of probe.sheets) entry.sheet.disabled = entry.disabled;
            scrollTo(probe.x, probe.y); probe.command.focus({preventScroll: true});
            const result = {present: true, stylesheetCount: probe.sheets.length,
              restoredDisabledStates: probe.sheets.every(entry => entry.sheet.disabled === entry.disabled),
              sameCombatNode: probe.combat === document.getElementById('battle-combat'),
              sameCommandNode: probe.command === document.getElementById('battle-one-action'),
              sameMarkup: probe.markup === probe.combat.outerHTML};
            delete window.__archiTestStyleProbe; return result;
            """)
    }

    @MainActor
    private func restoreGridProbe(_ view: WKWebView) async throws -> Any? {
        try await js(view, """
            const probe = window.__archiTestGridProbe; if (!probe) return {present: false};
            if (probe.style === null) probe.combat.removeAttribute('style'); else probe.combat.setAttribute('style', probe.style);
            const result = {present: true, restoredOriginalStyle: probe.combat.getAttribute('style') === probe.style};
            delete window.__archiTestGridProbe; return result;
            """)
    }

    @MainActor
    private func nativeBattleCommandLabels(_ file: URL) throws -> [String] {
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let tree = try XCTUnwrap(value?["publicAX"] as? [String: Any])
        let nodes = try XCTUnwrap(tree["nodes"] as? [[String: Any]])
        return nodes.compactMap { node in
            guard ["AXButton", "AXPopUpButton"].contains(node["AXRole"] as? String ?? "") else { return nil }
            let labels = [node["AXTitle"] as? String, node["AXDescription"] as? String].compactMap { $0 }
            return labels.first { $0.localizedCaseInsensitiveContains("command") || $0.localizedCaseInsensitiveContains("resolve") }
        }
    }

    @MainActor
    private func recordBattleAccessibility(_ view: WKWebView, name: String, output: URL) async throws {
        let dom = try await js(view, """
            const ids = ['app', 'battle-panel', 'battle-setup', 'battle-start', 'battle-combat', 'battle-command-dock', 'battle-one-action', 'battle-one-lock', 'battle-two-action', 'battle-two-lock', 'battle-resolve'];
            const describe = node => {
              const style = getComputedStyle(node), rect = node.getBoundingClientRect();
              return {id: node.id, tag: node.tagName, hidden: node.hidden === true, inert: node.inert === true,
                ariaHidden: node.getAttribute('aria-hidden'), role: node.getAttribute('role'),
                display: style.display, visibility: style.visibility, pointerEvents: style.pointerEvents,
                rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height}};
            };
            return {visibility: document.visibilityState, activeElement: document.activeElement?.id ?? null,
              controls: ids.map(id => { const node = document.getElementById(id); if (!node) return {id, missing: true};
                const ancestors = []; let parent = node.parentElement;
                while (parent && ancestors.length < 12) { ancestors.push(describe(parent)); parent = parent.parentElement; }
                return {...describe(node), disabled: node.disabled === true, ancestors}; })};
            """)
        let native = nativeAccessibilitySnapshot(view)
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        let remoteBytes = await Task.detached { @Sendable () -> Data in
            HostedPlayWebKitTests.ownProcessAccessibilitySnapshot(processID: ownProcessID)
        }.value
        dispatchPendingAppKitEvents()
        let publicAX = (try? JSONSerialization.jsonObject(with: remoteBytes)) ?? NSNull()
        let record: [String: Any] = ["schema": "archi-native-battle-ax-snapshot/v1", "stage": name,
            "dom": dom ?? NSNull(), "native": native, "publicAX": publicAX]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent(name + ".json"))
    }

    /// Query only this test application's public AX tree. AXUIElement follows
    /// WebKit's remote accessibility boundary; NSObject traversal cannot.
    /// No system-wide element, trust prompt, or other application lookup occurs.
    nonisolated private static func ownProcessAccessibilitySnapshot(processID: Int32) -> Data {
        let root = AXUIElementCreateApplication(processID)
        let deadline = Date().addingTimeInterval(4)
        var nodes: [[String: Any]] = []
        var seen: [CFHashCode: [AXUIElement]] = [:]
        var duplicateCount = 0
        var hashCollisionCount = 0
        var errors: [String: Int] = [:]
        func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(node, name as CFString, &value)
            if error != .success { errors[name + ":" + String(error.rawValue), default: 0] += 1 }
            return value
        }
        func visit(_ node: AXUIElement, parent: Int?, depth: Int) {
            guard depth <= 20, nodes.count < 1000, Date() < deadline else { return }
            let hash = CFHash(node)
            let bucket = seen[hash] ?? []
            if bucket.contains(where: { CFEqual($0, node) }) { duplicateCount += 1; return }
            if !bucket.isEmpty { hashCollisionCount += 1 }
            seen[hash, default: []].append(node)
            _ = AXUIElementSetMessagingTimeout(node, 0.2)
            let index = nodes.count
            var record: [String: Any] = ["index": index, "parent": parent.map { $0 as Any } ?? NSNull()]
            for key in [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXFocusedAttribute, "AXIdentifier"] {
                if let value = attribute(node, key) {
                    if let text = value as? String { record[key] = String(text.prefix(256)) }
                    else if let number = value as? NSNumber { record[key] = number }
                }
            }
            let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
            record["childCount"] = children.count
            nodes.append(record)
            for child in children { visit(child, parent: index, depth: depth + 1) }
        }
        visit(root, parent: nil, depth: 0)
        let result: [String: Any] = ["source": "AXUIElementCreateApplication for this test process only", "processID": processID,
            "trustedWithoutPrompt": AXIsProcessTrusted(), "nodes": nodes, "nodeCount": nodes.count,
            "errors": errors, "equalDuplicatesSkipped": duplicateCount, "unequalHashCollisionsRetained": hashCollisionCount,
            "budgetReached": Date() >= deadline || nodes.count >= 1000]
        return (try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    @MainActor
    private func nativeAccessibilitySnapshot(_ view: WKWebView) -> [String: Any] {
        var records: [[String: Any]] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: Any, parent: Int?, depth: Int) {
            guard depth <= 20, records.count < 1200, let node = object as? NSObject else { return }
            guard seen.insert(ObjectIdentifier(node)).inserted else { return }
            let index = records.count
            var record: [String: Any] = ["index": index, "parent": parent.map { $0 as Any } ?? NSNull(),
                "class": String(describing: type(of: node))]
            // WK remote accessibility objects can expose the legacy NSObject
            // interface without declaring the full modern NSAccessibility
            // protocol. Use their advertised attributes rather than omitting
            // that subtree or inventing DOM-derived accessibility nodes.
            let attributes = node.accessibilityAttributeNames()
            for attribute in [NSAccessibility.Attribute.role, .subrole, .title, .description, .value, .identifier, .focused] {
                guard attributes.contains(attribute) else { continue }
                let value = node.accessibilityAttributeValue(attribute)
                if let text = value as? String { record[attribute.rawValue] = String(text.prefix(256)) }
                else if let number = value as? NSNumber { record[attribute.rawValue] = number }
            }
            let children = attributes.contains(.children) ? node.accessibilityAttributeValue(.children) as? [Any] ?? [] : []
            record["advertisedAttributes"] = attributes.map(\.rawValue)
            record["childCount"] = children.count
            records.append(record)
            for child in children { visit(child, parent: index, depth: depth + 1) }
        }
        visit(view, parent: nil, depth: 0)
        return ["source": "WKWebView native NSAccessibility attributes", "nodes": records,
            "nodeCount": records.count, "nodeLimitReached": records.count >= 1200]
    }

    @MainActor
    private func nativeWindowEvidence(_ application: NSApplication, window: NSWindow, view: WKWebView?) -> [String: Any] {
        ["activationPolicy": application.activationPolicy().rawValue,
         "appActive": application.isActive, "appHidden": application.isHidden,
         "appRunning": application.isRunning, "dispatchedAppKitEventsByType": dispatchedAppKitEvents,
         "appOcclusionVisible": application.occlusionState.contains(.visible),
         "windowVisible": window.isVisible, "windowKey": window.isKeyWindow,
         "windowOcclusionVisible": window.occlusionState.contains(.visible),
         "windowFrame": NSStringFromRect(window.frame),
         "viewFrame": view.map { NSStringFromRect($0.frame) } ?? "none",
         "viewBounds": view.map { NSStringFromRect($0.bounds) } ?? "none",
         "viewAttachedToTestWindow": view?.window === window,
         "viewHidden": view?.isHiddenOrHasHiddenAncestor ?? true]
    }

    @MainActor
    private func waitForVisibleDocument(_ view: WKWebView, inspect: ([String: Any]) -> Void) async throws {
        let deadline = Date().addingTimeInterval(10)
        while true {
            let value = try await js(view, "return {visibilityState: document.visibilityState, hidden: document.hidden, hasFocus: document.hasFocus(), width: innerWidth, height: innerHeight, readyState: document.readyState};")
            let probe = try XCTUnwrap(value as? [String: Any])
            inspect(probe)
            if probe["visibilityState"] as? String == "visible",
               (probe["width"] as? NSNumber)?.doubleValue ?? 0 > 0,
               (probe["height"] as? NSNumber)?.doubleValue ?? 0 > 0 { return }
            guard Date() < deadline else {
                throw NSError(domain: "HostedPlayWebKitTests", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Visible WebKit document with a nonempty viewport timed out"])
            }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    @MainActor
    private func js(_ view: WKWebView, _ body: String) async throws -> Any? {
        dispatchPendingAppKitEvents()
        let value = try await view.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page)
        dispatchPendingAppKitEvents()
        return value
    }
    @MainActor
    private func wait(_ label: String, condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(25)
        while true {
            dispatchPendingAppKitEvents()
            if condition() { return }
            guard Date() < deadline else { throw NSError(domain: "HostedPlayWebKitTests", code: 1, userInfo: [NSLocalizedDescriptionKey: label + " timed out"]) }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    @MainActor
    private func dispatchPendingAppKitEvents() {
        // XCTest drives async tasks, but does not run NSApplication.run().
        // Dispatch only events already queued for this test application's own
        // windows, including AppKit activation/occlusion notifications. This
        // neither synthesizes input nor overrides WebKit's visibility state.
        let application = NSApplication.shared
        for _ in 0..<100 {
            guard let event = application.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) else { break }
            dispatchedAppKitEvents[String(event.type.rawValue), default: 0] += 1
            application.sendEvent(event)
        }
        application.updateWindows()
    }
    @MainActor
    private func waitJS(_ view: WKWebView, _ body: String, label: String) async throws {
        let deadline = Date().addingTimeInterval(10)
        while try await js(view, body) as? Bool != true {
            guard Date() < deadline else { throw NSError(domain: "HostedPlayWebKitTests", code: 2, userInfo: [NSLocalizedDescriptionKey: label + " timed out"]) }
            try await Task.sleep(for: .milliseconds(30))
        }
    }
}

@MainActor
private final class HostedPlayAcceptanceSink: NSObject, WKScriptMessageHandler {
    private(set) var ready = false
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any], body["readiness"] as? String == "ready" { ready = true }
    }
}
