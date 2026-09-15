import Foundation
import XCTest
@testable import ARCHiDesktop

/// Disposable profiles exercise the same outfit and workspace owners used by
/// the marketplace. These tests never connect a model or capture the desktop.
@MainActor
final class MarketplaceOutfitTests: XCTestCase {
    private var staff: CompanionItemPackage { CompanionItemCatalog.designs[0] }
    private var decoration: CompanionItemPackage { CompanionItemCatalog.designs[1] }
    private var grove: CompanionItemPackage { CompanionItemCatalog.designs[2] }

    func testSavedOutfitProjectionIgnoresUnrelatedSettingsAndRememberToggle() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = fixture.store()
        XCTAssertTrue(store.marketplaceOutfitReadable)
        XCTAssertNil(store.savedMarketplaceEquipment)
        XCTAssertTrue(store.collectMarketItem(staff))
        XCTAssertTrue(store.equipMarketItem(staff))
        XCTAssertNil(store.savedMarketplaceEquipment, "Equipping is for this visit until Save.")

        store.rememberPreferences = true
        store.savePreferences()
        let saved = store.preferences.equipment
        let savedBytes = try Data(contentsOf: fixture.preferences)
        XCTAssertEqual(store.savedMarketplaceEquipment, saved)
        XCTAssertTrue(store.equipMarketItem(staff))
        XCTAssertTrue(store.marketplaceMessage.contains("also saved for the next visit"))
        store.preferences.tone = "Direct"
        XCTAssertEqual(store.preferenceRetention, .changed)
        XCTAssertEqual(store.savedMarketplaceEquipment, store.preferences.equipment,
                       "A different reply tone must not label an unchanged outfit as unsaved.")
        store.rememberPreferences = false
        XCTAssertEqual(store.savedMarketplaceEquipment, saved,
                       "Turning Save off does not forget the previously saved outfit.")
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), savedBytes)
        let reopened = fixture.store()
        XCTAssertEqual(reopened.preferences.equipment, saved)
        XCTAssertEqual(reopened.savedMarketplaceEquipment, saved)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testForgetOutfitPreservesCurrentVisitButChangesNextVisit() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = fixture.store()
        XCTAssertTrue(store.collectMarketItem(staff))
        XCTAssertTrue(store.equipMarketItem(staff))
        store.rememberPreferences = true
        store.savePreferences()
        let current = store.preferences.equipment
        store.forgetPreferences()
        XCTAssertNil(store.savedMarketplaceEquipment)
        XCTAssertTrue(store.marketplaceOutfitReadable)
        XCTAssertEqual(store.preferences.equipment, current)
        XCTAssertEqual(store.itemLibrary, [staff])
        let reopened = fixture.store()
        XCTAssertTrue(reopened.preferences.equipment.isEmpty)
        XCTAssertNil(reopened.savedMarketplaceEquipment)
        XCTAssertEqual(reopened.itemLibrary, [staff])
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testRemovingSavedItemKeepsDifferentCurrentOutfitAndRestartsEmpty() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = fixture.store()
        XCTAssertTrue(store.collectMarketItem(staff))
        XCTAssertTrue(store.collectMarketItem(grove))
        XCTAssertTrue(store.equipMarketItem(staff))
        store.rememberPreferences = true
        store.savePreferences()
        XCTAssertTrue(store.equipMarketItem(grove))
        XCTAssertEqual(store.savedMarketplaceEquipment?.design, staff)
        XCTAssertTrue(store.removeMarketItem(staff))
        XCTAssertEqual(store.preferences.equipment.design, grove)
        XCTAssertEqual(store.savedMarketplaceEquipment, .empty,
                       "A saved empty outfit is distinct from no saved preferences.")
        let reopened = fixture.store()
        XCTAssertEqual(reopened.savedMarketplaceEquipment, .empty)
        XCTAssertTrue(reopened.preferences.equipment.isEmpty)
        XCTAssertEqual(reopened.itemLibrary, [grove])
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testUnreadableOutfitIsNotPresentedAsNoSavedOutfit() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let damaged = Data("unreadable profile".utf8)
        try damaged.write(to: fixture.preferences)
        let store = fixture.store()
        XCTAssertFalse(store.marketplaceOutfitReadable)
        XCTAssertNil(store.savedMarketplaceEquipment)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), damaged)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testKnownExternalConflictHidesStaleSavedOutfitUntilProfileReload() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = fixture.store()
        XCTAssertTrue(store.collectMarketItem(staff))
        XCTAssertTrue(store.collectMarketItem(grove))
        XCTAssertTrue(store.equipMarketItem(staff))
        store.rememberPreferences = true
        store.savePreferences()
        let current = store.preferences
        let library = store.itemLibrary
        var external = try NativePreferencePersistence.read(fixture.preferences).document
        external.revision += 1
        external.preferences?.equipment = CompanionEquipment(hand: .focusStaff, design: grove)
        let externalBytes = try external.encoded()
        try externalBytes.write(to: fixture.preferences)

        XCTAssertFalse(store.collectMarketItem(decoration))
        XCTAssertFalse(store.marketplaceOutfitReadable, "The app now knows its retained snapshot no longer matches disk.")
        XCTAssertNil(store.savedMarketplaceEquipment, "Do not claim the previous staff is still the next visit's outfit.")
        XCTAssertEqual(store.preferences, current)
        XCTAssertEqual(store.itemLibrary, library)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), externalBytes)

        try store.admitRestoredProfile()
        XCTAssertTrue(store.marketplaceOutfitReadable)
        XCTAssertEqual(store.savedMarketplaceEquipment?.design, grove)
        XCTAssertEqual(store.preferences.equipment.design, grove)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), externalBytes)
        store.blockProfileForRecovery("Synthetic recovery conflict")
        XCTAssertFalse(store.marketplaceOutfitReadable)
        XCTAssertNil(store.savedMarketplaceEquipment)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testSuccessfulCommitRestoresOutfitValidityAfterOriginalBaselineReturns() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = fixture.store()
        XCTAssertTrue(store.collectMarketItem(staff))
        XCTAssertTrue(store.equipMarketItem(staff))
        store.rememberPreferences = true
        store.savePreferences()
        let original = try NativePreferencePersistence.read(fixture.preferences)
        var external = original.document
        external.revision += 1
        external.preferences?.equipment = .empty
        try external.encoded().write(to: fixture.preferences)
        XCTAssertFalse(store.collectMarketItem(grove))
        XCTAssertFalse(store.marketplaceOutfitReadable)
        try XCTUnwrap(original.baseline).write(to: fixture.preferences)
        XCTAssertTrue(store.collectMarketItem(grove), "Exact baseline restoration permits the existing owner's explicit commit.")
        XCTAssertTrue(store.marketplaceOutfitReadable)
        XCTAssertEqual(store.savedMarketplaceEquipment?.design, staff)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testExternalDirectoryReplacementInvalidatesSavedOutfitAndPreservesDirectory() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = fixture.store()
        XCTAssertTrue(store.collectMarketItem(staff))
        XCTAssertTrue(store.equipMarketItem(staff))
        store.rememberPreferences = true
        store.savePreferences()
        let current = store.preferences
        let savedBytes = try Data(contentsOf: fixture.preferences)
        try FileManager.default.removeItem(at: fixture.preferences)
        try FileManager.default.createDirectory(at: fixture.preferences, withIntermediateDirectories: false)
        let externalFile = fixture.preferences.appendingPathComponent("external.txt")
        let externalBytes = Data("External replacement remains untouched.".utf8)
        try externalBytes.write(to: externalFile)

        XCTAssertFalse(store.collectMarketItem(grove))
        XCTAssertFalse(store.marketplaceOutfitReadable)
        XCTAssertNil(store.savedMarketplaceEquipment)
        XCTAssertEqual(store.preferences, current)
        XCTAssertEqual(store.itemLibrary, [staff])
        XCTAssertEqual(try fixture.preferences.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, true)
        XCTAssertEqual(try Data(contentsOf: externalFile), externalBytes)

        try FileManager.default.removeItem(at: fixture.preferences)
        try savedBytes.write(to: fixture.preferences)
        try store.admitRestoredProfile()
        XCTAssertTrue(store.marketplaceOutfitReadable)
        XCTAssertEqual(store.savedMarketplaceEquipment?.design, staff)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), savedBytes)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testWorkTogetherShortcutKeepsSourceSelectionOutfitAndProfileWithoutCallingTools() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = fixture.store()
        XCTAssertTrue(store.collectMarketItem(grove))
        XCTAssertTrue(store.equipMarketItem(grove))
        store.share(text: "A short passage for local review.", name: "Synthetic note.txt")
        store.selectText(range: NSRange(location: 2, length: 13), sourceRevision: store.sourceRevision)
        let selection = try XCTUnwrap(store.textSelection)
        let ticket = store.contextTicket()
        let preferences = store.preferences
        let bytes = try Data(contentsOf: fixture.preferences)
        var opened: [WorkspaceSection] = []
        var captureCalls = 0
        var observationCalls = 0
        store.onOpenWorkspace = { opened.append($0) }
        store.onBeginDesktopInterest = { captureCalls += 1 }
        store.onObserveSelectedPassage = { observationCalls += 1; return nil }
        store.onObserveSpatialEnvironment = { observationCalls += 1; return nil }
        store.section = .marketplace

        XCTAssertTrue(store.canUseMarketItemInWorkTogether(grove))
        XCTAssertTrue(store.useMarketItemInWorkTogether(grove))
        XCTAssertEqual(store.section, .context)
        XCTAssertEqual(opened, [.context])
        XCTAssertEqual(store.sharedText, "A short passage for local review.")
        XCTAssertEqual(store.sourceName, "Synthetic note.txt")
        XCTAssertEqual(store.textSelection, selection)
        XCTAssertEqual(store.contextTicket(), ticket)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertNil(store.focusGesturePlayback)
        XCTAssertNil(store.spatialPreview)
        XCTAssertFalse(store.isWorking)
        XCTAssertTrue(store.marketplaceMessage.contains("Point with staff"))
        XCTAssertEqual(captureCalls, 0)
        XCTAssertEqual(observationCalls, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), bytes)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testWorkTogetherRejectsUncollectedUnequippedDecorativeAndStaleDesigns() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = fixture.store()
        var opened: [WorkspaceSection] = []
        store.section = .marketplace
        store.onOpenWorkspace = { opened.append($0) }
        XCTAssertFalse(store.canUseMarketItemInWorkTogether(staff))
        XCTAssertFalse(store.useMarketItemInWorkTogether(staff))
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff, design: staff)
        XCTAssertFalse(store.useMarketItemInWorkTogether(staff), "Editing preferences cannot bypass collection membership.")
        XCTAssertTrue(store.collectMarketItem(staff))
        XCTAssertTrue(store.collectMarketItem(decoration))
        XCTAssertTrue(store.collectMarketItem(grove))
        XCTAssertTrue(store.equipMarketItem(decoration))
        XCTAssertFalse(store.canUseMarketItemInWorkTogether(decoration))
        XCTAssertFalse(store.useMarketItemInWorkTogether(decoration))
        XCTAssertTrue(store.equipMarketItem(grove))
        let current = store.preferences.equipment
        XCTAssertFalse(store.canUseMarketItemInWorkTogether(staff))
        XCTAssertFalse(store.useMarketItemInWorkTogether(staff), "A stale staff action cannot equip or use a previously selected recipe.")
        XCTAssertFalse(store.unequipMarketItem(staff), "A stale sheet cannot unequip the current different design.")
        XCTAssertEqual(store.preferences.equipment, current)
        XCTAssertEqual(store.section, .marketplace)
        XCTAssertTrue(opened.isEmpty)
        XCTAssertFalse(store.marketplaceMessage.contains("Work together is ready"))
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testUnequipRefreshesFeedbackForVisitAndLeavesSavedOutfitUntouched() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = fixture.store()
        XCTAssertTrue(store.collectMarketItem(staff))
        XCTAssertTrue(store.equipMarketItem(staff))
        XCTAssertTrue(store.unequipMarketItem(staff))
        XCTAssertTrue(store.marketplaceMessage.contains("No outfit is saved"))
        XCTAssertTrue(store.equipMarketItem(staff))
        store.rememberPreferences = true
        store.savePreferences()
        let saved = store.savedMarketplaceEquipment
        let savedBytes = try Data(contentsOf: fixture.preferences)
        XCTAssertTrue(store.unequipMarketItem(staff))
        XCTAssertTrue(store.preferences.equipment.isEmpty)
        XCTAssertTrue(store.marketplaceMessage.contains("unequipped for this visit"))
        XCTAssertTrue(store.marketplaceMessage.contains("saved outfit is unchanged"))
        XCTAssertEqual(store.savedMarketplaceEquipment, saved)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), savedBytes)
        XCTAssertFalse(store.unequipMarketItem(staff))
        XCTAssertTrue(store.marketplaceMessage.contains("not available to unequip"),
                      "Rejected repeated actions must not leave a success message behind.")
        let reopened = fixture.store()
        XCTAssertEqual(reopened.preferences.equipment, saved)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testShutdownRejectsWorkTogetherAndUnequipWithoutChangingOutfit() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = fixture.store()
        XCTAssertTrue(store.collectMarketItem(staff))
        XCTAssertTrue(store.equipMarketItem(staff))
        let equipment = store.preferences.equipment
        var opened: [WorkspaceSection] = []
        store.section = .marketplace
        store.onOpenWorkspace = { opened.append($0) }
        await store.shutdownAssistant()
        XCTAssertFalse(store.canUseMarketItemInWorkTogether(staff))
        XCTAssertFalse(store.useMarketItemInWorkTogether(staff))
        XCTAssertFalse(store.unequipMarketItem(staff))
        XCTAssertEqual(store.preferences.equipment, equipment)
        XCTAssertEqual(store.section, .marketplace)
        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let client = MarketplaceOutfitNoCalls()
        var preferences: URL { root.appendingPathComponent("preferences.json") }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-marketplace-outfit-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func store() -> CompanionStore {
            CompanionStore(preferenceURL: preferences, assistant: client,
                           assistantFactory: { _, _ in client }, allowsPlay: false)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

@MainActor
private final class MarketplaceOutfitNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.configuration
    }
    func disconnect() {}
}
