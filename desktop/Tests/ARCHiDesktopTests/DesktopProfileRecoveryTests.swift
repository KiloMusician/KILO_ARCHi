import CryptoKit
import Foundation
import XCTest
@testable import ARCHiDesktop

/// Rehearses the manual two-file copy procedure with disposable data and existing
/// owners. These helpers are test fixtures, not a production backup engine.
final class DesktopProfileRecoveryTests: XCTestCase {
    private let filenames = ["preferences.json", "preferences.evolution.json"]

    @MainActor
    func testCopiedPairRestoresNativeOwnersThenExplicitlyLoadsFirstLight() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSource(in: root.appendingPathComponent("source"))
        let growth = try XCTUnwrap(source.store.evolution.kinGrowthRecord)
        let useful = source.store.evolution.usefulReceipts
        let guidance = source.store.evolution.preferences
        let history = source.store.evolution.history
        source.store.prompt = "An unsent synthetic draft belongs to this visit."
        source.store.share(text: "An unexported synthetic document is separate from profile recovery.", name: "visit-only.txt")
        source.store.placed(at: CGPoint(x: 543, y: 321))
        source.store.activity.append("Synthetic visit-only activity marker")
        await source.store.shutdownAssistant()

        let backup = root.appendingPathComponent("dated-backup-2026-09-13-120000")
        let backedUp = try copyProfilePair(from: source.directory, to: backup)
        XCTAssertTrue(backedUp.values.allSatisfy(\.present))
        XCTAssertEqual(backedUp, try readCheckpointNote(backup))
        let restoredDirectory = root.appendingPathComponent("disposable-restored")
        XCTAssertEqual(try copyProfilePair(from: backup, to: restoredDirectory), backedUp)
        let restoredPreferenceURL = restoredDirectory.appendingPathComponent("preferences.json")
        let decoded = try NativePreferencePersistence.read(restoredPreferenceURL)
        XCTAssertEqual(decoded.document, source.document)
        XCTAssertEqual(decoded.baseline, try Data(contentsOf: backup.appendingPathComponent("preferences.json")))

        let restored = makeStore(at: restoredPreferenceURL, client: source.client)
        XCTAssertEqual(restored.preferences, source.document.preferences)
        XCTAssertEqual(restored.keptLessons, source.document.lessons)
        XCTAssertEqual(restored.activeQiMon, source.document.qiMon)
        XCTAssertEqual(restored.keptFocusGesture, source.document.focusGesture)
        XCTAssertNil(restored.evolution.kinGrowthRecord)
        XCTAssertTrue(restored.evolution.usefulReceipts.isEmpty)
        XCTAssertEqual(restored.presentationForm, .kinSeed, "Evolution is not silently loaded during construction")
        XCTAssertEqual(restored.cursorPresentationForm, .kinSeed)
        XCTAssertEqual(try pairState(restoredDirectory), backedUp, "Read-only construction preserves the copied files")
        XCTAssertTrue(restored.evolution.load(), restored.evolution.status)
        XCTAssertEqual(restored.evolution.kinGrowthRecord, growth)
        XCTAssertEqual(restored.evolution.usefulReceipts, useful)
        XCTAssertEqual(restored.evolution.preferences, guidance)
        XCTAssertEqual(restored.evolution.history, history)
        XCTAssertEqual(restored.presentationForm, .kin)
        XCTAssertEqual(restored.cursorPresentationForm, .kinSeed)
        XCTAssertEqual(restored.evolution.kinGrowthRecord?.originDigest, restored.activeQiMon?.originDigest)
        XCTAssertEqual(restored.prompt, "")
        XCTAssertEqual(restored.position, .zero)
        XCTAssertEqual(restored.sharedText, "")
        XCTAssertNil(restored.sourceName)
        XCTAssertTrue(restored.localConversation.exchanges.isEmpty)
        XCTAssertTrue(restored.compareResults.isEmpty)
        XCTAssertFalse(restored.activity.contains("Synthetic visit-only activity marker"))
        XCTAssertEqual(try pairState(restoredDirectory), backedUp)

        // Exercise a deliberate post-restore write only in the disposable copy,
        // after adopting its exact baseline through the successful Load above.
        restored.returnKinToSeed()
        XCTAssertTrue(restored.evolution.save(), restored.evolution.status)
        let reopened = makeStore(at: restoredPreferenceURL, client: source.client)
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertEqual(reopened.presentationForm, .kinSeed)
        XCTAssertEqual(reopened.evolution.kinGrowthRecord?.id, growth.id)
        XCTAssertTrue(reopened.resumeKinFirstLight())
        XCTAssertTrue(reopened.evolution.save())
        XCTAssertEqual(reopened.activeQiMon, source.document.qiMon)
        XCTAssertEqual(reopened.keptLessons, source.document.lessons)
        XCTAssertEqual(reopened.keptFocusGesture, source.document.focusGesture)
        XCTAssertEqual(try pairState(backup), backedUp, "The verified checkpoint is not the rehearsal working copy")
        XCTAssertEqual(try pairState(source.directory), backedUp, "The stopped source pair stays untouched")
        XCTAssertEqual(source.client.calls, 0)
        await reopened.shutdownAssistant()
        await restored.shutdownAssistant()
    }

    @MainActor
    func testAbsentEvolutionIsRecordedAndCannotRestoreAnOldBody() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSource(in: root.appendingPathComponent("source"), saveGrowth: false)
        await source.store.shutdownAssistant()
        let backup = root.appendingPathComponent("dated-backup-2026-09-13-120100")
        let checkpoint = try copyProfilePair(from: source.directory, to: backup)
        XCTAssertEqual(checkpoint["preferences.evolution.json"], FileState(present: false, byteCount: nil, sha256: nil))
        XCTAssertEqual(try readCheckpointNote(backup), checkpoint)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.appendingPathComponent("preferences.evolution.json").path))
        let restoredDirectory = root.appendingPathComponent("disposable-restored")
        XCTAssertEqual(try copyProfilePair(from: backup, to: restoredDirectory), checkpoint)
        let restored = makeStore(at: restoredDirectory.appendingPathComponent("preferences.json"), client: source.client)
        XCTAssertEqual(restored.activeQiMon, source.document.qiMon)
        XCTAssertEqual(restored.keptLessons, source.document.lessons)
        XCTAssertEqual(restored.keptFocusGesture, source.document.focusGesture)
        XCTAssertEqual(restored.presentationForm, .kinSeed)
        XCTAssertEqual(restored.cursorPresentationForm, .kinSeed)
        XCTAssertFalse(restored.evolution.load())
        XCTAssertNil(restored.evolution.kinGrowthRecord)
        XCTAssertTrue(restored.evolution.usefulReceipts.isEmpty)
        XCTAssertFalse(restored.resumeKinFirstLight())
        XCTAssertEqual(restored.presentationForm, .kinSeed)
        XCTAssertEqual(try pairState(restoredDirectory), checkpoint, "A missing save must not become an empty or invented save")
        XCTAssertEqual(source.client.calls, 0)
        await restored.shutdownAssistant()
    }

    @MainActor
    func testForeignOriginAndDamagedCopiesCannotAdmitTheWrongBody() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let foreignOrigin = String(repeating: "d", count: 64)
        let source = try makeSource(in: root.appendingPathComponent("source"), foreignGrowthOrigin: foreignOrigin)
        await source.store.shutdownAssistant()
        let backup = root.appendingPathComponent("dated-backup-2026-09-13-120200")
        let checkpoint = try copyProfilePair(from: source.directory, to: backup)
        let restoredDirectory = root.appendingPathComponent("disposable-restored")
        XCTAssertEqual(try copyProfilePair(from: backup, to: restoredDirectory), checkpoint)
        let restored = makeStore(at: restoredDirectory.appendingPathComponent("preferences.json"), client: source.client)
        XCTAssertTrue(restored.evolution.load(), restored.evolution.status)
        XCTAssertEqual(restored.evolution.kinGrowthRecord?.originDigest, foreignOrigin)
        XCTAssertNotEqual(restored.activeQiMon?.originDigest, foreignOrigin)
        XCTAssertEqual(restored.activeQiMon, source.document.qiMon)
        XCTAssertEqual(restored.presentationForm, .kinSeed)
        XCTAssertEqual(restored.cursorPresentationForm, .kinSeed)
        XCTAssertFalse(restored.resumeKinFirstLight())
        XCTAssertEqual(try pairState(restoredDirectory), checkpoint)
        XCTAssertEqual(source.client.calls, 0)
        await restored.shutdownAssistant()
        try await verifyDamagedCopiesFailValidationAndRollbackRemainsUsable()
    }

    @MainActor
    private func verifyDamagedCopiesFailValidationAndRollbackRemainsUsable() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSource(in: root.appendingPathComponent("source"))
        await source.store.shutdownAssistant()
        let backup = root.appendingPathComponent("dated-backup-2026-09-13-120300")
        let checkpoint = try copyProfilePair(from: source.directory, to: backup)
        let damaged = root.appendingPathComponent("damaged-rehearsal-copy")
        _ = try copyProfilePair(from: backup, to: damaged)
        let corrupt = Data("{ damaged synthetic backup".utf8)
        for filename in filenames { try corrupt.write(to: damaged.appendingPathComponent(filename)) }
        XCTAssertNotEqual(try pairState(damaged), checkpoint, "The independent checksum step detects damage before adoption")
        XCTAssertThrowsError(try NativePreferencePersistence.read(damaged.appendingPathComponent("preferences.json")))
        let rejected = makeStore(at: damaged.appendingPathComponent("preferences.json"), client: source.client)
        XCTAssertNil(rejected.activeQiMon)
        XCTAssertTrue(rejected.keptLessons.isEmpty)
        XCTAssertNil(rejected.keptFocusGesture)
        XCTAssertFalse(rejected.evolution.load())
        XCTAssertNil(rejected.evolution.kinGrowthRecord)
        XCTAssertTrue(rejected.evolution.usefulReceipts.isEmpty)
        XCTAssertFalse(rejected.presentationForm.isKin)
        XCTAssertFalse(rejected.cursorPresentationForm.isKin)
        for filename in filenames { XCTAssertEqual(try Data(contentsOf: damaged.appendingPathComponent(filename)), corrupt) }
        await rejected.shutdownAssistant()

        // A rollback is another verified copy, not an attempt to repair JSON or
        // reuse the rejected store's cached baseline. The damaged copy survives.
        let rollback = root.appendingPathComponent("disposable-rollback-restored")
        XCTAssertEqual(try copyProfilePair(from: backup, to: rollback), checkpoint)
        let recovered = makeStore(at: rollback.appendingPathComponent("preferences.json"), client: source.client)
        XCTAssertTrue(recovered.evolution.load())
        XCTAssertEqual(recovered.activeQiMon, source.document.qiMon)
        XCTAssertEqual(recovered.keptLessons, source.document.lessons)
        XCTAssertEqual(recovered.keptFocusGesture, source.document.focusGesture)
        XCTAssertEqual(recovered.evolution.kinGrowthRecord, source.store.evolution.kinGrowthRecord)
        XCTAssertEqual(recovered.presentationForm, .kin)
        XCTAssertEqual(recovered.cursorPresentationForm, .kinSeed)
        XCTAssertEqual(try pairState(backup), checkpoint)
        XCTAssertEqual(try pairState(source.directory), checkpoint)
        XCTAssertEqual(source.client.calls, 0)
        await recovered.shutdownAssistant()
    }

    @MainActor private func makeSource(in directory: URL, saveGrowth: Bool = true,
                                       foreignGrowthOrigin: String? = nil) throws -> SourceFixture {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let origin = String(repeating: "a", count: 64)
        var preferences = CompanionPreferences()
        preferences.tone = "Warm"
        preferences.replyLength = 0.65
        preferences.reduceMotion = true
        preferences.equipment = CompanionEquipment(hand: .focusStaff)
        let lesson = KeptLesson(revision: 2, topic: "Drawing plans", text: "Begin with charcoal and a short outline.",
            reason: "Synthetic recovery fixture", createdAt: now)
        let gesture = FocusGestureConfiguration(pace: .unhurried, sparkle: .none, hold: .lingering)
        let kin = LocalQiMon(character: .kin, originDigest: origin, welcomedAt: now)
        let document = NativePreferenceDocument(revision: 7, preferences: preferences, lessons: [lesson], focusGesture: gesture, qiMon: kin)
        let url = directory.appendingPathComponent("preferences.json")
        _ = try NativePreferencePersistence.write(document: document, to: url, expected: nil)
        let client = RecoveryNoCalls()
        let store = makeStore(at: url, client: client)
        if saveGrowth {
            store.evolution.confirmRole(.muse)
            store.evolution.confirmHelpStyle(.stepByStep)
            let snapshot = LessonSnapshot(lesson: lesson), requestID = UUID()
            let sourceDigest = String(repeating: "b", count: 64)
            var receipt = AssistantLaneReceipt(requestID: requestID.uuidString, route: .local, provider: .qwen,
                context: store.contextTicket(), inputDigest: String(repeating: "c", count: 64), sourceDigest: sourceDigest,
                inputContract: "native-assistant-input/v4", deadline: .distantFuture,
                modelIdentity: "synthetic-profile-recovery", state: .complete)
            receipt.localLessons = [snapshot]; receipt.usedLessonIDs = [snapshot.modelID]
            XCTAssertTrue(store.evolution.markUseful(receipt: receipt, sourceDigest: sourceDigest, confirmedLesson: snapshot))
            if let foreignGrowthOrigin {
                let retained = try XCTUnwrap(store.evolution.usefulReceipts.first)
                let proposal = try XCTUnwrap(store.evolution.proposeKinGrowth(originDigest: foreignGrowthOrigin, receipt: retained))
                XCTAssertTrue(store.evolution.keepKinGrowth(proposal))
            } else {
                XCTAssertTrue(store.previewKinGrowth(receiptID: requestID))
                XCTAssertTrue(store.keepKinGrowth())
            }
            XCTAssertTrue(store.evolution.save(), store.evolution.status)
        }
        return SourceFixture(directory: directory, document: document, client: client, store: store)
    }

    @MainActor private func makeStore(at preferenceURL: URL, client: RecoveryNoCalls) -> CompanionStore {
        CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { _, _ in client }, wallClock: { Date(timeIntervalSince1970: 1_789_000_000) }, allowsPlay: false)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-profile-recovery-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Plain FileManager copying and independent readback, used only by tests.
    /// The destination is fresh; no existing file is overwritten by this helper.
    private func copyProfilePair(from source: URL, to destination: URL) throws -> [String: FileState] {
        XCTAssertNotEqual(source.standardizedFileURL, destination.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let expected = try pairState(source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for filename in filenames where expected[filename]?.present == true {
            try FileManager.default.copyItem(at: source.appendingPathComponent(filename), to: destination.appendingPathComponent(filename))
            XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent(filename)),
                try Data(contentsOf: destination.appendingPathComponent(filename)))
        }
        let actual = try pairState(destination)
        XCTAssertEqual(actual, expected)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(actual).write(to: destination.appendingPathComponent("checkpoint.json"))
        return actual
    }

    private func pairState(_ directory: URL) throws -> [String: FileState] {
        var records: [String: FileState] = [:]
        for filename in filenames {
            let url = directory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                let type = try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
                XCTAssertEqual(type, .typeRegular)
                let bytes = try Data(contentsOf: url)
                records[filename] = FileState(present: true, byteCount: bytes.count,
                    sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
            } else {
                records[filename] = FileState(present: false, byteCount: nil, sha256: nil)
            }
        }
        return records
    }

    private func readCheckpointNote(_ directory: URL) throws -> [String: FileState] {
        try JSONDecoder().decode([String: FileState].self, from: Data(contentsOf: directory.appendingPathComponent("checkpoint.json")))
    }

    private struct FileState: Codable, Equatable {
        let present: Bool
        let byteCount: Int?
        let sha256: String?
    }

    @MainActor private struct SourceFixture {
        let directory: URL
        let document: NativePreferenceDocument
        let client: RecoveryNoCalls
        let store: CompanionStore
    }
}

@MainActor private final class RecoveryNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.configuration
    }
    func disconnect() {}
}
