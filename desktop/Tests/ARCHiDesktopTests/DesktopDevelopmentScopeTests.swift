import XCTest
@testable import ARCHiDesktop

final class DesktopDevelopmentScopeTests: XCTestCase {
    @MainActor
    func testDisabledPlayCannotOpenThroughStoreOrSidebarSelection() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("preferences.json")
        let store = CompanionStore(preferenceURL: url, allowsPlay: false)
        var opened: WorkspaceSection?
        store.onOpenWorkspace = { opened = $0 }
        store.open(.play)
        XCTAssertEqual(store.section, .assistant)
        XCTAssertEqual(opened, .assistant)
        store.section = .play
        XCTAssertEqual(store.section, .assistant)
        store.open(.context)
        XCTAssertEqual(store.section, .context)
    }

    @MainActor
    func testValidatedNativeKinSurvivesWithoutStartingTheGameOrRewritingItsOrigin() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("preferences.json")
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: Date())
        var document = NativePreferenceDocument()
        document.qiMon = kin
        let original = try document.encoded()
        try original.write(to: url)
        let desktop = CompanionStore(preferenceURL: url, allowsPlay: false)
        XCTAssertNil(desktop.qiMonJourneyOrigin, "No game projection is fabricated")
        XCTAssertEqual(desktop.activeQiMon, kin)
        XCTAssertEqual(desktop.presentationForm, .kinSeed)
        XCTAssertEqual(try Data(contentsOf: url), original)
        let historicalGameMode = CompanionStore(preferenceURL: url)
        XCTAssertNil(historicalGameMode.activeQiMon, "Retained game integration still verifies its actual Journey")
    }
}
