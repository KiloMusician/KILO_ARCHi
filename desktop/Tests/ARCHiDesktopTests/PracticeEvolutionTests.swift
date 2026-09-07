import Foundation
import XCTest
@testable import ARCHiDesktop

final class PracticeEvolutionTests: XCTestCase {
    private let origin = String(repeating: "a", count: 64)
    private let otherOrigin = String(repeating: "b", count: 64)

    @MainActor
    func testExplicitBindingAndReviewRecordExperienceWithoutChoosingOrGatingAForm() throws {
        let store = EvolutionStore()
        let reference = practice()
        XCTAssertFalse(store.reviewPractice(reference, currentOriginDigest: origin))
        XCTAssertNil(store.confirmedFamily)
        XCTAssertTrue(store.bindPracticeJourney(origin))
        XCTAssertTrue(store.reviewedPractices.isEmpty)
        XCTAssertTrue(store.reviewPractice(reference, currentOriginDigest: origin))
        XCTAssertEqual(store.preferences.confirmedCount, 0, "Practice does not choose or confirm user preferences")
        confirm(store)
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        let proposal = try XCTUnwrap(store.proposeEvolution())
        XCTAssertEqual(proposal.basis.kind, .appearanceChoice)
        XCTAssertNil(proposal.basis.practice)
        XCTAssertEqual(proposal.basis.title, "Your appearance choice")
        XCTAssertNil(proposal.appearanceRecipe)
        XCTAssertNil(store.activeFamily)
        XCTAssertTrue(store.keepEvolution(proposal))
        XCTAssertEqual(store.activeFamily, .lumen)
        XCTAssertEqual(store.keptBasis, proposal.basis)
        store.returnToStarter()
        XCTAssertNil(store.activeFamily)
        XCTAssertNil(store.keptBasis)
        XCTAssertEqual(store.reviewedPractices, [reference])
    }

    @MainActor
    func testEveryCompletedOutcomeCanCountAndReferencesAreBoundedAndDeduplicated() {
        let store = EvolutionStore()
        XCTAssertTrue(store.bindPracticeJourney(origin))
        for outcome in [PracticeEvolutionReference.Outcome.won, .lost, .draw] {
            XCTAssertTrue(store.reviewPractice(practice(outcome: outcome), currentOriginDigest: origin))
        }
        let first = store.reviewedPractices[0]
        XCTAssertFalse(store.reviewPractice(first, currentOriginDigest: origin))
        XCTAssertFalse(store.reviewPractice(practice(event: first.eventId, outcome: .draw), currentOriginDigest: origin),
                       "Changing outcome data cannot recount an existing origin/event pair")
        for _ in store.reviewedPractices.count..<EvolutionStore.maximumReviewedPractices {
            XCTAssertTrue(store.reviewPractice(practice(), currentOriginDigest: origin))
        }
        XCTAssertFalse(store.reviewPractice(practice(), currentOriginDigest: origin))
        XCTAssertEqual(store.reviewedPractices.count, 8)
        store.withdrawPractice(id: first.id)
        XCTAssertEqual(store.reviewedPractices.count, 7)
        XCTAssertTrue(store.reviewPractice(practice(), currentOriginDigest: origin))
    }

    @MainActor
    func testMalformedAndForeignReferencesLeaveEvidenceAndProposalUnchanged() throws {
        let store = EvolutionStore()
        confirm(store)
        XCTAssertTrue(store.bindPracticeJourney(origin))
        XCTAssertTrue(store.reviewPractice(practice(), currentOriginDigest: origin))
        let pending = try XCTUnwrap(store.proposeEvolution()), before = store.reviewedPractices
        let reference = practice()
        let encoded = try JSONEncoder().encode(reference)
        let base = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let invalidFields: [(String, Any)] = [
            ("originDigest", "bad"), ("replayDigest", String(repeating: "g", count: 64)),
            ("eventId", ""), ("eventId", "not an event"), ("rulesVersion", 2),
            ("rounds", 0), ("rounds", 21), ("committedAt", "yesterday"), ("committedAt", "2026-09-06T18:00:00Z trailing")
        ]
        for (field, invalid) in invalidFields {
            var object = base; object[field] = invalid
            let invalid = try JSONDecoder().decode(PracticeEvolutionReference.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertFalse(invalid.isValid, field)
            XCTAssertFalse(store.reviewPractice(invalid, currentOriginDigest: origin), field)
        }
        XCTAssertFalse(store.reviewPractice(practice(origin: otherOrigin), currentOriginDigest: otherOrigin))
        XCTAssertFalse(store.reviewPractice(reference, currentOriginDigest: otherOrigin))
        XCTAssertFalse(store.bindPracticeJourney("not a digest"))
        XCTAssertEqual(store.reviewedPractices, before)
        XCTAssertEqual(store.proposal, pending)
        XCTAssertEqual(store.practiceJourneyOriginDigest, origin)
    }

    @MainActor
    func testEvidenceChangesInvalidateProposalAndRebindPreservesKeptAppearance() throws {
        let store = EvolutionStore()
        confirm(store)
        XCTAssertTrue(store.bindPracticeJourney(origin))
        let first = practice()
        XCTAssertTrue(store.reviewPractice(first, currentOriginDigest: origin))
        let stale = try XCTUnwrap(store.proposeEvolution())
        XCTAssertTrue(store.reviewPractice(practice(), currentOriginDigest: origin))
        XCTAssertFalse(store.keepEvolution(stale))
        let kept = try XCTUnwrap(store.proposeEvolution())
        XCTAssertTrue(store.keepEvolution(kept))
        let history = store.history
        let next = try XCTUnwrap(store.proposeEvolution())
        XCTAssertTrue(store.bindPracticeJourney(otherOrigin))
        XCTAssertFalse(store.keepEvolution(next))
        XCTAssertTrue(store.reviewedPractices.isEmpty)
        XCTAssertEqual(store.activeFamily, .lumen)
        XCTAssertEqual(store.history, history)
        XCTAssertEqual(store.keptBasis?.kind, .appearanceChoice)
        XCTAssertNil(store.keptBasis?.practice, "New appearance choices do not claim a practice caused a body")
        XCTAssertFalse(store.reviewPractice(first, currentOriginDigest: origin))
        XCTAssertTrue(store.reviewPractice(practice(origin: otherOrigin), currentOriginDigest: otherOrigin))
        XCTAssertEqual(store.reviewedPractices.count, 1)
        XCTAssertEqual(store.activeFamily, .lumen)
    }

    @MainActor
    func testWithdrawalRemovesPracticeReferenceWithoutDemotingTheKeptBody() throws {
        let store = EvolutionStore()
        confirm(store)
        XCTAssertTrue(store.bindPracticeJourney(origin))
        let reference = practice()
        XCTAssertTrue(store.reviewPractice(reference, currentOriginDigest: origin))
        XCTAssertNotNil(store.proposeEvolution())
        XCTAssertTrue(store.keepEvolution())
        let stale = try XCTUnwrap(store.proposeEvolution())
        store.withdrawPractice(id: reference.id)
        XCTAssertTrue(store.reviewedPractices.isEmpty)
        XCTAssertFalse(store.keepEvolution(stale))
        XCTAssertEqual(store.activeFamily, .lumen)
        XCTAssertEqual(store.keptBasis?.kind, .appearanceChoice)
        XCTAssertNil(store.keptBasis?.practice)
    }

    @MainActor
    func testHistoricalV3PracticeKeepAndRebindingRoundTripThroughV4Save() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reference = practice()
        var legacy = try EvolutionLegacyTestData.object(practice: reference)
        legacy["origin"] = CompanionForm.ink.rawValue
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.load())
        let recipe = store.keptAppearanceRecipe
        XCTAssertTrue(store.bindPracticeJourney(otherOrigin))
        XCTAssertTrue(store.save())
        let saved = try Data(contentsOf: url)
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertNil(reopened.activeFamily)
        XCTAssertTrue(reopened.load())
        XCTAssertEqual(reopened.origin, .ink)
        XCTAssertEqual(reopened.activeFamily, .lumen)
        XCTAssertEqual(reopened.keptBasis?.practice, reference)
        XCTAssertEqual(reopened.practiceJourneyOriginDigest, otherOrigin)
        XCTAssertTrue(reopened.reviewedPractices.isEmpty)
        XCTAssertEqual(reopened.keptAppearanceRecipe, recipe)
        XCTAssertNil(reopened.activeAppearanceRecipe, "Another Journey cannot apply an old individual recipe")
        XCTAssertEqual(try Data(contentsOf: url), saved)
        XCTAssertTrue(reopened.forget())
        XCTAssertNil(reopened.practiceJourneyOriginDigest)
        XCTAssertNil(reopened.keptBasis)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testHistoricalUsefulWorkBasisRemainsLoadableAfterPracticeReplacesCurrentEvidence() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try EvolutionLegacyTestData.data().write(to: url)
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.load())
        let requests = store.usefulReceipts.map(\.requestID), originalRecipe = store.keptAppearanceRecipe
        XCTAssertEqual(store.keptBasis?.kind, .usefulWork)
        XCTAssertTrue(store.bindPracticeJourney(origin))
        XCTAssertTrue(store.reviewPractice(practice(), currentOriginDigest: origin))
        for request in requests { store.withdrawUseful(requestID: request) }
        XCTAssertEqual(store.activeFamily, .lumen)
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertTrue(store.bindPracticeJourney(otherOrigin))
        XCTAssertTrue(store.save())
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.load())
        XCTAssertEqual(reopened.activeFamily, .lumen)
        XCTAssertEqual(reopened.keptBasis?.kind, .usefulWork)
        XCTAssertTrue(reopened.usefulReceipts.isEmpty)
        XCTAssertTrue(reopened.reviewedPractices.isEmpty)
        XCTAssertEqual(reopened.keptAppearanceRecipe, originalRecipe)
    }

    @MainActor
    func testValidV1SaveLoadsUnchangedAndOnlyExplicitSaveMigratesWithoutInventedPractice() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workIDs = [UUID(), UUID()], historyID = UUID()
        let object: [String: Any] = ["schema": "archi-companion-evolution/v1", "origin": CompanionForm.light.rawValue,
            "role": "muse", "helpStyle": "exploratory", "family": "fen", "activeFamily": "fen",
            "usefulReceipts": workIDs.map { ["requestID": $0.uuidString, "sourceDigest": origin] },
            "history": [["kind": "kept", "family": "fen", "id": historyID.uuidString]]]
        let legacy = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try legacy.write(to: url)
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.load())
        XCTAssertEqual(store.origin, .light)
        XCTAssertEqual(store.activeFamily, .fen)
        XCTAssertEqual(store.usefulReceipts.map(\.requestID), workIDs)
        XCTAssertEqual(store.history.first?.id, historyID)
        XCTAssertEqual(store.keptBasis?.kind, .usefulWork)
        XCTAssertTrue(store.reviewedPractices.isEmpty)
        XCTAssertNil(store.practiceJourneyOriginDigest)
        XCTAssertEqual(try Data(contentsOf: url), legacy)
        XCTAssertTrue(store.save())
        let saved = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(saved["schema"] as? String, EvolutionStore.schema)
        XCTAssertEqual((saved["reviewedPractices"] as? [Any])?.count, 0)
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.load())
        XCTAssertEqual(reopened.history, store.history)
        XCTAssertEqual(reopened.usefulReceipts, store.usefulReceipts)
    }

    @MainActor
    func testForgedV2SaveCannotChangeCurrentStateOrOverwriteItsFile() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(saveURL: url)
        confirm(store); XCTAssertTrue(store.bindPracticeJourney(origin))
        XCTAssertTrue(store.reviewPractice(practice(), currentOriginDigest: origin))
        XCTAssertNotNil(store.proposeEvolution()); XCTAssertTrue(store.keepEvolution()); XCTAssertTrue(store.save())
        let valid = try Data(contentsOf: url)
        let baseline = try XCTUnwrap(try JSONSerialization.jsonObject(with: valid) as? [String: Any])
        for mutate in [
            { (value: inout [String: Any]) in value["practiceJourneyOriginDigest"] = self.otherOrigin },
            { (value: inout [String: Any]) in value["keptBasis"] = NSNull() },
            { (value: inout [String: Any]) in value["reviewedPractices"] = (value["reviewedPractices"] as! [Any]) + (value["reviewedPractices"] as! [Any]) },
            { (value: inout [String: Any]) in
                var basis = value["keptBasis"] as! [String: Any]
                basis["permission"] = "grant-tools"; value["keptBasis"] = basis
            }
        ] {
            var object = baseline; mutate(&object)
            let invalid = try JSONSerialization.data(withJSONObject: object)
            try invalid.write(to: url)
            XCTAssertFalse(store.load())
            XCTAssertFalse(store.save())
            XCTAssertEqual(store.activeFamily, .lumen)
            XCTAssertEqual(store.practiceJourneyOriginDigest, origin)
            XCTAssertEqual(try Data(contentsOf: url), invalid)
        }
    }

    private func practice(origin: String? = nil, event: String = UUID().uuidString,
                          outcome: PracticeEvolutionReference.Outcome = .won) -> PracticeEvolutionReference {
        PracticeEvolutionReference(originDigest: origin ?? self.origin, eventId: event, battleId: UUID(), rulesVersion: 1,
            rounds: 6, outcome: outcome, replayDigest: String(repeating: "c", count: 64), committedAt: "2026-09-06T18:00:00.000Z")
    }
    @MainActor private func confirm(_ store: EvolutionStore) {
        store.confirmRole(.muse); store.confirmHelpStyle(.exploratory); store.confirmFamily(.lumen)
    }
    private func temporarySave() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ARCHi-practice-evolution-\(UUID().uuidString)").appendingPathComponent("evolution.json")
    }
}
