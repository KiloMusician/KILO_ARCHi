import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import ARCHiDesktop

final class HostedArenaCoachingWebKitTests: XCTestCase {
    /// Uses the actual packaged match, native host and separate acceptance profile.
    /// A nearby coach can offer a thought; only the player's later action plays it.
    @MainActor
    func testActualArenaCoachingIsTemporaryAndOnlyThePlayerPlaysTheMove() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let assets = env["ARCHI_HOSTED_ASSETS_DIR"], let directory = env["ARCHI_COACHING_FIXTURES_DIR"] else {
            throw XCTSkip("Set native bundled assets and ARCHI_COACHING_FIXTURES_DIR for actual coaching acceptance.")
        }
        let output = URL(fileURLWithPath: directory).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared, previous = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer { _ = app.setActivationPolicy(previous) }
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: URL(fileURLWithPath: assets))
        let store = CompanionStore(preferenceURL: output.appendingPathComponent("unused-preferences.json"))
        store.section = .play
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1080, height: 750),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ARCHi · Nearby coaching acceptance"
        let hosting = NSHostingView(rootView: WorkspaceView(store: store, playHost: host))
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil); app.activate()
        host.setVisible(true); host.start()
        defer { window.contentView = nil; window.close() }
        do {
            try await wait("Bundled Arena ready") { host.state == .ready || host.state == .unavailable }
            XCTAssertEqual(host.state, .ready, host.status)
            // The XCTest runner has no app delegate to forward activation events.
            host.setVisible(true)
            try await wait("Bundled Arena visible") { host.projection?.visible == true && host.projection?.readiness == .ready }
            let view = try XCTUnwrap(host.webView)
            let hostSession = host.sessionID
            let originalJourney = try XCTUnwrap(host.projection?.revision)
            let originalEvents = try XCTUnwrap(host.projection?.eventCount)
            let saved = try await storage(view)
            XCTAssertNil(host.beginCoaching(), "Habitat entry is not an active player turn.")

            try await act("start", host: host)
            XCTAssertEqual(host.projection?.arena?.phase, .planning)
            let baseline = try await match(view)
            let startingTeams = try await teams(view)
            let composing = try XCTUnwrap(host.beginCoaching())
            XCTAssertEqual(host.coaching.session?.id, composing)
            XCTAssertNil(host.coaching.session?.offer)
            // This is the same dispatch boundary used by ordinary native controls
            // and their keyboard shortcuts; no command may leak through the sheet.
            try await assertMoveBlocked("one:guard", host: host, view: view, baseline: baseline)
            try await assertMoveBlocked("what-if:open", host: host, view: view, baseline: baseline)
            XCTAssertNil(host.projection?.arena?.whatIf, "A rehearsal cannot open behind a coaching sheet.")
            XCTAssertTrue(host.offerCoaching(sessionID: composing, actionID: "one:guard",
                reason: "Guard absorbs impact while we keep our shared Spark."))
            XCTAssertEqual(host.coaching.session?.offer?.action.id, "one:guard")
            // Qualify the active Arena, not only Habitat entry, at the app's
            // minimum size with the additional native coaching controls present.
            window.setContentSize(NSSize(width: 880, height: 640))
            hosting.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            let webRect = view.convert(view.bounds, to: nil)
            XCTAssertGreaterThan(webRect.height, 200)
            XCTAssertTrue(window.contentLayoutRect.insetBy(dx: -1, dy: -1).contains(webRect))
            XCTAssertEqual(host.coaching.session?.id, composing)
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("arena-minimum.png"))
            }
            try await assertMoveBlocked("one:pulse", host: host, view: view, baseline: baseline)
            host.dismissCoaching(sessionID: composing)
            XCTAssertNil(host.coaching.session)
            try await assertMatch(view, baseline)
            try await assertStorage(view, saved)
            XCTAssertEqual(host.projection?.revision, originalJourney)
            XCTAssertEqual(host.projection?.eventCount, originalEvents)

            let hiddenSession = try XCTUnwrap(host.beginCoaching())
            XCTAssertTrue(host.offerCoaching(sessionID: hiddenSession, actionID: "one:guard", reason: "Keep a defensive option in mind."))
            host.setVisible(false)
            try await wait("Hidden coaching retired") { host.projection?.visible == false && host.coaching.session?.id == nil }
            XCTAssertNil(host.acceptCoaching(sessionID: hiddenSession))
            XCTAssertFalse(host.offerCoaching(sessionID: hiddenSession, actionID: "one:pulse", reason: "This offer is stale."))
            host.setVisible(true)
            try await wait("Arena visible after coaching") { host.projection?.visible == true }
            let replacementSession = try XCTUnwrap(host.beginCoaching())
            XCTAssertNotEqual(replacementSession, hiddenSession)
            XCTAssertTrue(host.offerCoaching(sessionID: replacementSession, actionID: "one:guard", reason: "This is the current suggestion."))
            // An old sheet callback cannot overwrite, accept or dismiss its successor.
            XCTAssertFalse(host.offerCoaching(sessionID: hiddenSession, actionID: "one:pulse", reason: "Late old suggestion."))
            XCTAssertNil(host.acceptCoaching(sessionID: hiddenSession))
            host.dismissCoaching(sessionID: hiddenSession)
            XCTAssertEqual(host.coaching.session?.id, replacementSession)
            XCTAssertEqual(host.coaching.session?.offer?.action.id, "one:guard")
            XCTAssertEqual(host.coaching.session?.offer?.reason, "This is the current suggestion.")
            host.dismissCoaching(sessionID: replacementSession)
            try await assertMatch(view, baseline)

            try await act("what-if:open", host: host)
            XCTAssertNotNil(host.projection?.arena?.whatIf)
            XCTAssertNil(host.beginCoaching(), "Finish a rehearsal before opening nearby coaching.")
            try await act("what-if:close", host: host)
            try await assertMatch(view, baseline)

            let acceptedSession = try XCTUnwrap(host.beginCoaching())
            XCTAssertTrue(host.offerCoaching(sessionID: acceptedSession, actionID: "one:guard", reason: "Try guarding this turn."))
            let draft = try XCTUnwrap(host.acceptCoaching(sessionID: acceptedSession))
            XCTAssertEqual(draft.id, "one:guard")
            XCTAssertNil(host.coaching.session)
            XCTAssertNil(host.acceptCoaching(sessionID: acceptedSession), "An accepted offer cannot be accepted twice.")
            XCTAssertFalse(host.arenaCommandPending)
            XCTAssertEqual(host.projection?.arena?.round, 1)
            try await assertMatch(view, baseline)
            try await assertStorage(view, saved)
            // Acceptance supplies a draft, not permission to act. The player's
            // separate ordinary command performs the existing simultaneous round.
            try await act(draft.id, host: host)
            XCTAssertEqual(host.projection?.arena?.round, 2)
            XCTAssertEqual(host.projection?.arena?.phase, .planning)
            let historyCount = try await value(view, "return String(JSON.parse(window.render_game_to_text()).battle.history.length);")
            XCTAssertEqual(historyCount, "1")
            let coachedRound = try await revealedRound(view)

            let leavingSession = try XCTUnwrap(host.beginCoaching())
            XCTAssertTrue(host.offerCoaching(sessionID: leavingSession, actionID: "one:guard", reason: "A temporary second-round thought."))
            try await act("leave", host: host)
            XCTAssertNil(host.coaching.session)
            XCTAssertNil(host.acceptCoaching(sessionID: leavingSession))
            XCTAssertFalse(host.offerCoaching(sessionID: leavingSession, actionID: "one:pulse", reason: "The encounter has ended."))
            XCTAssertEqual(host.projection?.mode, .habitat)
            XCTAssertTrue(host.webView === view)
            XCTAssertEqual(host.sessionID, hostSession)
            XCTAssertEqual(host.projection?.revision, originalJourney)
            XCTAssertEqual(host.projection?.eventCount, originalEvents)
            try await assertStorage(view, saved)

            // Compare only after the ordinary reveal: coaching must not replace
            // the partner's already-sealed move, even though public readback hides it.
            try await act("start", host: host)
            let controlTeams = try await teams(view)
            XCTAssertEqual(controlTeams, startingTeams)
            XCTAssertNil(host.coaching.session)
            try await act("one:guard", host: host)
            let controlRound = try await revealedRound(view)
            XCTAssertEqual(coachedRound, controlRound)
            try await act("leave", host: host)
            try await assertStorage(view, saved)
            XCTAssertEqual(host.projection?.revision, originalJourney)
            XCTAssertEqual(host.projection?.eventCount, originalEvents)
            XCTAssertEqual(host.sessionID, hostSession)
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("unused-preferences.json").path))
            let assertionFailures = testRun?.totalFailureCount ?? 0
            let receipt: [String: Any] = ["status": assertionFailures == 0 ? "passed" : "failed",
                "assertionFailures": assertionFailures, "session": hostSession.uuidString,
                "journeyRevision": originalJourney, "events": originalEvents,
                "checks": ["offer and dismissal preserve public match, Journey and storage",
                    "ordinary move dispatch blocked during composing and offered coaching",
                    "accept returns a draft without playing; separate player command resolves once",
                    "hiding retires coaching; old callbacks cannot replace or dismiss a new session",
                    "What if and coaching do not coexist", "leaving retires the offered suggestion",
                    "coached and untouched twins reveal identical commands and outcomes",
                    "same native host and Journey retained without saving"],
                "limits": ["Separate native acceptance profile; no owner save writes",
                    "Tests the keyboard command's native dispatch boundary, not physical key events",
                    "No model call, remote coach or camera coaching"]]
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("acceptance.json"))
            await host.shutdown(); await store.shutdownAssistant()
        } catch {
            let diagnostic = "\(error)\nHost: \(host.state), \(host.status), visible=\(host.isVisible), projection=\(String(describing: host.projection)), coaching=\(String(describing: host.coaching.session)), rejected=\(host.rejectedMessageCount)"
            try? Data(diagnostic.utf8).write(to: output.appendingPathComponent("failure.txt"))
            await host.shutdown(); await store.shutdownAssistant()
            throw error
        }
    }

    @MainActor private func assertMoveBlocked(_ id: String, host: HostedPlayHost, view: WKWebView, baseline: String) async throws {
        let arena = try XCTUnwrap(host.projection?.arena)
        let action = try XCTUnwrap(arena.actions.first { $0.id == id })
        host.performArenaAction(action, revision: arena.revision)
        XCTAssertFalse(host.arenaCommandPending)
        try await assertMatch(view, baseline)
        XCTAssertEqual(host.projection?.arena?.phase, .planning)
        XCTAssertEqual(host.projection?.arena?.round, 1)
    }
    @MainActor private func act(_ id: String, host: HostedPlayHost) async throws {
        try await wait("Arena command settled") { !host.arenaCommandPending }
        let arena = try XCTUnwrap(host.projection?.arena)
        let action = try XCTUnwrap(arena.actions.first { $0.id == id }, "Missing action \(id): \(arena.actions.map(\.id))")
        let sequence = host.projection?.sequence
        host.performArenaAction(action, revision: arena.revision)
        try await wait("Arena accepted \(id)") { !host.arenaCommandPending && host.projection?.sequence != sequence }
        XCTAssertEqual(host.arenaStatus, "")
    }
    @MainActor private func wait(_ label: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(25)
        while !condition() {
            guard Date() < deadline else { throw NSError(domain: "CoachingAcceptance", code: 1,
                userInfo: [NSLocalizedDescriptionKey: label]) }
            while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            try await Task.sleep(for: .milliseconds(30))
        }
    }
    @MainActor private func value(_ view: WKWebView, _ script: String) async throws -> String {
        let raw = try await view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        return try XCTUnwrap(raw as? String)
    }
    @MainActor private func assertMatch(_ view: WKWebView, _ expected: String) async throws {
        let actual = try await match(view)
        XCTAssertEqual(actual, expected)
    }
    @MainActor private func storage(_ view: WKWebView) async throws -> String {
        try await value(view, "return localStorage.getItem('archi.journey.v3') ?? '<absent>';")
    }
    @MainActor private func assertStorage(_ view: WKWebView, _ expected: String) async throws {
        let actual = try await storage(view)
        XCTAssertEqual(actual, expected)
    }
    @MainActor private func teams(_ view: WKWebView) async throws -> String {
        try await value(view, "return JSON.stringify(JSON.parse(window.render_game_to_text()).battle.teams);")
    }
    @MainActor private func match(_ view: WKWebView) async throws -> String {
        try await value(view, """
            const b = JSON.parse(window.render_game_to_text()).battle;
            return JSON.stringify({battleId:b.battleId,revision:b.revision,round:b.round,status:b.status,
              teams:b.teams,history:b.history,sealed:b.sealedCommands});
            """)
    }
    @MainActor private func revealedRound(_ view: WKWebView) async throws -> String {
        try await value(view, """
            const b = JSON.parse(window.render_game_to_text()).battle;
            const e = b.history[0];
            return JSON.stringify({round:e.round,commands:e.commands.map(({battleId,baseRevision,...command})=>command),
              outcomes:e.outcomes,winner:e.winner,teams:b.teams});
            """)
    }
}
