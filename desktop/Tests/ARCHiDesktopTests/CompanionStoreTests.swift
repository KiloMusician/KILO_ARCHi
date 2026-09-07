import XCTest
@testable import ARCHiDesktop

final class CompanionStoreTests: XCTestCase {
    @MainActor
    func testMovementAndCancellationInvalidateCapturedContext() {
        let store = CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"))
        let first = store.contextTicket()
        store.placed(at: CGPoint(x: 400, y: -80))
        XCTAssertFalse(store.isCurrent(first))
        XCTAssertEqual(store.position, CGPoint(x: 400, y: -80))
        let moved = store.contextTicket()
        store.cancelWork()
        XCTAssertFalse(store.isCurrent(moved))
        XCTAssertEqual(store.position, CGPoint(x: 400, y: -80))
    }

    @MainActor
    func testSourceReplacementAndStopSharingInvalidateAndClearContent() {
        let store = CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"))
        store.share(text: "first", name: "one.txt")
        let first = store.contextTicket()
        store.share(text: "second", name: "two.txt")
        XCTAssertFalse(store.isCurrent(first))
        let second = store.contextTicket()
        store.stopSharing()
        XCTAssertFalse(store.isCurrent(second))
        XCTAssertEqual(store.sharedText, "")
        XCTAssertNil(store.sourceName)
    }

    @MainActor
    func testHiddenOrNewRequestCannotKeepOldContextCurrent() {
        let store = CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"))
        let first = store.contextTicket()
        store.hideCompanion()
        store.showCompanion()
        XCTAssertFalse(store.isCurrent(first))
        let visible = store.contextTicket()
        store.prompt = "Help with this"
        store.submit()
        XCTAssertFalse(store.isCurrent(visible))
        XCTAssertFalse(store.isWorking)
        XCTAssertTrue(store.status.contains("Not sent"))
    }

    @MainActor
    func testSharedDocumentIsExactAndOversizeReplacementIsRejected() {
        let store = CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"))
        let text = String(repeating: "a", count: 80_000)
        store.share(text: text, name: "valid.txt")
        XCTAssertEqual(store.sharedText, text)
        let ticket = store.contextTicket()
        store.share(text: String(repeating: "é", count: 50_001), name: "too-large.txt")
        XCTAssertEqual(store.sharedText, text)
        XCTAssertEqual(store.sourceName, "valid.txt")
        XCTAssertTrue(store.isCurrent(ticket))
    }

    @MainActor
    func testPreferencePersistenceRequiresOptInAndForgettingRemovesSavedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let store = CompanionStore(preferenceURL: url)
        store.preferences.form = .ink
        store.savePreferences()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        store.rememberPreferences = true
        store.savePreferences()
        let reloaded = CompanionStore(preferenceURL: url)
        XCTAssertEqual(reloaded.preferences.form, .ink)
        XCTAssertTrue(reloaded.rememberPreferences)
        reloaded.forgetPreferences()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(reloaded.preferences.form, .ink)
    }

    @MainActor
    func testInvalidStoredPreferencesDoNotCorruptLayout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        var preferences = CompanionPreferences()
        preferences.size = -1000
        try JSONEncoder().encode(preferences).write(to: url)
        let store = CompanionStore(preferenceURL: url)
        XCTAssertEqual(store.preferences, CompanionPreferences())
        XCTAssertFalse(store.rememberPreferences)
    }
}
