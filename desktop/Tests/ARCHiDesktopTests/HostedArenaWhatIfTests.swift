import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import ARCHiDesktop

final class HostedArenaWhatIfTests: XCTestCase {
    /// Runs the actual bundled match and its native intent port in the separate
    /// acceptance profile. Rehearsals must leave saved and live game state intact.
    @MainActor
    func testActualArenaRehearsalPreservesMatchAndRetiresWithItsContext() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let assets = env["ARCHI_HOSTED_ASSETS_DIR"], let directory = env["ARCHI_WHAT_IF_FIXTURES_DIR"] else {
            throw XCTSkip("Set native bundled assets and ARCHI_WHAT_IF_FIXTURES_DIR for actual Arena acceptance.")
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
        window.title = "ARCHi · What if acceptance"
        let hosting = NSHostingView(rootView: WorkspaceView(store: store, playHost: host))
        window.contentView = hosting; window.makeKeyAndOrderFront(nil); app.activate()
        host.setVisible(true); host.start()
        defer { window.contentView = nil; window.close() }
        do {
            try await wait("Bundled Arena ready") { host.state == .ready || host.state == .unavailable }
            XCTAssertEqual(host.state, .ready, host.status)
            // The test runner has no app delegate to forward activation events.
            // Set visibility after the actual SwiftUI onAppear has mounted it.
            host.setVisible(true)
            try await wait("Bundled Arena visible") { host.projection?.visible == true && host.projection?.readiness == .ready }
            let view = try XCTUnwrap(host.webView)
            let session = host.sessionID
            let originalJourney = host.projection?.revision
            let originalEvents = host.projection?.eventCount
            let saved = try await value(view, "return localStorage.getItem('archi.journey.v3') ?? '<absent>';")
            try await act("start", host: host)
            XCTAssertEqual(host.projection?.version, 4)
            XCTAssertEqual(host.projection?.arena?.phase, .planning)
            let baseline = try await match(view)
            let startingTeams = try await value(view, "return JSON.stringify(JSON.parse(window.render_game_to_text()).battle.teams);")
            let oldArena = try XCTUnwrap(host.projection?.arena)
            let oldMove = try XCTUnwrap(oldArena.actions.first { $0.id == "one:pulse" })
            let open = try XCTUnwrap(oldArena.actions.first { $0.id == "what-if:open" })
            try await act(open.id, host: host)
            let report = try XCTUnwrap(host.projection?.arena?.whatIf)
            let originalPresentation = try XCTUnwrap(host.whatIfPresentationID)
            XCTAssertNotEqual(report.firstId, report.secondId)
            XCTAssertFalse(report.cases.isEmpty)
            XCTAssertLessThanOrEqual(report.cases.count, 7)
            XCTAssertFalse(report.choices.contains { $0.id.contains("surrender") })
            try await assertMatch(view, baseline)
            XCTAssertEqual(host.projection?.revision, originalJourney)
            XCTAssertEqual(host.projection?.eventCount, originalEvents)
            try await assertStorage(view, saved)
            let openRevision = try XCTUnwrap(host.projection?.arena?.revision)
            // An ordinary action captured before opening the comparison is stale.
            host.performArenaAction(oldMove, revision: oldArena.revision)
            XCTAssertFalse(host.arenaCommandPending)
            XCTAssertEqual(host.projection?.arena?.revision, openRevision)
            if let other = report.choices.first(where: { $0.id != report.firstId && $0.id != report.secondId }) {
                try await act("what-if:first:\(other.id)", host: host)
                XCTAssertEqual(host.projection?.arena?.whatIf?.firstId, other.id)
                XCTAssertEqual(host.whatIfPresentationID, originalPresentation)
                try await assertMatch(view, baseline)
            }
            try await act("what-if:close", host: host)
            XCTAssertNil(host.projection?.arena?.whatIf)
            XCTAssertNil(host.whatIfPresentationID)
            try await assertMatch(view, baseline)
            try await act("what-if:open", host: host)
            XCTAssertNotEqual(host.whatIfPresentationID, originalPresentation)
            host.setVisible(false)
            try await wait("Hidden report retired") { host.projection?.visible == false && host.projection?.arena?.whatIf == nil }
            host.setVisible(true)
            try await wait("Arena visible again") { host.projection?.visible == true }
            XCTAssertNil(host.projection?.arena?.whatIf)
            try await assertMatch(view, baseline)
            try await act("what-if:open", host: host)
            let beforeSeal = try XCTUnwrap(host.projection?.arena)
            let obsoleteChoice = try XCTUnwrap(beforeSeal.actions.first { $0.id.hasPrefix("what-if:first:") })
            try await act("one:guard", host: host)
            XCTAssertNil(host.projection?.arena?.whatIf)
            // Partner practice resolves immediately when the human plays.
            XCTAssertEqual(host.projection?.arena?.phase, .planning)
            XCTAssertNil(host.whatIfPresentationID)
            host.performArenaAction(obsoleteChoice, revision: beforeSeal.revision)
            XCTAssertFalse(host.arenaCommandPending)
            XCTAssertEqual(host.projection?.arena?.round, 2)
            XCTAssertNil(host.projection?.arena?.whatIf)
            let rehearsedRound = try await revealedRound(view)
            try await act("what-if:open", host: host)
            XCTAssertNotNil(host.projection?.arena?.whatIf)
            try await act("leave", host: host)
            XCTAssertEqual(host.projection?.mode, .habitat)
            XCTAssertNil(host.projection?.arena?.whatIf)
            XCTAssertTrue(host.webView === view)
            XCTAssertEqual(host.sessionID, session)
            XCTAssertEqual(host.projection?.revision, originalJourney)
            XCTAssertEqual(host.projection?.eventCount, originalEvents)
            try await assertStorage(view, saved)
            // The partner's private command is inspected only after normal
            // reveal. An untouched twin must resolve exactly the same way.
            try await act("start", host: host)
            let controlTeams = try await value(view, "return JSON.stringify(JSON.parse(window.render_game_to_text()).battle.teams);")
            XCTAssertEqual(controlTeams, startingTeams)
            try await act("one:guard", host: host)
            let controlRound = try await revealedRound(view)
            XCTAssertEqual(rehearsedRound, controlRound)
            try await act("leave", host: host)
            try await assertStorage(view, saved)
            XCTAssertEqual(host.projection?.revision, originalJourney)
            XCTAssertEqual(host.projection?.eventCount, originalEvents)
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("unused-preferences.json").path))
            let receipt: [String: Any] = ["status": "passed", "session": session.uuidString,
                "journeyRevision": originalJourney ?? "", "events": originalEvents ?? -1,
                "choices": report.choices.count, "opposingBranches": report.cases.count,
                "checks": ["open/change/close preserve public match and storage", "stale ordinary actions rejected",
                    "hidden comparison retired", "sealing retires comparison", "stale comparison action rejected",
                    "real next round uses existing resolver", "leaving keeps same host and Journey",
                    "rehearsed and untouched twins reveal identical commands and outcomes"],
                "limits": ["Separate native acceptance profile; no owner Journey writes", "No model call, remote player or camera coaching"]]
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("acceptance.json"))
            await host.shutdown(); await store.shutdownAssistant()
        } catch {
            let diagnostic = "\(error)\nHost: \(host.state), \(host.status), visible=\(host.isVisible), projection=\(String(describing: host.projection)), rejected=\(host.rejectedMessageCount)"
            try? Data(diagnostic.utf8).write(to: output.appendingPathComponent("failure.txt"))
            await host.shutdown(); await store.shutdownAssistant()
            throw error
        }
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
            guard Date() < deadline else { throw NSError(domain: "WhatIfAcceptance", code: 1,
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
    @MainActor private func assertStorage(_ view: WKWebView, _ expected: String) async throws {
        let actual = try await value(view, "return localStorage.getItem('archi.journey.v3') ?? '<absent>';")
        XCTAssertEqual(actual, expected)
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
            return JSON.stringify({round:e.round, commands:e.commands.map(({battleId,baseRevision,...command})=>command),
              outcomes:e.outcomes,winner:e.winner,teams:b.teams});
            """)
    }
}
