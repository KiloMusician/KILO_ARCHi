import Foundation
import XCTest
@testable import ARCHiDesktop

final class HostedPracticeProjectionTests: XCTestCase {
    private let origin = String(repeating: "a", count: 64)
    private func body(session: UUID, sequence: Int = 1) -> [String: Any] {
        ["version": 2, "host": "archi-desktop", "sessionId": session.uuidString, "sequence": sequence,
         "kind": "journey-projection", "readiness": "ready", "storage": "local-browser", "mode": "battle",
         "journeyId": "ARCHI-A8BFA94B", "revision": "event-1-" + origin, "eventCount": 1, "visible": true,
         "originDigest": origin,
         "practices": [["originDigest": origin, "eventId": "event-1-" + origin, "battleId": UUID().uuidString,
                        "rulesVersion": 1, "rounds": 6, "outcome": "won", "replayDigest": origin,
                        "committedAt": "2026-09-06T20:00:00.000Z"]],
         "arena": ["battleId": UUID().uuidString, "revision": origin, "phase": "planning", "round": 1,
                   "summary": "Choose a move. The partner has already chosen.",
                   "actions": [["id": "one:guard", "label": "Guard", "detail": "Recover Spark and prepare a shield."]]]]
    }

    func testPracticeReadbackIsBoundedAndBoundToWholeOrigin() throws {
        let session = UUID(), object = body(session: session)
        let result = try HostedPlayProjection.decode(object, sessionID: session, after: 0)
        XCTAssertEqual(result.originDigest, origin)
        XCTAssertEqual(result.practices?.count, 1)
        XCTAssertEqual(result.arena?.actions.first?.id, "one:guard")
        var foreign = object
        var practices = try XCTUnwrap(foreign["practices"] as? [[String: Any]])
        practices[0]["originDigest"] = String(repeating: "b", count: 64)
        foreign["practices"] = practices
        XCTAssertThrowsError(try HostedPlayProjection.decode(foreign, sessionID: session, after: 0))
        foreign = object; foreign["practices"] = Array(repeating: practices[0], count: 9)
        XCTAssertThrowsError(try HostedPlayProjection.decode(foreign, sessionID: session, after: 0))
    }

    func testRejectsForgedPrivateFieldsDuplicateActionsAndInvalidRound() throws {
        let session = UUID(), valid = body(session: session)
        var arena = try XCTUnwrap(valid["arena"] as? [String: Any])
        for mutation in ["private", "duplicate", "round"] {
            var candidate = valid, changed = arena
            switch mutation {
            case "private": changed["partnerSealedMove"] = "burst"
            case "duplicate": changed["actions"] = Array(repeating: (arena["actions"] as! [[String: Any]])[0], count: 2)
            default: changed["round"] = 21
            }
            candidate["arena"] = changed
            XCTAssertThrowsError(try HostedPlayProjection.decode(candidate, sessionID: session, after: 0), mutation)
        }
        arena["summary"] = String(repeating: "x", count: 501)
        var candidate = valid; candidate["arena"] = arena
        XCTAssertThrowsError(try HostedPlayProjection.decode(candidate, sessionID: session, after: 0))
    }

    func testRetiredSessionAndLateMessagesCannotRestoreControls() throws {
        var gate = HostedPlayProjectionGate(); gate.begin()
        let old = body(session: gate.sessionID)
        _ = try gate.receive(old)
        XCTAssertThrowsError(try gate.receive(old))
        gate.retire()
        var late = old; late["sequence"] = 2
        XCTAssertThrowsError(try gate.receive(late))
        gate.begin()
        XCTAssertThrowsError(try gate.receive(late))
        let current = try gate.receive(body(session: gate.sessionID))
        XCTAssertNotNil(current.arena)
    }

    func testHiddenReadbackPreservesOutcomeButDoesNotRelabelBattle() throws {
        let session = UUID(); var hidden = body(session: session)
        hidden["visible"] = false
        let result = try HostedPlayProjection.decode(hidden, sessionID: session, after: 0)
        XCTAssertFalse(result.visible)
        XCTAssertEqual(result.practices?.first?.outcome, .won)
        XCTAssertEqual(result.arena?.phase, .planning)
        hidden["mode"] = "field"
        XCTAssertThrowsError(try HostedPlayProjection.decode(hidden, sessionID: session, after: 0))
    }
}
