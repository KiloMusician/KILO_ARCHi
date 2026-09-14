import Foundation
import XCTest
@testable import ARCHiDesktop

final class EvolutionLessonUseTests: XCTestCase {
    private let sourceDigest = String(repeating: "a", count: 64)
    private let lesson = LessonSnapshot(id: "11111111-1111-1111-1111-111111111111", revision: 2,
        topic: "Project planning", text: "Start with a brief outline.")

    func testReferenceHashesTheExactSnapshotAndStoresNoLessonContent() throws {
        let reference = try XCTUnwrap(EvolutionLessonUse.make(snapshot: lesson))
        XCTAssertEqual(reference.lessonID, lesson.id)
        XCTAssertEqual(reference.lessonRevision, 2)
        XCTAssertEqual(reference.snapshotDigest, "ade5ba15ee1ffd5d682bc51213e64158ef170e5ac0bc30862d9eb0e7976aec00")
        XCTAssertEqual(reference, EvolutionLessonUse.make(snapshot: lesson))
        XCTAssertTrue(reference.matches(snapshot: lesson))
        for changed in [
            LessonSnapshot(id: lesson.id, revision: 3, topic: lesson.topic, text: lesson.text),
            LessonSnapshot(id: lesson.id, revision: 2, topic: "Other topic", text: lesson.text),
            LessonSnapshot(id: lesson.id, revision: 2, topic: lesson.topic, text: "Start with a full draft."),
            LessonSnapshot(id: lesson.id, revision: 2, topic: lesson.topic, text: lesson.text,
                source: LessonSource(name: "Private source name", digest: sourceDigest)),
            LessonSnapshot(id: UUID().uuidString, revision: 2, topic: lesson.topic, text: lesson.text)
        ] { XCTAssertFalse(reference.matches(snapshot: changed)) }
        let bytes = try JSONEncoder().encode(reference)
        let fields = try object(bytes)
        XCTAssertEqual(Set(fields.keys), ["lessonID", "lessonRevision", "snapshotDigest"])
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertFalse(text.contains(lesson.topic))
        XCTAssertFalse(text.contains(lesson.text))
        XCTAssertEqual(try JSONDecoder().decode(EvolutionLessonUse.self, from: bytes), reference)
    }

    func testInvalidSnapshotsAndMalformedReferenceFieldsAreRejected() throws {
        for snapshot in [
            LessonSnapshot(id: "not-a-uuid", revision: 1, topic: lesson.topic, text: lesson.text),
            LessonSnapshot(id: lesson.id, revision: 0, topic: lesson.topic, text: lesson.text),
            LessonSnapshot(id: lesson.id, revision: 1, topic: "", text: lesson.text),
            LessonSnapshot(id: lesson.id, revision: 1, topic: lesson.topic, text: " ")
        ] { XCTAssertNil(EvolutionLessonUse.make(snapshot: snapshot)) }
        let valid = try object(JSONEncoder().encode(XCTUnwrap(EvolutionLessonUse.make(snapshot: lesson))))
        var variants: [[String: Any]] = []
        for (key, value) in [("lessonID", "bad" as Any), ("lessonRevision", 0), ("lessonRevision", -1),
                             ("lessonRevision", true), ("lessonRevision", 1.5), ("lessonRevision", "2"),
                             ("snapshotDigest", String(repeating: "A", count: 64)), ("snapshotDigest", "abc"),
                             ("text", "must not be retained")] {
            var fields = valid; fields[key] = value; variants.append(fields)
        }
        var missing = valid; missing.removeValue(forKey: "lessonRevision"); variants.append(missing)
        var null = valid; null["snapshotDigest"] = NSNull(); variants.append(null)
        for fields in variants {
            XCTAssertThrowsError(try JSONDecoder().decode(EvolutionLessonUse.self,
                from: JSONSerialization.data(withJSONObject: fields)), "\(fields)")
        }
    }

    @MainActor
    func testConfirmationRequiresCompletedQwenCapturedSnapshotAndReportedUse() throws {
        let store = EvolutionStore()
        var invalid: [AssistantLaneReceipt] = []
        for state in [AssistantLaneState.pending, .failed, .cancelled] {
            var candidate = receipt(); candidate.state = state; invalid.append(candidate)
        }
        invalid.append(receipt(provider: .codex))
        var absent = receipt(); absent.localLessons = []; invalid.append(absent)
        var notUsed = receipt(); notUsed.usedLessonIDs = []; invalid.append(notUsed)
        var differentVersion = receipt()
        differentVersion.usedLessonIDs = ["kept-\(lesson.id)-r1"]; invalid.append(differentVersion)
        var differentSnapshot = receipt()
        differentSnapshot.localLessons = [LessonSnapshot(id: lesson.id, revision: lesson.revision,
            topic: lesson.topic, text: "An unconfirmed replacement.")]
        invalid.append(differentSnapshot)
        var noSource = receipt(); noSource.sourceDigest = nil; invalid.append(noSource)
        invalid.append(receipt(source: String(repeating: "b", count: 64)))
        for candidate in invalid {
            XCTAssertFalse(store.markUseful(receipt: candidate, sourceDigest: sourceDigest, confirmedLesson: lesson))
        }
        XCTAssertFalse(store.markUseful(receipt: receipt(), sourceDigest: "source text", confirmedLesson: lesson))
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertEqual(store.revision, 0)
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertTrue(store.markUseful(receipt: receipt(), sourceDigest: sourceDigest, confirmedLesson: lesson))
        XCTAssertEqual(store.usefulReceipts.count, 1)
        XCTAssertEqual(store.usefulReceipts[0].lessonUse, EvolutionLessonUse.make(snapshot: lesson))
        XCTAssertNil(store.activeFamily)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertNil(store.proposeEvolution(), "Lesson feedback does not choose or unlock a body")
    }

    @MainActor
    func testPlainRecordCanBeAnnotatedOnceWithoutCountingCompareTwiceOrReplacingItsSource() throws {
        let store = EvolutionStore(), id = UUID()
        let local = receipt(id: id)
        XCTAssertTrue(store.markUseful(receipt: receipt(id: id, provider: .codex), sourceDigest: sourceDigest))
        XCTAssertNil(store.usefulReceipts[0].lessonUse)
        XCTAssertFalse(store.markUseful(receipt: local, sourceDigest: sourceDigest))
        let otherSource = String(repeating: "b", count: 64)
        XCTAssertFalse(store.markUseful(receipt: receipt(id: id, source: otherSource), sourceDigest: otherSource, confirmedLesson: lesson))
        XCTAssertTrue(store.markUseful(receipt: local, sourceDigest: sourceDigest.uppercased(), confirmedLesson: lesson))
        let retained = store.usefulReceipts, revision = store.revision
        XCTAssertFalse(store.markUseful(receipt: local, sourceDigest: sourceDigest, confirmedLesson: lesson))
        let other = LessonSnapshot(id: UUID().uuidString, revision: 1, topic: lesson.topic, text: "Another lesson.")
        var alternate = local; alternate.localLessons = [other]; alternate.usedLessonIDs = [other.modelID]
        XCTAssertFalse(store.markUseful(receipt: alternate, sourceDigest: sourceDigest, confirmedLesson: other))
        XCTAssertEqual(store.usefulReceipts, retained)
        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(store.usefulReceipts.count, 1)
        store.withdrawLessonUse(requestID: id)
        XCTAssertEqual(store.usefulReceipts, [EvolutionUsefulReceipt(requestID: id, sourceDigest: sourceDigest, requestBinding: EvolutionRequestBinding(receipt: local))])
        XCTAssertTrue(store.markUseful(receipt: alternate, sourceDigest: sourceDigest, confirmedLesson: other))
        XCTAssertEqual(store.usefulReceipts.count, 1)
        XCTAssertTrue(try XCTUnwrap(store.usefulReceipts[0].lessonUse).matches(snapshot: other))
    }

    @MainActor
    func testAnnotationAndWithdrawalPreserveBodyHistoryAndJourneyAndRespectTheRecordLimit() throws {
        let store = EvolutionStore(origin: .particle)
        store.observeJourneyOrigin(sourceDigest)
        XCTAssertTrue(store.bindPracticeJourney(sourceDigest))
        store.confirmFamily(.lumen)
        XCTAssertTrue(store.keepEvolution(try XCTUnwrap(store.proposeEvolution())))
        let history = store.history, natural = store.naturalVariation, basis = store.keptBasis
        let preferences = store.preferences, practices = store.reviewedPractices
        let records = (0..<EvolutionStore.maximumUsefulReceipts).map { _ in receipt() }
        for record in records { XCTAssertTrue(store.markUseful(receipt: record, sourceDigest: sourceDigest)) }
        XCTAssertTrue(store.markUseful(receipt: records[0], sourceDigest: sourceDigest, confirmedLesson: lesson),
            "Annotation adds no request and remains possible at the record limit")
        XCTAssertFalse(store.markUseful(receipt: receipt(), sourceDigest: sourceDigest, confirmedLesson: lesson))
        let id = try XCTUnwrap(UUID(uuidString: records[0].requestID))
        store.withdrawLessonUse(requestID: id)
        let revision = store.revision
        store.withdrawLessonUse(requestID: id)
        store.withdrawLessonUse(requestID: UUID())
        XCTAssertEqual(store.revision, revision, "Absent annotation withdrawal is a no-op")
        XCTAssertEqual(store.usefulReceipts.count, EvolutionStore.maximumUsefulReceipts)
        XCTAssertTrue(store.usefulReceipts.allSatisfy { $0.lessonUse == nil })
        XCTAssertEqual(store.origin, .particle)
        XCTAssertEqual(store.activeFamily, .lumen)
        XCTAssertEqual(store.history, history)
        XCTAssertEqual(store.naturalVariation, natural)
        XCTAssertEqual(store.keptBasis, basis)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.reviewedPractices, practices)
        XCTAssertEqual(store.practiceJourneyOriginDigest, sourceDigest)
        XCTAssertEqual(store.observedJourneyOriginDigest, sourceDigest)
    }

    @MainActor
    func testV5SaveAndExplicitLoadPreserveOnlyHistoricalReferences() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(origin: .particle, saveURL: url)
        let record = receipt()
        XCTAssertTrue(store.markUseful(receipt: record, sourceDigest: sourceDigest, confirmedLesson: lesson))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(store.save(), store.status)
        let bytes = try Data(contentsOf: url), fields = try object(bytes)
        XCTAssertEqual(fields["schema"] as? String, EvolutionStore.schema)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertFalse(text.contains(lesson.topic))
        XCTAssertFalse(text.contains(lesson.text))
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.usefulReceipts.isEmpty, "Construction never loads historical references")
        XCTAssertTrue(reopened.load(), reopened.status)
        XCTAssertEqual(reopened.usefulReceipts, store.usefulReceipts)
        XCTAssertEqual(reopened.origin, .particle)
        XCTAssertNil(reopened.activeFamily)
        XCTAssertNil(reopened.proposeEvolution())
        XCTAssertTrue(reopened.history.isEmpty)
        reopened.withdrawLessonUse(requestID: try XCTUnwrap(UUID(uuidString: record.requestID)))
        XCTAssertEqual(try Data(contentsOf: url), bytes, "Withdrawal still needs explicit Save")
        XCTAssertTrue(reopened.save(), reopened.status)
        XCTAssertTrue(store.load(), store.status)
        XCTAssertEqual(store.usefulReceipts.count, 1)
        XCTAssertNil(store.usefulReceipts[0].lessonUse)
        XCTAssertTrue(store.forget())
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testV1ThroughV4MigrateWithoutInventingLessonUseAndV4KeepsUnqualifiedAppearanceChoice() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        for version in 1...4 {
            try write(EvolutionLegacyTestData.data(version: version), to: url)
            let store = EvolutionStore(saveURL: url)
            XCTAssertTrue(store.load(), "v\(version): \(store.status)")
            XCTAssertEqual(store.activeFamily, .lumen)
            XCTAssertTrue(store.usefulReceipts.allSatisfy { $0.lessonUse == nil })
            let history = store.history
            XCTAssertTrue(store.save(), store.status)
            XCTAssertEqual(try object(Data(contentsOf: url))["schema"] as? String, EvolutionStore.schema)
            let migrated = EvolutionStore(saveURL: url)
            XCTAssertTrue(migrated.load(), migrated.status)
            XCTAssertEqual(migrated.history, history)
            XCTAssertEqual(migrated.usefulReceipts, store.usefulReceipts)
        }
        var v4 = try EvolutionLegacyTestData.object(version: 4, receiptCount: 0)
        v4["role"] = NSNull(); v4["helpStyle"] = NSNull(); v4["family"] = NSNull()
        v4["keptBasis"] = ["kind": "appearance-choice/v1"]
        v4["keptAppearanceRecipe"] = NSNull()
        var history = try XCTUnwrap(v4["history"] as? [[String: Any]])
        history[0]["appearanceRecipe"] = NSNull(); v4["history"] = history
        try write(JSONSerialization.data(withJSONObject: v4), to: url)
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.load(), store.status)
        XCTAssertEqual(store.preferences.confirmedCount, 0)
        XCTAssertEqual(store.activeFamily, .lumen)
        XCTAssertEqual(store.keptBasis?.kind, .appearanceChoice)
        XCTAssertNil(store.proposeEvolution())
        XCTAssertTrue(store.save(), store.status)
    }

    @MainActor
    func testV5AllowsAbsentOrNullLessonUseButRejectsMalformedNestedDataWithoutReplacingStateOrFile() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.markUseful(receipt: receipt(), sourceDigest: sourceDigest, confirmedLesson: lesson))
        XCTAssertTrue(store.save(), store.status)
        let valid = try object(Data(contentsOf: url))
        let validRows = try XCTUnwrap(valid["usefulReceipts"] as? [[String: Any]])
        for explicitNull in [false, true] {
            var fields = valid, rows = validRows
            if explicitNull { rows[0]["lessonUse"] = NSNull() } else { rows[0].removeValue(forKey: "lessonUse") }
            fields["usefulReceipts"] = rows
            try write(JSONSerialization.data(withJSONObject: fields), to: url)
            let historical = EvolutionStore(saveURL: url)
            XCTAssertTrue(historical.load(), historical.status)
            XCTAssertNil(historical.usefulReceipts[0].lessonUse)
        }
        let retained = store.usefulReceipts, revision = store.revision
        var malformed: [Data] = []
        let reference = try XCTUnwrap(validRows[0]["lessonUse"] as? [String: Any])
        for invalidReference in [
            reference.merging(["topic": "Do not copy this"]) { _, new in new },
            reference.merging(["lessonRevision": 0]) { _, new in new },
            reference.merging(["lessonRevision": true]) { _, new in new },
            reference.merging(["snapshotDigest": "invalid"]) { _, new in new },
            reference.merging(["lessonID": "invalid"]) { _, new in new }
        ] {
            var fields = valid, rows = validRows; rows[0]["lessonUse"] = invalidReference; fields["usefulReceipts"] = rows
            malformed.append(try JSONSerialization.data(withJSONObject: fields))
        }
        for invalidValue in ["bad" as Any, [], 5] {
            var fields = valid, rows = validRows; rows[0]["lessonUse"] = invalidValue; fields["usefulReceipts"] = rows
            malformed.append(try JSONSerialization.data(withJSONObject: fields))
        }
        var oldSchema = valid; oldSchema["schema"] = "archi-companion-evolution/v4"
        oldSchema.removeValue(forKey: "kinGrowthRecord")
        malformed.append(try JSONSerialization.data(withJSONObject: oldSchema))
        let encoded = try JSONSerialization.data(withJSONObject: valid, options: .sortedKeys)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let duplicate = text.replacingOccurrences(of: #""lessonRevision":2"#, with: #""lessonRevision":2,"lessonRevision":2"#)
        XCTAssertNotEqual(duplicate, text)
        malformed.append(Data(duplicate.utf8))
        for bytes in malformed {
            try write(bytes, to: url)
            XCTAssertFalse(store.load())
            XCTAssertEqual(store.usefulReceipts, retained)
            XCTAssertEqual(store.revision, revision)
            XCTAssertFalse(store.save(), "Invalid existing archives require explicit replacement")
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    @MainActor
    func testMaximumHistoricalStateAndAllLessonReferencesStillFitTheExistingSaveBound() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let practices = (0..<8).map { index in
            PracticeEvolutionReference(originDigest: sourceDigest, eventId: "\(index):" + String(repeating: "e", count: 158),
                battleId: UUID(), rulesVersion: 1, rounds: 20, outcome: .lost,
                replayDigest: String(repeating: "c", count: 64), committedAt: "2026-09-06T18:00:00.123456789+00:00")
        }
        var legacy = try EvolutionLegacyTestData.object(practice: practices[0], historyCount: 32, receiptCount: 32)
        legacy["reviewedPractices"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(practices))
        try write(JSONSerialization.data(withJSONObject: legacy), to: url)
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.load(), store.status)
        let history = store.history, recipe = store.keptAppearanceRecipe
        let snapshot = LessonSnapshot(id: lesson.id, revision: UInt64.max, topic: lesson.topic, text: lesson.text)
        for record in store.usefulReceipts {
            var lane = receipt(id: record.requestID)
            lane.localLessons = [snapshot]; lane.usedLessonIDs = [snapshot.modelID]
            store.withdrawUseful(requestID: try XCTUnwrap(UUID(uuidString: lane.requestID)))
            XCTAssertTrue(store.markUseful(receipt: lane, sourceDigest: sourceDigest, confirmedLesson: snapshot))
        }
        XCTAssertTrue(store.save(), store.status)
        XCTAssertLessThanOrEqual(try Data(contentsOf: url).count, EvolutionStore.maximumSaveBytes)
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.load(), reopened.status)
        XCTAssertEqual(reopened.history, history)
        XCTAssertEqual(reopened.keptAppearanceRecipe, recipe)
        XCTAssertEqual(reopened.reviewedPractices, practices)
        XCTAssertEqual(reopened.usefulReceipts, store.usefulReceipts)
        XCTAssertEqual(reopened.usefulReceipts.count, 32)
        XCTAssertTrue(reopened.usefulReceipts.allSatisfy { $0.lessonUse?.lessonRevision == UInt64.max })
    }

    private func receipt(id: UUID = UUID(), provider: AssistantProvider = .qwen, source: String? = nil) -> AssistantLaneReceipt {
        var receipt = AssistantLaneReceipt(requestID: id.uuidString, route: .compare, provider: provider,
            context: ContextTicket(generation: 1, placement: 1, source: 1, selection: 1),
            inputDigest: String(repeating: "b", count: 64), sourceDigest: source ?? sourceDigest,
            inputContract: "native-assistant-input/v2", deadline: .distantFuture, modelIdentity: "synthetic-fixture", state: .complete)
        receipt.localLessons = [lesson]; receipt.usedLessonIDs = [lesson.modelID]
        return receipt
    }

    private func temporarySave() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("archi-lesson-use-\(UUID().uuidString)")
            .appendingPathComponent("evolution.json")
    }
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
