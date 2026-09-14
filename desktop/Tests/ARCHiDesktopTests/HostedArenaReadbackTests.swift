import Foundation
import XCTest
@testable import ARCHiDesktop

final class HostedArenaReadbackTests: XCTestCase {
    func testPublicTeamsAndResolvedRoundsDecodeAsValueSnapshots() throws {
        let session = UUID(), body = projection(session: session, round: 3)
        let readback = try XCTUnwrap(HostedPlayProjection.decode(body, sessionID: session, after: 0).arena?.readback)
        XCTAssertEqual(readback.teams.map(\.id), [.one, .two])
        XCTAssertEqual(readback.teams[0].integrity, 33)
        XCTAssertEqual(readback.teams[0].maximumIntegrity, 36)
        XCTAssertEqual(readback.teams[0].spark, 2)
        XCTAssertEqual(readback.teams[0].activeMember?.id, "one-0")
        XCTAssertEqual(readback.teams[0].reserves.map(\.id), ["one-1", "one-2"])
        XCTAssertEqual(readback.latestRound?.round, 2)
        XCTAssertNil(readback.result)
    }

    func testVersionFourRequiresReadbackOnlyAfterEntryAndKeepsLegacyShapes() throws {
        let session = UUID(); var candidate = projection(session: session)
        var arena = candidate["arena"] as! [String: Any]
        arena.removeValue(forKey: "readback"); candidate["arena"] = arena
        XCTAssertThrowsError(try decode(candidate, session: session))
        arena["readback"] = NSNull(); candidate["arena"] = arena
        XCTAssertThrowsError(try decode(candidate, session: session))
        arena["phase"] = "entry"; arena["battleId"] = NSNull(); arena["round"] = 0; candidate["arena"] = arena
        XCTAssertNil(try decode(candidate, session: session).arena?.readback)
        arena["readback"] = readback(round: 1); candidate["arena"] = arena
        XCTAssertThrowsError(try decode(candidate, session: session))

        for version in [2, 3] {
            candidate = projection(session: session); candidate["version"] = version
            arena = candidate["arena"] as! [String: Any]; arena.removeValue(forKey: "readback")
            if version == 2 { arena.removeValue(forKey: "whatIf") }
            candidate["arena"] = arena
            XCTAssertNil(try decode(candidate, session: session).arena?.readback)
            arena["readback"] = NSNull(); candidate["arena"] = arena
            XCTAssertThrowsError(try decode(candidate, session: session), "Historical versions keep their closed shape")
        }
    }

    func testVersionFourLoadingAndNullArenaRemainValid() throws {
        let session = UUID(); var candidate = projection(session: session)
        candidate["arena"] = NSNull(); candidate["mode"] = "habitat"
        XCTAssertNil(try decode(candidate, session: session).arena)
        candidate["readiness"] = "loading"; candidate["storage"] = "unknown"
        for key in ["journeyId", "revision", "eventCount", "originDigest"] { candidate[key] = NSNull() }
        XCTAssertEqual(try decode(candidate, session: session).readiness, .loading)
    }

    func testFinishedResultsHaveBoundedExplicitRetentionAndRoundCount() throws {
        let session = UUID()
        for retention in ["unsaved", "saving", "saved", "session-only", "unavailable"] {
            var candidate = projection(session: session, round: 4, finished: true)
            candidate = changingReadback(candidate) { readback in
                var result = readback["result"] as! [String: Any]; result["retention"] = retention; readback["result"] = result
            }
            let arena = try XCTUnwrap(decode(candidate, session: session).arena)
            XCTAssertEqual(arena.readback?.result?.retention.rawValue, retention)
            XCTAssertEqual(arena.readback?.rounds.count, 4)
            XCTAssertEqual(arena.readback?.result?.winner, .one)
            XCTAssertEqual(arena.readback?.result?.reason, .eliminated)
        }
        let finished = projection(session: session, finished: true)
        XCTAssertThrowsError(try decode(changingReadback(finished) { $0["result"] = NSNull() }, session: session))
        let active = projection(session: session)
        XCTAssertThrowsError(try decode(changingReadback(active) { $0["result"] = result() }, session: session))
        for (key, value) in [("winner", "unknown"), ("reason", "timeout"), ("retention", "persisted"), ("message", ""), ("message", String(repeating: "🦋", count: 76))] {
            let changed = changingReadback(finished) { readback in
                var result = readback["result"] as! [String: Any]; result[key] = value; readback["result"] = result
            }
            XCTAssertThrowsError(try decode(changed, session: session), key)
        }
    }

    func testRejectsPrivateOrUnknownFieldsAtEveryReadbackLevel() throws {
        let session = UUID(), original = projection(session: session, round: 2, finished: true)
        for scope in ["readback", "team", "member", "round", "result"] {
            let candidate = changingReadback(original) { readback in
                switch scope {
                case "readback": readback["sealedCommands"] = ["one": "guard"]
                case "team":
                    var teams = readback["teams"] as! [[String: Any]]; teams[0]["nextMove"] = "pulse"; readback["teams"] = teams
                case "member":
                    var teams = readback["teams"] as! [[String: Any]], roster = teams[0]["roster"] as! [[String: Any]]
                    roster[0]["futureDamage"] = 4; teams[0]["roster"] = roster; readback["teams"] = teams
                case "round":
                    var rounds = readback["rounds"] as! [[String: Any]]; rounds[0]["draft"] = "guard"; readback["rounds"] = rounds
                default:
                    var result = readback["result"] as! [String: Any]; result["permission"] = true; readback["result"] = result
                }
            }
            XCTAssertThrowsError(try decode(candidate, session: session), scope)
        }
        for key in ["teams", "rounds", "result"] {
            XCTAssertThrowsError(try decode(changingReadback(original) { $0.removeValue(forKey: key) }, session: session), key)
        }
    }

    func testTeamOrderIdentityAndRosterTotalsCannotBeForged() throws {
        let session = UUID(), original = projection(session: session)
        for mutation in ["missing", "extra", "reversed", "same-team", "same-member", "cross-team-member", "empty-roster", "four-members", "wrong-total", "two-active", "dead-active"] {
            let candidate = changingReadback(original) { readback in
                var teams = readback["teams"] as! [[String: Any]]
                var roster = teams[0]["roster"] as! [[String: Any]]
                switch mutation {
                case "missing": teams.removeLast()
                case "extra": teams.append(teams[0])
                case "reversed": teams.reverse()
                case "same-team": teams[1]["id"] = "one"
                case "same-member": roster[1]["id"] = roster[0]["id"]; teams[0]["roster"] = roster
                case "cross-team-member":
                    var other = teams[1]["roster"] as! [[String: Any]]; other[0]["id"] = roster[0]["id"]; teams[1]["roster"] = other
                case "empty-roster": teams[0]["roster"] = [] as [[String: Any]]
                case "four-members": teams[0]["roster"] = roster + [roster[0]]
                case "wrong-total": roster[0]["maximumIntegrity"] = 13; teams[0]["roster"] = roster
                case "two-active": roster[1]["active"] = true; teams[0]["roster"] = roster
                default: roster[0]["integrity"] = 0; teams[0]["roster"] = roster
                }
                readback["teams"] = teams
            }
            XCTAssertThrowsError(try decode(candidate, session: session), mutation)
        }
    }

    func testScalarTypesAndResourceBoundsAreStrict() throws {
        let session = UUID(), original = projection(session: session)
        let memberMutations: [(String, Any)] = [
            ("integrity", -1), ("integrity", 13), ("integrity", 1.5), ("integrity", true), ("maximumIntegrity", 0),
            ("maximumIntegrity", 37), ("maximumIntegrity", Int.max), ("active", 1), ("exposed", "false"),
            ("id", ""), ("id", String(repeating: "x", count: 161)), ("name", ""),
            ("name", String(repeating: "🦋", count: 31)), ("role", "wizard")
        ]
        for (key, value) in memberMutations {
            let candidate = changingReadback(original) { readback in
                var teams = readback["teams"] as! [[String: Any]], roster = teams[0]["roster"] as! [[String: Any]]
                roster[0][key] = value; teams[0]["roster"] = roster; readback["teams"] = teams
            }
            XCTAssertThrowsError(try decode(candidate, session: session), "member \(key): \(value)")
        }
        for (key, value) in [("spark", -1), ("spark", 4), ("spark", 0.5), ("spark", true), ("label", ""), ("label", String(repeating: "🦋", count: 31))] as [(String, Any)] {
            let candidate = changingReadback(original) { readback in
                var teams = readback["teams"] as! [[String: Any]]; teams[0][key] = value; readback["teams"] = teams
            }
            XCTAssertThrowsError(try decode(candidate, session: session), "team \(key): \(value)")
        }
    }

    func testHistoryContainsOnlyContiguousAlreadyResolvedRounds() throws {
        let session = UUID(), original = projection(session: session, round: 3)
        let invalid: [[[String: Any]]] = [
            [], [["round": 1, "summary": "Only one."]],
            [["round": 1, "summary": "One."], ["round": 1, "summary": "Duplicate."]],
            [["round": 1, "summary": "One."], ["round": 3, "summary": "Not resolved yet."]],
            [["round": true, "summary": "Wrong scalar."], ["round": 2, "summary": "Two."]],
            [["round": 1, "summary": ""], ["round": 2, "summary": "Two."]],
            [["round": 1, "summary": String(repeating: "🦋", count: 126)], ["round": 2, "summary": "Two."]],
            (1...21).map { ["round": $0, "summary": "Resolved."] }
        ]
        for history in invalid {
            XCTAssertThrowsError(try decode(changingReadback(original) { $0["rounds"] = history }, session: session))
        }
        var sealed = original, arena = original["arena"] as! [String: Any]
        arena["phase"] = "sealed"; sealed["arena"] = arena
        XCTAssertEqual(try decode(sealed, session: session).arena?.readback?.rounds.count, 2)
    }

    func testSingleMemberAndEliminatedTeamAreRepresentable() throws {
        let session = UUID()
        let candidate = changingReadback(projection(session: session, finished: true)) { readback in
            var teams = readback["teams"] as! [[String: Any]]
            for index in teams.indices {
                var member = (teams[index]["roster"] as! [[String: Any]])[0]
                member["maximumIntegrity"] = 36; member["integrity"] = index == 0 ? 36 : 0
                member["active"] = index == 0; teams[index]["roster"] = [member]
            }
            readback["teams"] = teams
        }
        let readback = try XCTUnwrap(decode(candidate, session: session).arena?.readback)
        XCTAssertEqual(readback.teams[0].reserves.count, 0)
        XCTAssertEqual(readback.teams[1].integrity, 0)
        XCTAssertNil(readback.teams[1].activeMember)
    }

    func testFullHistoryFitsButCombinedPayloadCannotExceedTransportBudget() throws {
        let session = UUID()
        var candidate = changingReadback(projection(session: session, round: 20, finished: true)) { readback in
            readback["rounds"] = (1...20).map { ["round": $0, "summary": String(repeating: "r", count: 500)] }
        }
        XCTAssertEqual(try decode(candidate, session: session).arena?.readback?.rounds.count, 20)
        candidate = changingReadback(projection(session: session, round: 20)) { readback in
            readback["rounds"] = (1...19).map { ["round": $0, "summary": String(repeating: "r", count: 500)] }
        }
        var arena = candidate["arena"] as! [String: Any]
        let actions = (0..<32).map { ["id": String($0).padding(toLength: 160, withPad: "x", startingAt: 0), "label": String(repeating: "l", count: 120), "detail": String(repeating: "d", count: 300)] }
        arena["actions"] = actions
        arena["whatIf"] = [
            "choices": Array(actions.prefix(7)), "firstId": actions[0]["id"]!, "secondId": actions[1]["id"]!,
            "cases": (0..<7).map { ["opponentId": "case-\($0)", "opponentLabel": "Public choice", "first": String(repeating: "a", count: 700), "second": String(repeating: "b", count: 700)] }
        ]
        candidate["arena"] = arena
        XCTAssertGreaterThan(try JSONSerialization.data(withJSONObject: candidate).count, 32_768)
        XCTAssertThrowsError(try decode(candidate, session: session))
    }

    func testRejectedOrLateReadbacksNeverReplaceAnAdmittedSnapshot() throws {
        var gate = HostedPlayProjectionGate(); gate.begin()
        var candidate = projection(session: gate.sessionID, round: 2)
        let mutable = NSMutableDictionary(dictionary: ["round": 1, "summary": "Original resolved round."])
        candidate = changingReadback(candidate) { $0["rounds"] = [mutable] }
        let admitted = try gate.receive(candidate)
        mutable["summary"] = "Changed after receipt."
        XCTAssertEqual(admitted.arena?.readback?.latestRound?.summary, "Original resolved round.")
        candidate["sequence"] = 2
        let malformed = changingReadback(candidate) { $0["sealedCommands"] = "private" }
        XCTAssertThrowsError(try gate.receive(malformed)); XCTAssertEqual(gate.sequence, 1)
        XCTAssertEqual(try gate.receive(candidate).sequence, 2)
        gate.retire(); candidate["sequence"] = 3
        XCTAssertThrowsError(try gate.receive(candidate))
        gate.begin()
        XCTAssertThrowsError(try gate.receive(candidate))
    }

    private func decode(_ body: [String: Any], session: UUID) throws -> HostedPlayProjection {
        try HostedPlayProjection.decode(body, sessionID: session, after: 0)
    }

    private func changingReadback(_ body: [String: Any], _ mutate: (inout [String: Any]) -> Void) -> [String: Any] {
        var value = body, arena = body["arena"] as! [String: Any], readback = arena["readback"] as! [String: Any]
        mutate(&readback); arena["readback"] = readback; value["arena"] = arena
        return value
    }

    private func result() -> [String: Any] {
        ["winner": "one", "reason": "eliminated", "retention": "unsaved", "message": "Keep this practice in Journey."]
    }

    private func readback(round: Int, finished: Bool = false) -> [String: Any] {
        let teams: [[String: Any]] = ["one", "two"].map { team in
            ["id": team, "label": team == "one" ? "Your team" : "Practice partner", "spark": 2,
             "roster": (0..<3).map { index in
                 ["id": "\(team)-\(index)", "name": "Companion \(index + 1)", "role": "scout", "integrity": 11,
                  "maximumIntegrity": 12, "active": index == 0, "exposed": index == 0] as [String: Any]
             }]
        }
        let historyCount = finished ? round : round - 1
        return ["teams": teams, "rounds": (0..<historyCount).map { ["round": $0 + 1, "summary": "Both teams resolved their choices."] },
                "result": finished ? result() : NSNull()]
    }

    private func projection(session: UUID, round: Int = 1, finished: Bool = false) -> [String: Any] {
        let digest = String(repeating: "a", count: 64)
        return ["version": 4, "host": "archi-desktop", "sessionId": session.uuidString, "sequence": 1,
                "kind": "journey-projection", "readiness": "ready", "storage": "local-browser", "mode": "battle",
                "journeyId": "ARCHI-READBACK", "revision": "event-1-" + digest, "eventCount": 1, "visible": true,
                "originDigest": digest, "practices": [] as [[String: Any]],
                "arena": ["battleId": UUID().uuidString, "revision": digest, "phase": finished ? "finished" : "planning", "round": round,
                          "summary": "Practice readback.", "actions": [["id": "leave", "label": "Return to Habitat", "detail": "Leave practice."]],
                          "whatIf": NSNull(), "readback": readback(round: round, finished: finished)]]
    }
}
