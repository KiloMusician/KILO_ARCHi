import XCTest
@testable import ARCHiDesktop

final class HostedArenaCoachingTests: XCTestCase {
    private typealias Action = HostedArenaProjection.Action
    private typealias Context = HostedArenaCoaching.Context

    private func action(_ id: String, label: String = "Move", detail: String = "Projected explanation") -> Action {
        Action(id: id, label: label, detail: detail)
    }
    private var choices: [Action] {
        [action("one:pulse", label: "Pulse"), action("one:guard", label: "Guard"),
         action("one:signature", label: "Mark"), action("one:swap:reserve", label: "Swap → Reserve")]
    }
    private func context(sessionID: UUID = UUID(), visibilityRevision: Int = 1,
                         journeyRevision: String = "journey-1", arenaRevision: String = String(repeating: "a", count: 64),
                         battleID: UUID = UUID()) -> Context {
        Context(sessionID: sessionID, visibilityRevision: visibilityRevision,
                journeyRevision: journeyRevision, arenaRevision: arenaRevision, battleID: battleID)
    }

    func testLegalChoicesRetainOnlyCurrentFirstPlayerMovesAndTheirExactTargetLabels() {
        let targeted = action("one:signature:ally", label: "Beacon → Ally", detail: "Restore Ally.")
        let valid = choices + [targeted]
        let excluded = ["start", "keep", "resolve", "leave", "again", "what-if:open", "one:surrender", "two:pulse",
                        "one:swap", "one:swap:", "one:signature:", "one:swap:reserve:extra", "one:signature: ",
                        "one:signature:\n", "one:unknown", "one:pulse:reserve"].map { action($0) }
        XCTAssertEqual(HostedArenaCoaching.legalChoices(from: valid + excluded), valid)
        XCTAssertEqual(HostedArenaCoaching.legalChoices(from: valid).last, targeted)
        XCTAssertTrue(HostedArenaCoaching.legalChoices(from: [action("one:guard", label: "")]).isEmpty)
        XCTAssertTrue(HostedArenaCoaching.legalChoices(from: [action("one:guard", detail: String(repeating: "x", count: 301))]).isEmpty)
    }

    func testBeginRequiresNonemptyUniqueLegalChoicesAndDoesNotEraseAnExistingSessionOnInvalidInput() throws {
        let basis = context(); var coaching = HostedArenaCoaching()
        let id = try XCTUnwrap(coaching.begin(context: basis, choices: choices))
        let preserved = coaching.session
        for invalid in [[], [choices[0], choices[0]], [action("two:guard")], [action("one:surrender")],
                        choices + [action("what-if:open")], [action("one:guard", label: "")]] {
            XCTAssertNil(coaching.begin(context: basis, choices: invalid))
            XCTAssertEqual(coaching.session, preserved)
        }
        XCTAssertEqual(coaching.session?.id, id)
        XCTAssertNil(coaching.session?.offer)
    }

    func testOfferAndAcceptReturnExactProjectedMoveWithoutMutatingInputValues() throws {
        let basis = context(), originalChoices = choices
        var suppliedChoices = originalChoices, coaching = HostedArenaCoaching()
        let id = try XCTUnwrap(coaching.begin(context: basis, choices: suppliedChoices))
        XCTAssertNil(coaching.accept(sessionID: id, context: basis, choices: suppliedChoices), "No offer exists yet.")
        XCTAssertEqual(coaching.session?.id, id)
        XCTAssertTrue(coaching.offer(sessionID: id, actionID: "one:guard", reason: "  Recover   Spark\u{00A0}before attacking.  ",
                                     context: basis, choices: suppliedChoices))
        XCTAssertEqual(coaching.session?.offer?.reason, "Recover Spark before attacking.")
        let offered = coaching.session
        suppliedChoices[1] = action("one:guard", label: "Changed externally")
        XCTAssertEqual(coaching.session, offered, "The presentation owns values, not mutable source references.")
        XCTAssertNil(coaching.accept(sessionID: id, context: basis, choices: suppliedChoices))
        XCTAssertEqual(coaching.session, offered)
        XCTAssertEqual(coaching.accept(sessionID: id, context: basis, choices: originalChoices), originalChoices[1])
        XCTAssertNil(coaching.session)
        XCTAssertEqual(originalChoices, choices)
        XCTAssertNil(coaching.accept(sessionID: id, context: basis, choices: originalChoices), "An offer can be accepted once.")
    }

    func testInvalidOffersPreserveTheCurrentOfferAndCannotInventAMove() throws {
        let basis = context(); var coaching = HostedArenaCoaching()
        let id = try XCTUnwrap(coaching.begin(context: basis, choices: choices))
        XCTAssertTrue(coaching.offer(sessionID: id, actionID: "one:guard", reason: "Recover Spark.", context: basis, choices: choices))
        let preserved = coaching.session
        for idToOffer in ["two:guard", "one:surrender", "one:swap:missing", "what-if:open", "one:signature:missing", ""] {
            XCTAssertFalse(coaching.offer(sessionID: id, actionID: idToOffer, reason: "Advice.", context: basis, choices: choices))
            XCTAssertEqual(coaching.session, preserved)
        }
        XCTAssertFalse(coaching.offer(sessionID: id, actionID: "one:guard", reason: "   ", context: basis, choices: choices))
        XCTAssertEqual(coaching.session, preserved)
    }

    func testReasonLimitCountsNormalizedUnicodeCharactersWithoutTruncating() throws {
        let basis = context(); var coaching = HostedArenaCoaching()
        let id = try XCTUnwrap(coaching.begin(context: basis, choices: choices))
        for reason in [String(repeating: "a", count: 240), String(repeating: "猫", count: 240),
                       String(repeating: "e\u{0301}", count: 240), String(repeating: "👨‍👩‍👧‍👦", count: 240)] {
            XCTAssertTrue(coaching.offer(sessionID: id, actionID: "one:guard", reason: "   " + reason + "   ", context: basis, choices: choices))
            XCTAssertEqual(coaching.session?.offer?.reason, reason)
            XCTAssertEqual(coaching.session?.offer?.reason.count, 240)
            let preserved = coaching.session
            XCTAssertFalse(coaching.offer(sessionID: id, actionID: "one:guard", reason: reason + "a", context: basis, choices: choices))
            XCTAssertEqual(coaching.session, preserved)
        }
        XCTAssertTrue(coaching.offer(sessionID: id, actionID: "one:guard", reason: "Hold\u{2009}\u{2009}the line.", context: basis, choices: choices))
        XCTAssertEqual(coaching.session?.offer?.reason, "Hold the line.")
    }

    func testReasonsRejectBlankControlNewlineAndDirectionalFormattingInput() throws {
        let basis = context(); var coaching = HostedArenaCoaching()
        let id = try XCTUnwrap(coaching.begin(context: basis, choices: choices))
        let empty = coaching.session
        for reason in ["", " \u{00A0}\u{2009} ", "Guard\nnow", "Guard\rnow", "Guard\tthen move", "Guard\u{0000}",
                       "Guard\u{001B}", "Guard\u{007F}", "Guard\u{2028}now", "Guard\u{2029}now", "Guard\u{202E}", "Guard\u{2066}"] {
            XCTAssertFalse(coaching.offer(sessionID: id, actionID: "one:guard", reason: reason, context: basis, choices: choices))
            XCTAssertEqual(coaching.session, empty)
        }
    }

    func testEveryContextChangeRejectsCallbacksAndReconciliationExpiresTheOffer() throws {
        let basis = context()
        let changed = [
            context(sessionID: UUID(), visibilityRevision: basis.visibilityRevision, journeyRevision: basis.journeyRevision,
                    arenaRevision: basis.arenaRevision, battleID: basis.battleID),
            context(sessionID: basis.sessionID, visibilityRevision: basis.visibilityRevision + 1, journeyRevision: basis.journeyRevision,
                    arenaRevision: basis.arenaRevision, battleID: basis.battleID),
            context(sessionID: basis.sessionID, visibilityRevision: basis.visibilityRevision, journeyRevision: "journey-2",
                    arenaRevision: basis.arenaRevision, battleID: basis.battleID),
            context(sessionID: basis.sessionID, visibilityRevision: basis.visibilityRevision, journeyRevision: basis.journeyRevision,
                    arenaRevision: String(repeating: "b", count: 64), battleID: basis.battleID),
            context(sessionID: basis.sessionID, visibilityRevision: basis.visibilityRevision, journeyRevision: basis.journeyRevision,
                    arenaRevision: basis.arenaRevision, battleID: UUID()),
        ]
        for currentContext in changed {
            var coaching = HostedArenaCoaching()
            let id = try XCTUnwrap(coaching.begin(context: basis, choices: choices))
            XCTAssertTrue(coaching.offer(sessionID: id, actionID: "one:guard", reason: "Recover Spark.", context: basis, choices: choices))
            let preserved = coaching.session
            XCTAssertFalse(coaching.offer(sessionID: id, actionID: "one:pulse", reason: "Try Pulse.", context: currentContext, choices: choices))
            XCTAssertNil(coaching.accept(sessionID: id, context: currentContext, choices: choices))
            XCTAssertEqual(coaching.session, preserved)
            coaching.reconcile(context: currentContext, choices: choices)
            XCTAssertNil(coaching.session)
        }
    }

    func testExactChoiceChangesExpireEvenWhenTheMoveIDRemainsAvailable() throws {
        let basis = context()
        var relabelled = choices; relabelled[1] = action("one:guard", label: "Different Guard")
        var redescribed = choices; redescribed[1] = action("one:guard", label: "Guard", detail: "Changed effect")
        for currentChoices in [Array(choices.reversed()), Array(choices.dropLast()), relabelled, redescribed, []] {
            var coaching = HostedArenaCoaching()
            let id = try XCTUnwrap(coaching.begin(context: basis, choices: choices))
            XCTAssertTrue(coaching.offer(sessionID: id, actionID: "one:guard", reason: "Recover Spark.", context: basis, choices: choices))
            XCTAssertNil(coaching.accept(sessionID: id, context: basis, choices: currentChoices))
            coaching.reconcile(context: basis, choices: currentChoices)
            XCTAssertNil(coaching.session)
        }
    }

    func testHiddenContextRetiresSessionAndReturningToIdenticalContextCannotReviveIt() throws {
        let basis = context(); var coaching = HostedArenaCoaching()
        let id = try XCTUnwrap(coaching.begin(context: basis, choices: choices))
        XCTAssertTrue(coaching.offer(sessionID: id, actionID: "one:guard", reason: "Recover Spark.", context: basis, choices: choices))
        coaching.reconcile(context: nil, choices: choices)
        XCTAssertNil(coaching.session)
        coaching.reconcile(context: basis, choices: choices)
        XCTAssertNil(coaching.accept(sessionID: id, context: basis, choices: choices))
        XCTAssertNil(coaching.session)
    }

    func testOldOfferAcceptAndDismissCannotClearOrRelabelANewerSession() throws {
        let basis = context(); var coaching = HostedArenaCoaching()
        let oldID = try XCTUnwrap(coaching.begin(context: basis, choices: choices))
        let newID = try XCTUnwrap(coaching.begin(context: basis, choices: choices))
        XCTAssertNotEqual(oldID, newID)
        XCTAssertTrue(coaching.offer(sessionID: newID, actionID: "one:guard", reason: "New coach suggestion.", context: basis, choices: choices))
        let current = coaching.session
        XCTAssertFalse(coaching.offer(sessionID: oldID, actionID: "one:pulse", reason: "Late suggestion.", context: basis, choices: choices))
        XCTAssertNil(coaching.accept(sessionID: oldID, context: basis, choices: choices))
        coaching.dismiss(sessionID: oldID)
        XCTAssertEqual(coaching.session, current)
        coaching.reconcile(context: basis, choices: choices)
        XCTAssertEqual(coaching.session, current)
        coaching.dismiss(sessionID: newID)
        XCTAssertNil(coaching.session)
        XCTAssertEqual(choices[1].label, "Guard")
    }

    func testResetRetiresAnOfferWithoutChangingCapturedInputs() throws {
        let basis = context(), originalChoices = choices
        var coaching = HostedArenaCoaching()
        let id = try XCTUnwrap(coaching.begin(context: basis, choices: originalChoices))
        XCTAssertTrue(coaching.offer(sessionID: id, actionID: "one:guard", reason: "Recover Spark.", context: basis, choices: originalChoices))
        let detached = coaching.session
        coaching.reset()
        XCTAssertNil(coaching.session)
        XCTAssertEqual(detached?.offer?.action, originalChoices[1])
        XCTAssertEqual(detached?.context, basis)
        XCTAssertEqual(originalChoices, choices)
        XCTAssertNil(coaching.accept(sessionID: id, context: basis, choices: originalChoices))
    }
}
