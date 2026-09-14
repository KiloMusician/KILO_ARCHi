import Foundation
import XCTest
@testable import ARCHiDesktop

final class IndividualEvolutionStoreTests: XCTestCase {
    private let origin = String(repeating: "a", count: 64)
    private let otherOrigin = String(repeating: "b", count: 64)

    @MainActor
    func testNaturalIndividualExistsBeforePreferencesTasksOrAppearanceChoice() throws {
        let store = EvolutionStore()
        XCTAssertNil(store.naturalVariation, "Evolution cannot invent a Journey origin")
        store.observeJourneyOrigin(origin)
        let natural = try XCTUnwrap(store.naturalVariation)
        XCTAssertEqual(natural.originDigest, origin)
        XCTAssertNil(store.practiceJourneyOriginDigest, "Observation is not a history binding")
        XCTAssertEqual(store.preferences.confirmedCount, 0)
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertTrue(store.reviewedPractices.isEmpty)
        XCTAssertFalse(store.hasUnsavedChanges)
        store.confirmFamily(.lumen)
        let proposed = try XCTUnwrap(store.proposeEvolution())
        XCTAssertEqual(proposed.basis.kind, .appearanceChoice)
        XCTAssertNil(proposed.appearanceRecipe)
        XCTAssertTrue(store.keepEvolution(proposed))
        XCTAssertEqual(store.naturalVariation, natural)
        XCTAssertNil(store.keptAppearanceRecipe)
        XCTAssertEqual(store.activeFamily, .lumen)
    }

    @MainActor
    func testObservedJourneyAToBToAFencesTheExactProposalWhileNaturalIdentityIsRepeatable() throws {
        let store = EvolutionStore()
        store.confirmFamily(.lumen)
        store.observeJourneyOrigin(origin)
        let first = try XCTUnwrap(store.proposeEvolution()), natural = store.naturalVariation
        let oldRevision = store.revision
        store.observeJourneyOrigin(otherOrigin)
        XCTAssertNil(store.proposal)
        XCTAssertNil(store.previewFamily)
        XCTAssertNotEqual(store.naturalVariation, natural)
        store.observeJourneyOrigin(origin)
        XCTAssertGreaterThan(store.revision, oldRevision)
        XCTAssertEqual(store.naturalVariation, natural)
        XCTAssertFalse(store.keepEvolution(first), "Returning to the same individual cannot revive a retired proposal")
        let fresh = try XCTUnwrap(store.proposeEvolution()), revision = store.revision
        store.observeJourneyOrigin(origin)
        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(store.proposal, fresh)
        XCTAssertTrue(store.keepEvolution(fresh))
    }

    @MainActor
    func testRoleStyleAndFutureFamilyDoNotRedrawOrDemoteTheKeptIndividual() throws {
        let store = EvolutionStore()
        store.observeJourneyOrigin(origin)
        store.confirmFamily(.lumen)
        XCTAssertTrue(store.keepEvolution(try XCTUnwrap(store.proposeEvolution())))
        let natural = store.naturalVariation, history = store.history
        let stale = try XCTUnwrap(store.proposeEvolution())
        store.confirmRole(.keeper)
        store.confirmHelpStyle(.reflective)
        store.confirmFamily(.veil)
        XCTAssertFalse(store.keepEvolution(stale))
        XCTAssertEqual(store.activeFamily, .lumen)
        XCTAssertEqual(store.naturalVariation, natural)
        XCTAssertEqual(store.history, history)
        for category in EvolutionPreferenceCategory.allCases { store.revoke(category) }
        XCTAssertNil(store.proposeEvolution(), "A family must be selected for a new appearance choice")
        XCTAssertEqual(store.activeFamily, .lumen)
        XCTAssertEqual(store.naturalVariation, natural)
        store.confirmFamily(.veil)
        XCTAssertTrue(store.keepEvolution(try XCTUnwrap(store.proposeEvolution())))
        XCTAssertEqual(store.activeFamily, .veil)
        XCTAssertEqual(store.naturalVariation, natural)
        XCTAssertEqual(store.history.first, history.first)
        XCTAssertEqual(store.keptBasis?.kind, .appearanceChoice)
    }

    @MainActor
    func testReturnAndForgetDoNotEraseTheIndividualOwnedByTheOpenJourney() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(origin: .ink, saveURL: url)
        store.observeJourneyOrigin(origin)
        let natural = store.naturalVariation
        store.confirmFamily(.lumen)
        XCTAssertTrue(store.bindPracticeJourney(origin))
        XCTAssertTrue(store.keepEvolution(try XCTUnwrap(store.proposeEvolution())))
        XCTAssertTrue(store.save())
        let saved = try Data(contentsOf: url)
        store.returnToStarter()
        XCTAssertEqual(store.origin, .ink)
        XCTAssertNil(store.activeFamily)
        XCTAssertNil(store.keptBasis)
        XCTAssertEqual(store.naturalVariation, natural)
        XCTAssertEqual(store.history.last?.kind, .returned)
        XCTAssertEqual(try Data(contentsOf: url), saved, "Return needs an explicit Save to update the existing archive")
        XCTAssertTrue(store.load())
        let pending = try XCTUnwrap(store.proposeEvolution())
        XCTAssertTrue(store.forget())
        XCTAssertFalse(store.keepEvolution(pending))
        XCTAssertNil(store.practiceJourneyOriginDigest)
        XCTAssertNil(store.activeFamily)
        XCTAssertNil(store.keptAppearanceRecipe)
        XCTAssertEqual(store.naturalVariation, natural, "Forget clears evolution records, not the host-owned individual")
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(store.reviewedPractices.isEmpty)
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertEqual(store.preferences.confirmedCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testCurrentSaveKeepsChosenBodyAfterAllAssistanceAndFutureFormPreferencesAreRemoved() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(origin: .light, saveURL: url)
        XCTAssertTrue(store.bindPracticeJourney(origin))
        store.confirmFamily(.lumen)
        XCTAssertTrue(store.keepEvolution(try XCTUnwrap(store.proposeEvolution())))
        store.revoke(.family)
        XCTAssertEqual(store.preferences.confirmedCount, 0)
        XCTAssertEqual(store.activeFamily, .lumen)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(store.save())
        let saved = try Data(contentsOf: url), object = try jsonObject(saved)
        XCTAssertEqual(object["schema"] as? String, EvolutionStore.schema)
        XCTAssertTrue(object["keptAppearanceRecipe"] is NSNull)
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertNil(reopened.activeFamily)
        XCTAssertTrue(reopened.load())
        XCTAssertEqual(reopened.origin, .light)
        XCTAssertEqual(reopened.activeFamily, .lumen)
        XCTAssertEqual(reopened.preferences.confirmedCount, 0)
        XCTAssertEqual(reopened.keptBasis?.kind, .appearanceChoice)
        XCTAssertNil(reopened.keptAppearanceRecipe)
        XCTAssertEqual(reopened.naturalVariation, store.naturalVariation)
        XCTAssertEqual(reopened.history, store.history)
        XCTAssertEqual(try Data(contentsOf: url), saved)
    }

    @MainActor
    func testHandAuthoredLegacyV1V2V3LoadUnchangedAndMigrateOnlyOnExplicitSave() throws {
        for version in [1, 2, 3] {
            let url = temporarySave()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let legacy = try EvolutionLegacyTestData.data(version: version)
            try write(legacy, to: url)
            let store = EvolutionStore(saveURL: url)
            XCTAssertTrue(store.load(), "Valid legacy v\(version) remains readable")
            XCTAssertEqual(store.activeFamily, .lumen)
            XCTAssertEqual(store.usefulReceipts.count, 2)
            XCTAssertEqual(store.keptBasis?.kind, .usefulWork)
            XCTAssertEqual(store.practiceJourneyOriginDigest, version == 1 ? nil : origin)
            if version == 3 {
                XCTAssertEqual(store.keptAppearanceRecipe?.originDigest, origin)
                XCTAssertEqual(store.keptAppearanceRecipe?.role, .muse)
                XCTAssertEqual(store.keptAppearanceRecipe?.helpStyle, .exploratory)
                XCTAssertEqual(store.history.first?.appearanceRecipe, store.keptAppearanceRecipe)
            } else {
                XCTAssertNil(store.keptAppearanceRecipe, "Migration does not invent an old role-based recipe")
                XCTAssertTrue(store.history.allSatisfy { $0.appearanceRecipe == nil })
            }
            let history = store.history, recipe = store.keptAppearanceRecipe
            XCTAssertEqual(try Data(contentsOf: url), legacy)
            XCTAssertTrue(store.save())
            XCTAssertEqual(try jsonObject(Data(contentsOf: url))["schema"] as? String, EvolutionStore.schema)
            let reopened = EvolutionStore(saveURL: url)
            XCTAssertTrue(reopened.load())
            XCTAssertEqual(reopened.history, history)
            XCTAssertEqual(reopened.keptAppearanceRecipe, recipe)
        }
    }

    @MainActor
    func testLegacyRecipeReasonsRemainCapturedAfterPreferencesChangeAndNewChoiceArchivesThem() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try write(EvolutionLegacyTestData.data(), to: url)
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.load())
        let legacy = try XCTUnwrap(store.keptAppearanceRecipe), history = store.history
        store.confirmRole(.guardian)
        store.confirmHelpStyle(.concise)
        store.revoke(.family)
        XCTAssertEqual(store.activeAppearanceRecipe, legacy)
        XCTAssertEqual(store.history, history)
        XCTAssertEqual(legacy.traitExplanations.first(where: { $0.id == "role" })?.value, "Muse")
        XCTAssertTrue(store.save())
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.load())
        XCTAssertEqual(reopened.keptAppearanceRecipe, legacy)
        XCTAssertEqual(reopened.preferences.role, .guardian)
        reopened.confirmFamily(.lumen)
        let newChoice = try XCTUnwrap(reopened.proposeEvolution())
        XCTAssertEqual(newChoice.basis.kind, .appearanceChoice)
        XCTAssertNil(newChoice.appearanceRecipe)
        XCTAssertTrue(reopened.keepEvolution(newChoice))
        XCTAssertNil(reopened.keptAppearanceRecipe)
        XCTAssertEqual(reopened.history.first?.appearanceRecipe, legacy)
        XCTAssertNil(reopened.history.last?.appearanceRecipe)
    }

    @MainActor
    func testMalformedUnknownAndDuplicateNestedLegacyRecipePreserveStateAndFile() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let valid = try EvolutionLegacyTestData.data()
        try write(valid, to: url)
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.load())
        let pending = try XCTUnwrap(store.proposeEvolution()), before = Snapshot(store)
        let baseline = try jsonObject(valid)
        var corruptions: [Data] = []
        for (key, value) in [("version", 2 as Any), ("originDigest", origin.uppercased() as Any),
                             ("unexpected", "hidden data" as Any), ("helpStyle", "unknown" as Any),
                             ("basisKind", EvolutionProposalBasis.Kind.appearanceChoice.rawValue as Any)] {
            var object = baseline, recipe = try XCTUnwrap(baseline["keptAppearanceRecipe"] as? [String: Any])
            recipe[key] = value; object["keptAppearanceRecipe"] = recipe
            corruptions.append(try JSONSerialization.data(withJSONObject: object))
        }
        var changedHistory = baseline
        var history = try XCTUnwrap(changedHistory["history"] as? [[String: Any]])
        var historicalRecipe = try XCTUnwrap(history[0]["appearanceRecipe"] as? [String: Any])
        historicalRecipe["unexpected"] = "hidden history data"
        history[0]["appearanceRecipe"] = historicalRecipe; changedHistory["history"] = history
        corruptions.append(try JSONSerialization.data(withJSONObject: changedHistory))
        // Raw text preserves duplicates, including equivalent escaped key names.
        let compact = String(decoding: try JSONSerialization.data(withJSONObject: baseline, options: .sortedKeys), as: UTF8.self)
        corruptions.append(Data(compact.replacingOccurrences(of: "\"keptAppearanceRecipe\":{",
            with: "\"keptAppearanceRecipe\":{\"version\":1,").utf8))
        corruptions.append(Data(compact.replacingOccurrences(of: "\"appearanceRecipe\":{",
            with: "\"appearanceRecipe\":{\"vers\\u0069on\":1,").utf8))
        for invalid in corruptions {
            XCTAssertNotEqual(invalid, valid)
            try invalid.write(to: url)
            XCTAssertFalse(store.load())
            XCTAssertEqual(Snapshot(store), before)
            XCTAssertEqual(store.proposal, pending)
            XCTAssertTrue(store.requiresReplacement)
            XCTAssertFalse(store.save())
            XCTAssertEqual(Snapshot(store), before)
            XCTAssertEqual(try Data(contentsOf: url), invalid)
        }
    }

    @MainActor
    func testRebindingHidesLegacyRecipeAndNaturalVariationFollowsTheObservedIndividual() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try write(EvolutionLegacyTestData.data(), to: url)
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.load())
        let recipe = try XCTUnwrap(store.keptAppearanceRecipe), history = store.history
        let naturalA = try XCTUnwrap(store.naturalVariation)
        store.observeJourneyOrigin(otherOrigin)
        XCTAssertNil(store.activeAppearanceRecipe)
        XCTAssertEqual(store.keptAppearanceRecipe, recipe)
        XCTAssertEqual(store.naturalVariation?.originDigest, otherOrigin)
        XCTAssertNotEqual(store.naturalVariation, naturalA)
        XCTAssertTrue(store.bindPracticeJourney(otherOrigin))
        XCTAssertEqual(store.history, history)
        XCTAssertEqual(store.activeFamily, .lumen)
        XCTAssertTrue(store.save())
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.load())
        XCTAssertEqual(reopened.keptAppearanceRecipe, recipe)
        XCTAssertNil(reopened.activeAppearanceRecipe)
        XCTAssertEqual(reopened.naturalVariation?.originDigest, otherOrigin)
        reopened.observeJourneyOrigin(origin)
        XCTAssertEqual(reopened.naturalVariation, naturalA)
        XCTAssertNil(reopened.activeAppearanceRecipe, "Observation cannot rebind earlier personal history")
        XCTAssertTrue(reopened.bindPracticeJourney(origin))
        XCTAssertEqual(reopened.activeAppearanceRecipe, recipe)
        XCTAssertEqual(reopened.history, history)
    }

    @MainActor
    func testMaximumLegacyRecordsAndRecipeHistoryMigrateWithinTheSaveBudget() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let practices = (0..<8).map { index in
            PracticeEvolutionReference(originDigest: origin, eventId: "\(index):" + String(repeating: "e", count: 158),
                battleId: UUID(), rulesVersion: 1, rounds: 20, outcome: .lost,
                replayDigest: String(repeating: "c", count: 64), committedAt: "2026-09-06T18:00:00.123456789+00:00")
        }
        var object = try EvolutionLegacyTestData.object(practice: practices[0], historyCount: 32, receiptCount: 32)
        object["reviewedPractices"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(practices))
        let saved = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        XCTAssertLessThanOrEqual(saved.count, EvolutionStore.maximumSaveBytes)
        try write(saved, to: url)
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.load())
        XCTAssertEqual(store.history.count, 32)
        XCTAssertEqual(store.reviewedPractices.count, 8)
        XCTAssertEqual(store.usefulReceipts.count, 32)
        XCTAssertTrue(store.history.allSatisfy { $0.appearanceRecipe != nil })
        XCTAssertTrue(store.save(), store.status)
        XCTAssertLessThanOrEqual(try Data(contentsOf: url).count, EvolutionStore.maximumSaveBytes)
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.load())
        XCTAssertEqual(reopened.history, store.history)
        XCTAssertEqual(reopened.reviewedPractices, store.reviewedPractices)
        XCTAssertEqual(reopened.keptAppearanceRecipe, store.keptAppearanceRecipe)
    }

    private struct Snapshot: Equatable {
        let preferences: EvolutionPreferences
        let receipts: [EvolutionUsefulReceipt]
        let binding: String?
        let practices: [PracticeEvolutionReference]
        let basis: EvolutionProposalBasis?
        let recipe: CompanionAppearanceRecipe?
        let active: EvolutionFamily?
        let history: [EvolutionHistoryEntry]
        let proposal: EvolutionProposal?
        let revision: UInt64
        @MainActor init(_ store: EvolutionStore) {
            preferences = store.preferences; receipts = store.usefulReceipts; binding = store.practiceJourneyOriginDigest
            practices = store.reviewedPractices; basis = store.keptBasis; recipe = store.keptAppearanceRecipe
            active = store.activeFamily; history = store.history; proposal = store.proposal; revision = store.revision
        }
    }
    private func temporarySave() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ARCHi-individual-evolution-\(UUID().uuidString)")
            .appendingPathComponent("evolution.json")
    }
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

/// Historical archives are authored independently of today's proposal flow.
/// This keeps migration checks capable of detecting accidental legacy rewrites.
enum EvolutionLegacyTestData {
    static func data(version: Int = 3, practice: PracticeEvolutionReference? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: object(version: version, practice: practice), options: .sortedKeys)
    }
    static func object(version: Int = 3, practice: PracticeEvolutionReference? = nil,
                       historyCount: Int = 1, receiptCount: Int = 2) throws -> [String: Any] {
        let origin = String(repeating: "a", count: 64)
        let kind = practice == nil ? "useful-work/v1" : "first-completed-practice/v1"
        let recipe: [String: Any] = ["version": 1, "originDigest": origin, "family": "lumen", "role": "muse",
                                     "helpStyle": "exploratory", "basisKind": kind]
        var history: [[String: Any]] = (0..<historyCount).map { index in
            ["kind": "kept", "family": "lumen", "id": String(format: "10000000-0000-0000-0000-%012d", index)]
        }
        if version >= 3 { for index in history.indices { history[index]["appearanceRecipe"] = recipe } }
        var object: [String: Any] = ["schema": "archi-companion-evolution/v\(version)",
            "origin": CompanionForm.companion.rawValue, "role": "muse", "helpStyle": "exploratory",
            "family": "lumen", "activeFamily": "lumen", "history": history,
            "usefulReceipts": (0..<receiptCount).map { index in
                ["requestID": String(format: "20000000-0000-0000-0000-%012d", index), "sourceDigest": origin]
            }]
        if version >= 2 {
            object["practiceJourneyOriginDigest"] = origin
            object["reviewedPractices"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(practice.map { [$0] } ?? []))
            var basis: [String: Any] = ["kind": kind]
            if let practice { basis["practice"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(practice)) }
            object["keptBasis"] = basis
        }
        if version >= 3 { object["keptAppearanceRecipe"] = recipe }
        return object
    }
}
