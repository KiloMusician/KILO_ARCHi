import Foundation
import XCTest
@testable import ARCHiDesktop

final class CompanionEvolutionTests: XCTestCase {
    @MainActor
    func testAnAppearanceChoiceNeedsOnlyASelectedFamilyAndNoWorkQuota() async throws {
        let store = EvolutionStore()
        XCTAssertNil(store.proposeEvolution())
        store.confirmFamily(.lumen)
        let proposal = try XCTUnwrap(store.proposeEvolution())
        XCTAssertEqual(proposal.family, .lumen)
        XCTAssertEqual(proposal.preferences, store.preferences)
        XCTAssertNil(proposal.preferences.role)
        XCTAssertNil(proposal.preferences.helpStyle)
        XCTAssertTrue(proposal.evidence.isEmpty)
        XCTAssertEqual(proposal.basis.kind, .appearanceChoice)
        XCTAssertNil(proposal.basis.practice)
        XCTAssertNil(proposal.appearanceRecipe)
        XCTAssertEqual(proposal.revision, store.revision)
        XCTAssertNil(store.activeFamily)
        XCTAssertTrue(store.keepEvolution(proposal))
        XCTAssertEqual(store.activeFamily, .lumen)
    }

    @MainActor
    func testRepeatedAndCompareLaneReceiptsCountOnceAndUnfinishedOrInvalidReceiptsNeverCount() async throws {
        let store = EvolutionStore(), id = UUID()
        XCTAssertTrue(store.markUseful(receipt: receipt(id: id), sourceDigest: digest))
        XCTAssertFalse(store.markUseful(receipt: receipt(id: id), sourceDigest: digest))
        XCTAssertFalse(store.markUseful(receipt: receipt(id: id, provider: .codex), sourceDigest: digest))
        for state in [AssistantLaneState.pending, .failed, .cancelled] {
            XCTAssertFalse(store.markUseful(receipt: receipt(state: state), sourceDigest: digest))
        }
        var invalid = receipt()
        invalid.sourceDigest = nil
        XCTAssertFalse(store.markUseful(receipt: invalid, sourceDigest: digest))
        XCTAssertFalse(store.markUseful(receipt: receipt(), sourceDigest: String(repeating: "b", count: 64)))
        XCTAssertFalse(store.markUseful(receipt: receipt(), sourceDigest: "raw source text"))
        let invalidID = AssistantLaneReceipt(requestID: "not-a-uuid", route: .local, provider: .qwen,
            context: ticket, inputDigest: digest, sourceDigest: digest, inputContract: "native-assistant-input/v1",
            deadline: .distantFuture, modelIdentity: nil, state: .complete)
        XCTAssertFalse(store.markUseful(receipt: invalidID, sourceDigest: digest))
        XCTAssertEqual(store.usefulReceipts.count, 1)
        XCTAssertEqual(store.usefulReceipts[0].requestID, id)
    }

    @MainActor
    func testReceiptBudgetDoesNotEvictHistoryOrInflateTheCount() async throws {
        let store = EvolutionStore()
        for _ in 0..<32 { XCTAssertTrue(store.markUseful(receipt: receipt(), sourceDigest: digest)) }
        let retained = store.usefulReceipts, revision = store.revision
        XCTAssertFalse(store.markUseful(receipt: receipt(), sourceDigest: digest))
        XCTAssertEqual(store.usefulReceipts, retained)
        XCTAssertEqual(store.revision, revision)
        store.withdrawUseful(requestID: retained[0].requestID)
        XCTAssertTrue(store.markUseful(receipt: receipt(), sourceDigest: digest))
        XCTAssertEqual(store.usefulReceipts.count, 32)
    }

    @MainActor
    func testFreeExplorationAddsNoEvidenceAndCannotKeepADifferentFamily() async throws {
        let store = EvolutionStore()
        for family in EvolutionFamily.allCases {
            store.preview(family)
            XCTAssertEqual(store.previewFamily, family)
            XCTAssertNil(store.activeFamily)
            XCTAssertFalse(store.keepEvolution())
        }
        XCTAssertEqual(store.revision, 0)
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertTrue(store.reviewedPractices.isEmpty)
        qualify(store)
        let lumen = try XCTUnwrap(store.proposeEvolution())
        store.preview(.frame)
        XCTAssertNil(store.proposal, "The visible preview cannot keep an older, different candidate")
        XCTAssertFalse(store.keepEvolution(lumen))
        XCTAssertEqual(store.confirmedFamily, .lumen)
        XCTAssertNil(store.activeFamily)
        let fresh = try XCTUnwrap(store.proposeEvolution())
        XCTAssertEqual(store.previewFamily, .lumen)
        XCTAssertTrue(store.keepEvolution(fresh))
        XCTAssertEqual(store.activeFamily, .lumen)
    }

    @MainActor
    func testPreferenceEditRevokeRestoreAndSecondProposalFenceEarlierCandidates() async throws {
        let store = EvolutionStore()
        qualify(store)
        let first = try XCTUnwrap(store.proposeEvolution())
        store.confirmHelpStyle(.reflective)
        store.confirmHelpStyle(.exploratory)
        XCTAssertFalse(store.keepEvolution(first), "Restoring identical choices cannot restore the old revision")
        let second = try XCTUnwrap(store.proposeEvolution())
        store.revoke(.role)
        store.confirmRole(.muse)
        XCTAssertFalse(store.keepEvolution(second))
        let third = try XCTUnwrap(store.proposeEvolution())
        let fourth = try XCTUnwrap(store.proposeEvolution())
        XCTAssertFalse(store.keepEvolution(third))
        XCTAssertTrue(store.keepEvolution(fourth))
        XCTAssertFalse(store.keepEvolution(fourth), "Keep consumes its proposal")
        let fifth = try XCTUnwrap(store.proposeEvolution())
        store.dismissPreview()
        XCTAssertFalse(store.keepEvolution(fifth))
    }

    @MainActor
    func testEvidenceAndPreferenceChangesNeverDemoteAKeptBody() async throws {
        for category in [EvolutionPreferenceCategory?.none, .some(.role), .some(.helpStyle), .some(.family)] {
            let store = EvolutionStore(origin: .ink)
            qualify(store)
            XCTAssertNotNil(store.proposeEvolution())
            XCTAssertTrue(store.keepEvolution())
            let stale = try XCTUnwrap(store.proposeEvolution())
            if let category { store.revoke(category) }
            else { store.withdrawUseful(requestID: store.usefulReceipts[0].requestID) }
            XCTAssertFalse(store.keepEvolution(stale))
            XCTAssertEqual(store.activeFamily, .lumen)
            XCTAssertEqual(store.origin, .ink)
            XCTAssertEqual(store.history.last?.kind, .kept)
        }
        let store = EvolutionStore()
        qualify(store)
        XCTAssertTrue(store.markUseful(receipt: receipt(), sourceDigest: digest))
        XCTAssertNotNil(store.proposeEvolution()); XCTAssertTrue(store.keepEvolution())
        store.withdrawUseful(requestID: store.usefulReceipts[0].requestID)
        XCTAssertEqual(store.activeFamily, .lumen, "Feedback counts do not determine the kept body")
        store.confirmFamily(.veil)
        XCTAssertEqual(store.activeFamily, .lumen, "A new selected family needs its own explicit Keep")
        let next = try XCTUnwrap(store.proposeEvolution())
        XCTAssertTrue(store.keepEvolution(next))
        XCTAssertEqual(store.activeFamily, .veil)
    }

    @MainActor
    func testReturnAndForgetPreserveStarterOriginAndForgetRemovesAllEvidence() async throws {
        let store = EvolutionStore(origin: .pixel)
        qualify(store)
        XCTAssertNotNil(store.proposeEvolution()); XCTAssertTrue(store.keepEvolution())
        store.returnToStarter()
        XCTAssertNil(store.activeFamily)
        XCTAssertEqual(store.origin, .pixel)
        XCTAssertNotNil(store.proposeEvolution(), "Returning to a starter does not create a new task quota")
        let stale = try XCTUnwrap(store.proposeEvolution())
        XCTAssertTrue(store.forget())
        XCTAssertFalse(store.keepEvolution(stale))
        XCTAssertEqual(store.origin, .pixel)
        XCTAssertEqual(store.preferences.confirmedCount, 0)
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertNil(store.previewFamily)
        XCTAssertNil(store.activeFamily)
    }

    @MainActor
    func testSaveAndLoadAreExplicitAndLaterEditsRemainDirtyUntilSaved() async throws {
        let url = try saveURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(origin: .ribbon, saveURL: url)
        qualify(store)
        XCTAssertNotNil(store.proposeEvolution()); XCTAssertTrue(store.keepEvolution())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertTrue(store.save())
        let bytes = try Data(contentsOf: url)
        XCTAssertFalse(store.hasUnsavedChanges)
        let reopened = EvolutionStore(origin: .ribbon, saveURL: url)
        XCTAssertNil(reopened.activeFamily, "Constructing the store does not load saved data")
        XCTAssertTrue(reopened.usefulReceipts.isEmpty)
        XCTAssertTrue(reopened.load())
        XCTAssertEqual(reopened.origin, .ribbon)
        XCTAssertEqual(reopened.activeFamily, .lumen)
        XCTAssertEqual(reopened.preferences, store.preferences)
        XCTAssertEqual(reopened.usefulReceipts, store.usefulReceipts)
        XCTAssertNil(reopened.proposal)
        XCTAssertNil(reopened.previewFamily)
        let stale = try XCTUnwrap(reopened.proposeEvolution())
        reopened.confirmRole(.guardian)
        XCTAssertTrue(reopened.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(reopened.load())
        XCTAssertFalse(reopened.keepEvolution(stale))
        XCTAssertEqual(reopened.confirmedRole, .muse)
        reopened.confirmRole(.guardian)
        XCTAssertTrue(reopened.save())
        XCTAssertNotEqual(try Data(contentsOf: url), bytes)
        XCTAssertFalse(reopened.hasUnsavedChanges)
    }

    @MainActor
    func testMalformedUnknownOversizedAndUnsupportedSavesPreserveCurrentSessionAndBytes() async throws {
        let url = try saveURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(saveURL: url)
        qualify(store)
        XCTAssertNotNil(store.proposeEvolution()); XCTAssertTrue(store.keepEvolution()); XCTAssertTrue(store.save())
        let valid = try Data(contentsOf: url)
        let source = try XCTUnwrap(try JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var cases: [Data] = [Data([0xff, 0xfe]), Data(repeating: 32, count: EvolutionStore.maximumSaveBytes + 1)]
        func mutated(_ edit: (inout [String: Any]) -> Void) throws -> Data {
            var object = source; edit(&object)
            return try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        }
        cases.append(try mutated { $0["schema"] = "archi-companion-evolution/v999" })
        cases.append(try mutated { $0["origin"] = "Unknown starter" })
        cases.append(try mutated { $0["permission"] = true })
        cases.append(try mutated { $0["role"] = "administrator" })
        cases.append(try mutated { $0.removeValue(forKey: "family") })
        cases.append(try mutated { object in
            var records = object["usefulReceipts"] as! [[String: Any]]
            records[0]["sourceDigest"] = "not-a-digest"; object["usefulReceipts"] = records
        })
        cases.append(try mutated { object in
            var records = object["usefulReceipts"] as! [[String: Any]]
            records[0]["reply"] = "A private reply must never be retained"; object["usefulReceipts"] = records
        })
        cases.append(try mutated { object in
            let records = object["usefulReceipts"] as! [[String: Any]]
            object["usefulReceipts"] = [records[0], records[0]]
        })
        cases.append(try mutated {
            $0["schema"] = "archi-companion-evolution/v1"
            $0.removeValue(forKey: "practiceJourneyOriginDigest")
            $0.removeValue(forKey: "reviewedPractices")
            $0.removeValue(forKey: "keptBasis")
            $0.removeValue(forKey: "keptAppearanceRecipe")
            var history = $0["history"] as! [[String: Any]]
            for index in history.indices { history[index].removeValue(forKey: "appearanceRecipe") }
            $0["history"] = history
            $0["usefulReceipts"] = []
        })
        cases.append(try mutated { $0["history"] = [] })
        let text = try XCTUnwrap(String(data: valid, encoding: .utf8))
        cases.append(Data(text.replacingOccurrences(of: "{", with: "{\"schema\":\"archi-companion-evolution/v1\",", range: text.startIndex..<text.index(after: text.startIndex)).utf8))
        cases.append(Data(text.replacingOccurrences(of: "{", with: "{\"\\u0073chema\":\"archi-companion-evolution/v1\",", range: text.startIndex..<text.index(after: text.startIndex)).utf8))
        let preferences = store.preferences, evidence = store.usefulReceipts, history = store.history, origin = store.origin
        for invalid in cases {
            try invalid.write(to: url)
            XCTAssertFalse(store.load())
            XCTAssertEqual(store.preferences, preferences)
            XCTAssertEqual(store.usefulReceipts, evidence)
            XCTAssertEqual(store.history, history)
            XCTAssertEqual(store.origin, origin)
            XCTAssertEqual(store.activeFamily, .lumen)
            XCTAssertEqual(try Data(contentsOf: url), invalid)
            XCTAssertTrue(store.requiresReplacement)
            XCTAssertFalse(store.save())
            XCTAssertEqual(try Data(contentsOf: url), invalid)
        }
    }

    @MainActor
    func testInvalidSaveNeedsExplicitReplacementAndCanBeForgottenWithoutDecoding() async throws {
        let url = try saveURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let invalid = Data("{malformed saved state".utf8)
        try invalid.write(to: url)
        let store = EvolutionStore(saveURL: url)
        qualify(store)
        XCTAssertFalse(store.save())
        XCTAssertEqual(try Data(contentsOf: url), invalid)
        XCTAssertTrue(store.save(replacingInvalidFile: true))
        XCTAssertFalse(store.requiresReplacement)
        XCTAssertTrue(store.load())
        try invalid.write(to: url)
        XCTAssertTrue(store.forget(), "Explicit Forget deletes malformed saves without treating them as valid")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertFalse(store.requiresReplacement)
    }

    @MainActor
    func testForgetDeletionFailureClearsSessionButReportsThatSavedDataRemains() async throws {
        let url = try saveURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(saveURL: url, deleteFile: { _ in throw CocoaError(.fileWriteNoPermission) })
        qualify(store)
        XCTAssertNotNil(store.proposeEvolution()); XCTAssertTrue(store.keepEvolution()); XCTAssertTrue(store.save())
        let bytes = try Data(contentsOf: url)
        let stale = try XCTUnwrap(store.proposeEvolution())
        XCTAssertFalse(store.forget())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertNil(store.activeFamily)
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertFalse(store.keepEvolution(stale))
        XCTAssertTrue(store.requiresReplacement)
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertTrue(store.load(), "The error was honest: an explicit Load can still recover undeleted data")
        XCTAssertEqual(store.activeFamily, .lumen)
    }

    @MainActor
    func testForgetPreservesDirectoryContentsAtTheSaveLocation() async throws {
        let url = try saveURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let child = url.appendingPathComponent("unrelated.txt"), contents = Data("Keep this unrelated file.".utf8)
        try contents.write(to: child)
        let store = EvolutionStore(saveURL: url)
        qualify(store)
        XCTAssertFalse(store.load())
        XCTAssertFalse(store.save(replacingInvalidFile: true))
        XCTAssertFalse(store.forget())
        XCTAssertEqual(try Data(contentsOf: child), contents)
        XCTAssertTrue(store.requiresReplacement)
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertTrue(store.status.contains("could not be deleted"))
    }

    @MainActor
    func testDanglingSymlinkIsProtectedFromOrdinarySaveAndExplicitlyForgotten() async throws {
        let url = try saveURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let missing = url.deletingLastPathComponent().appendingPathComponent("missing-target.json")
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: missing)
        let store = EvolutionStore(saveURL: url)
        XCTAssertFalse(store.load())
        XCTAssertFalse(store.save())
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), missing.path)
        XCTAssertTrue(store.forget())
        XCTAssertThrowsError(try FileManager.default.attributesOfItem(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    @MainActor
    func testSavedPayloadContainsOnlyBoundedCosmeticMetadataAndKeepsOrigin() async throws {
        let url = try saveURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(origin: .light, saveURL: url)
        qualify(store)
        for _ in 0..<40 {
            XCTAssertNotNil(store.proposeEvolution()); XCTAssertTrue(store.keepEvolution())
            store.returnToStarter()
        }
        XCTAssertEqual(store.history.count, 32)
        XCTAssertTrue(store.save())
        let bytes = try Data(contentsOf: url)
        XCTAssertLessThanOrEqual(bytes.count, EvolutionStore.maximumSaveBytes)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schema", "origin", "role", "helpStyle", "family", "activeFamily", "usefulReceipts", "history",
            "practiceJourneyOriginDigest", "reviewedPractices", "keptBasis", "keptAppearanceRecipe"])
        let rows = try XCTUnwrap(object["usefulReceipts"] as? [[String: Any]])
        XCTAssertTrue(rows.allSatisfy { Set($0.keys) == ["requestID", "sourceDigest"] })
        XCTAssertEqual(object["origin"] as? String, "Guide light")
        let differentOrigin = EvolutionStore(origin: .ink, saveURL: url)
        XCTAssertEqual(differentOrigin.origin, .ink)
        XCTAssertTrue(differentOrigin.load(), "Changing ordinary starter preferences does not make the evolution save unreadable")
        XCTAssertEqual(differentOrigin.origin, .light, "Explicit Load restores the saved cosmetic starting form")
        differentOrigin.returnToStarter()
        XCTAssertEqual(differentOrigin.origin, .light)
        XCTAssertNil(differentOrigin.activeFamily)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    private var digest: String { String(repeating: "a", count: 64) }
    private var ticket: ContextTicket { ContextTicket(generation: 1, placement: 2, source: 3, selection: 4) }
    private func receipt(id: UUID = UUID(), provider: AssistantProvider = .qwen,
                         state: AssistantLaneState = .complete) -> AssistantLaneReceipt {
        AssistantLaneReceipt(requestID: id.uuidString, route: .compare, provider: provider, context: ticket,
            inputDigest: digest, sourceDigest: digest, inputContract: "native-assistant-input/v1",
            deadline: .distantFuture, modelIdentity: nil, state: state)
    }
    @MainActor
    private func qualify(_ store: EvolutionStore) {
        store.confirmRole(.muse); store.confirmHelpStyle(.exploratory); store.confirmFamily(.lumen)
        XCTAssertTrue(store.markUseful(receipt: receipt(), sourceDigest: digest))
        XCTAssertTrue(store.markUseful(receipt: receipt(), sourceDigest: digest))
    }
    private func saveURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-evolution-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("evolution.json")
    }
}
