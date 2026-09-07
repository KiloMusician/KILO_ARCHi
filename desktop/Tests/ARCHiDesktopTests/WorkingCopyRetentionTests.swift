import Foundation
import XCTest
@testable import ARCHiDesktop

final class WorkingCopyRetentionTests: XCTestCase {
    @MainActor
    func testOnlyVerifiedExportOrExactRestorationClearsUnexportedEdits() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("retention-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("original.txt")
        try Data("Original words".utf8).write(to: original)
        let store = CompanionStore(preferenceURL: folder.appendingPathComponent("unused.json"))
        XCTAssertFalse(store.hasUnexportedWorkingCopy)
        XCTAssertTrue(store.importWorkingCopy(from: original))
        XCTAssertFalse(store.hasUnexportedWorkingCopy)
        store.sharedText = "Revised words"
        XCTAssertTrue(store.hasUnexportedWorkingCopy)
        XCTAssertFalse(store.exportWorkingCopy(to: original, expectedRevision: store.sourceRevision))
        XCTAssertTrue(store.hasUnexportedWorkingCopy, "Rejecting the original as destination cannot mark edits saved")
        let draft = folder.appendingPathComponent("draft.txt")
        XCTAssertFalse(store.exportWorkingCopy(to: draft, expectedRevision: store.sourceRevision + 1))
        XCTAssertTrue(store.hasUnexportedWorkingCopy)
        XCTAssertTrue(store.exportWorkingCopy(to: draft, expectedRevision: store.sourceRevision))
        XCTAssertFalse(store.hasUnexportedWorkingCopy)
        XCTAssertEqual(try String(contentsOf: draft, encoding: .utf8), "Revised words")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "Original words")
        store.sharedText = "A later edit"
        XCTAssertTrue(store.hasUnexportedWorkingCopy)
        store.sharedText = "Revised words"
        XCTAssertFalse(store.hasUnexportedWorkingCopy, "Restoring exact exported bytes needs no new export")
        store.sharedText = "Original words"
        XCTAssertFalse(store.hasUnexportedWorkingCopy, "Undo back to the imported source needs no export")
        store.sharedText = "A later edit"
        XCTAssertFalse(store.exportWorkingCopy(to: folder.appendingPathComponent("missing/draft.txt"), expectedRevision: store.sourceRevision))
        XCTAssertTrue(store.hasUnexportedWorkingCopy, "A failed write must leave the quit guard active")
        store.stopSharing()
        XCTAssertFalse(store.hasUnexportedWorkingCopy)
    }

    @MainActor
    func testRetentionUsesExactBytesAndDoesNotLeakAcrossDocuments() {
        let store = CompanionStore(preferenceURL: FileManager.default.temporaryDirectory.appendingPathComponent("retention-\(UUID()).json"))
        store.share(text: "Café", name: "first.txt")
        store.sharedText = "Cafe\u{301}"
        XCTAssertTrue(store.hasUnexportedWorkingCopy, "Unicode-equivalent text can still contain unsaved byte edits")
        store.share(text: "Another draft", name: "second.txt")
        XCTAssertFalse(store.hasUnexportedWorkingCopy)
        store.sharedText += "!"
        XCTAssertTrue(store.hasUnexportedWorkingCopy)
    }
}
