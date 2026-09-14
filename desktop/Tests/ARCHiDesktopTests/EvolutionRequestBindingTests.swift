import Foundation
import XCTest
@testable import ARCHiDesktop

final class EvolutionRequestBindingTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)
    private let input = String(repeating: "b", count: 64)
    private let lesson = LessonSnapshot(id: "11111111-1111-1111-1111-111111111111", revision: 1,
        topic: "planning", text: "Begin with one concrete next action.")

    func testContextBindingChangesForEveryOwnedContextDimensionAndContainsNoContent() throws {
        let original = lane()
        let binding = EvolutionRequestBinding(receipt: original)
        XCTAssertTrue(binding.isValid)
        XCTAssertEqual(binding.inputDigest, original.inputDigest)
        for context in [ContextTicket(generation: 2, placement: 1, source: 1, selection: 1),
                        ContextTicket(generation: 1, placement: 2, source: 1, selection: 1),
                        ContextTicket(generation: 1, placement: 1, source: 2, selection: 1),
                        ContextTicket(generation: 1, placement: 1, source: 1, selection: 2)] {
            XCTAssertNotEqual(binding.contextDigest, EvolutionRequestBinding(receipt: lane(context: context)).contextDigest)
        }
        let data = try JSONEncoder().encode(binding)
        XCTAssertEqual(Set(try object(data).keys), ["inputDigest", "contextDigest"])
        XCTAssertEqual(try JSONDecoder().decode(EvolutionRequestBinding.self, from: data), binding)
    }

    @MainActor
    func testSameRequestCannotBeRelabeledWithDifferentInputOrContext() throws {
        let store = EvolutionStore(), original = lane()
        XCTAssertTrue(store.markUseful(receipt: original, sourceDigest: nil))
        let before = store.usefulReceipts
        for changed in [lane(id: original.requestID, input: digest),
                        lane(id: original.requestID, context: ContextTicket(generation: 2, placement: 1, source: 1, selection: 1))] {
            XCTAssertFalse(store.markUseful(receipt: changed, sourceDigest: nil, confirmedLesson: lesson))
        }
        XCTAssertEqual(store.usefulReceipts, before)
        XCTAssertTrue(store.markUseful(receipt: original, sourceDigest: nil, confirmedLesson: lesson))
        XCTAssertEqual(store.usefulReceipts.count, 1)
        XCTAssertEqual(store.usefulReceipts.first?.requestBinding, before.first?.requestBinding)
    }

    func testMissingMalformedAndAmbiguousConversationEvidenceIsRejected() throws {
        let valid = EvolutionUsefulReceipt(requestID: UUID(), sourceDigest: nil,
            requestBinding: EvolutionRequestBinding(receipt: lane()), lessonUse: EvolutionLessonUse.make(snapshot: lesson))
        let bytes = try JSONEncoder().encode(valid), base = try object(bytes)
        XCTAssertNil(base["sourceDigest"])
        XCTAssertEqual(try JSONDecoder().decode(EvolutionUsefulReceipt.self, from: bytes), valid)
        var variants: [[String: Any]] = []
        for (key, value) in [("sourceDigest", NSNull() as Any), ("sourceDigest", "not-a-document"),
                             ("requestBinding", NSNull()), ("text", "Do not retain the prompt")] {
            var fields = base; fields[key] = value; variants.append(fields)
        }
        var missing = base; missing.removeValue(forKey: "requestBinding"); variants.append(missing)
        let binding = try XCTUnwrap(base["requestBinding"] as? [String: Any])
        for (key, value) in [("inputDigest", "bad"), ("contextDigest", "bad"), ("unrecognized", "bad")] {
            var fields = base, invalid = binding; invalid[key] = value; fields["requestBinding"] = invalid; variants.append(fields)
        }
        for fields in variants {
            XCTAssertThrowsError(try JSONDecoder().decode(EvolutionUsefulReceipt.self,
                from: JSONSerialization.data(withJSONObject: fields)))
        }
    }

    @MainActor
    func testV6GrowthMigratesWithoutInventingInputBindingOrRewritingOnLoad() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = EvolutionStore(saveURL: url)
        XCTAssertTrue(original.save())
        var saved = try object(Data(contentsOf: url))
        let historical = EvolutionUsefulReceipt(requestID: UUID(), sourceDigest: digest,
            lessonUse: try XCTUnwrap(EvolutionLessonUse.make(snapshot: lesson)))
        let growth = KinGrowthRecord(originDigest: digest, active: true, receipt: historical)
        XCTAssertEqual(growth.version, 1)
        saved["schema"] = "archi-companion-evolution/v6"
        saved["usefulReceipts"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([historical]))
        saved["kinGrowthRecord"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(growth))
        let oldBytes = try JSONSerialization.data(withJSONObject: saved, options: .sortedKeys)
        try oldBytes.write(to: url)
        let migrated = EvolutionStore(saveURL: url)
        XCTAssertTrue(migrated.load(), migrated.status)
        XCTAssertEqual(migrated.usefulReceipts, [historical])
        XCTAssertEqual(migrated.kinGrowthRecord, growth)
        XCTAssertNil(migrated.usefulReceipts.first?.requestBinding)
        XCTAssertTrue(migrated.usefulReceipts.first?.evidenceTitle.contains("historical") == true)
        XCTAssertEqual(try Data(contentsOf: url), oldBytes)
        // Even a matching source cannot manufacture a missing historical input.
        var fresh = lane(id: historical.requestID.uuidString)
        fresh.sourceDigest = digest
        XCTAssertFalse(migrated.markUseful(receipt: fresh, sourceDigest: digest, confirmedLesson: lesson))
        XCTAssertTrue(migrated.save(), migrated.status)
        XCTAssertEqual(try object(Data(contentsOf: url))["schema"] as? String, EvolutionStore.schema)
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.load(), reopened.status)
        XCTAssertEqual(reopened.kinGrowthRecord, growth)
        XCTAssertEqual(reopened.usefulReceipts, [historical])
    }

    @MainActor
    func testV1ThroughV6ContinueAcceptingUppercaseHistoricalSourceFingerprints() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for version in 1...6 {
            var fields = try object(EvolutionLegacyTestData.data(version: min(version, 4)))
            fields["schema"] = "archi-companion-evolution/v\(version)"
            if version == 6 { fields["kinGrowthRecord"] = NSNull() }
            var rows = try XCTUnwrap(fields["usefulReceipts"] as? [[String: Any]])
            for index in rows.indices { rows[index]["sourceDigest"] = digest.uppercased() }
            fields["usefulReceipts"] = rows
            let bytes = try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)
            try bytes.write(to: url)
            let store = EvolutionStore(saveURL: url)
            XCTAssertTrue(store.load(), "v\(version): \(store.status)")
            XCTAssertTrue(store.usefulReceipts.allSatisfy { $0.sourceDigest == digest && $0.requestBinding == nil })
            XCTAssertEqual(try Data(contentsOf: url), bytes, "Load never rewrites legacy bytes")
            XCTAssertTrue(store.save(), store.status)
            let reopened = EvolutionStore(saveURL: url)
            XCTAssertTrue(reopened.load(), reopened.status)
            XCTAssertEqual(reopened.usefulReceipts, store.usefulReceipts)
        }
    }

    @MainActor
    func testOldSchemaCannotSmuggleConversationBindingAndBadV7LoadPreservesSession() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.markUseful(receipt: lane(), sourceDigest: nil, confirmedLesson: lesson))
        XCTAssertTrue(store.save(), store.status)
        let accepted = store.usefulReceipts, revision = store.revision
        let base = try object(Data(contentsOf: url))
        for schema in ["archi-companion-evolution/v5", "archi-companion-evolution/v6"] {
            var invalid = base; invalid["schema"] = schema
            if schema.hasSuffix("v5") { invalid.removeValue(forKey: "kinGrowthRecord") }
            let bytes = try JSONSerialization.data(withJSONObject: invalid)
            try bytes.write(to: url)
            XCTAssertFalse(store.load(), schema)
            XCTAssertEqual(store.usefulReceipts, accepted)
            XCTAssertEqual(store.revision, revision)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    @MainActor
    func testPersistenceHoldAndAbsentRestorePreserveFileBoundaries() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(origin: .particle, saveURL: url)
        store.confirmRole(.muse)
        XCTAssertTrue(store.save())
        let saved = try Data(contentsOf: url)
        store.confirmRole(.keeper)
        let retained = store.preferences
        store.persistenceBlockedReason = "A profile restore needs recovery."
        XCTAssertFalse(store.save())
        XCTAssertFalse(store.load())
        XCTAssertFalse(store.forget())
        XCTAssertFalse(store.loadRestoredProfile())
        XCTAssertEqual(store.preferences, retained)
        XCTAssertEqual(try Data(contentsOf: url), saved)
        store.persistenceBlockedReason = nil
        XCTAssertTrue(store.loadRestoredProfile())
        XCTAssertEqual(store.preferences.role, .muse)
        // Simulate an already validated, explicitly absent restored member.
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(store.loadRestoredProfile(origin: .light))
        XCTAssertEqual(store.origin, .light)
        XCTAssertEqual(store.preferences.confirmedCount, 0)
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertFalse(store.hasKnownSavedBaseline)
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func lane(id: String = UUID().uuidString, input: String? = nil,
                      context: ContextTicket = ContextTicket(generation: 1, placement: 1, source: 1, selection: 1)) -> AssistantLaneReceipt {
        var result = AssistantLaneReceipt(requestID: id, route: .local, provider: .qwen,
            context: context, inputDigest: input ?? self.input, inputContract: AssistantRequest.inputContract,
            deadline: .distantFuture, modelIdentity: "synthetic-binding-fixture", state: .complete)
        result.localLessons = [lesson]; result.usedLessonIDs = [lesson.modelID]
        return result
    }
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("archi-evolution-binding-\(UUID())")
            .appendingPathComponent("evolution.json")
    }
    private func object(_ bytes: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }
}
