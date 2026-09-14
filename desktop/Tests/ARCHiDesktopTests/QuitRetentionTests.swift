import Foundation
import XCTest
@testable import ARCHiDesktop

final class QuitRetentionTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("archi-quit-\(UUID())")
        let store: CompanionStore
        var preferenceURL: URL { folder.appendingPathComponent("preferences.json") }
        var evolutionURL: URL { folder.appendingPathComponent("preferences.evolution.json") }

        init() {
            store = CompanionStore(preferenceURL: folder.appendingPathComponent("preferences.json"))
        }

        func cleanup() { try? FileManager.default.removeItem(at: folder) }
    }

    @MainActor
    func testCleanSessionQuitsWithoutPromptSavingOrImplicitEvolutionLoad() throws {
        let f = Fixture(); defer { f.cleanup() }
        f.store.evolution.confirmRole(.scout)
        XCTAssertTrue(f.store.evolution.save())
        let saved = try Data(contentsOf: f.evolutionURL)
        let reopened = CompanionStore(preferenceURL: f.preferenceURL)
        XCTAssertNil(reopened.evolution.confirmedRole, "Evolution Load stays explicit")
        XCTAssertTrue(reopened.confirmQuitRetainingWork(chooseEvolution: {
            XCTFail("A clean session should not show the Evolution prompt")
            return .review
        }))
        XCTAssertEqual(try Data(contentsOf: f.evolutionURL), saved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.preferenceURL.path))
    }

    @MainActor
    func testReviewKeepsSessionOpenAndNavigatesToExistingEvolutionWithoutSaving() {
        let f = Fixture(); defer { f.cleanup() }
        f.store.evolution.confirmHelpStyle(.stepByStep)
        f.store.prompt = "An unfinished question"
        var opened: [WorkspaceSection] = []
        f.store.onOpenWorkspace = { opened.append($0) }
        XCTAssertFalse(f.store.confirmQuitRetainingWork(chooseEvolution: { .review }))
        XCTAssertEqual(opened, [.evolution])
        XCTAssertEqual(f.store.prompt, "An unfinished question")
        XCTAssertEqual(f.store.evolution.confirmedHelpStyle, .stepByStep)
        XCTAssertTrue(f.store.evolution.hasUnsavedChanges)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.evolutionURL.path))
    }

    @MainActor
    func testDeliberateQuitWithoutSavingPreservesSessionAndEarlierSave() throws {
        let f = Fixture(); defer { f.cleanup() }
        f.store.evolution.confirmRole(.scout)
        XCTAssertTrue(f.store.evolution.save())
        let saved = try Data(contentsOf: f.evolutionURL)
        f.store.evolution.confirmRole(.muse)
        f.store.evolution.confirmFamily(.fen)
        XCTAssertNotNil(f.store.evolution.proposeEvolution())
        XCTAssertTrue(f.store.evolution.keepEvolution())
        let history = f.store.evolution.history
        XCTAssertTrue(f.store.confirmQuitRetainingWork(chooseEvolution: { .quitWithoutSaving }))
        XCTAssertEqual(try Data(contentsOf: f.evolutionURL), saved)
        XCTAssertEqual(f.store.evolution.confirmedRole, .muse)
        XCTAssertEqual(f.store.evolution.history, history)
        XCTAssertTrue(f.store.evolution.hasUnsavedChanges, "Approval is not an in-memory discard")
    }

    @MainActor
    func testSaveAndQuitWritesExistingEvolutionOwnerAndLeavesDraftAndVisitAppearanceAlone() throws {
        let f = Fixture(); defer { f.cleanup() }
        f.store.share(text: "Original passage", name: "original.txt")
        f.store.sharedText = "Session edits"
        f.store.preferences.form = .particle
        f.store.evolution.confirmRole(.keeper)
        f.store.evolution.confirmHelpStyle(.reflective)
        f.store.evolution.confirmFamily(.veil)
        XCTAssertNotNil(f.store.evolution.proposeEvolution())
        XCTAssertTrue(f.store.evolution.keepEvolution())
        let history = f.store.evolution.history
        var workingCopyReviews = 0
        XCTAssertTrue(f.store.confirmQuitRetainingWork(reviewWorkingCopy: {
            workingCopyReviews += 1
            return true
        }, chooseEvolution: { .saveAndQuit }))
        XCTAssertEqual(workingCopyReviews, 1)
        XCTAssertFalse(f.store.evolution.hasUnsavedChanges)
        XCTAssertTrue(f.store.hasUnexportedWorkingCopy, "Evolution Save must not falsely mark a document exported")
        XCTAssertEqual(f.store.sharedText, "Session edits")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.preferenceURL.path))
        let reopened = CompanionStore(preferenceURL: f.preferenceURL)
        XCTAssertNil(reopened.evolution.confirmedRole)
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertEqual(reopened.evolution.confirmedRole, .keeper)
        XCTAssertEqual(reopened.evolution.confirmedHelpStyle, .reflective)
        XCTAssertEqual(reopened.evolution.activeFamily, .veil)
        XCTAssertEqual(reopened.evolution.history, history)
        XCTAssertEqual(reopened.preferences.form, .companion, "Visit appearance remains unsaved")
    }

    @MainActor
    func testInvalidSavedEvolutionCannotBeReplacedThroughQuitAndFailureKeepsAppOpen() throws {
        let f = Fixture(); defer { f.cleanup() }
        try FileManager.default.createDirectory(at: f.folder, withIntermediateDirectories: true)
        let original = Data("Existing authored bytes that are not valid Evolution".utf8)
        try original.write(to: f.evolutionURL)
        f.store.evolution.confirmHelpStyle(.exploratory)
        XCTAssertFalse(f.store.confirmQuitRetainingWork(chooseEvolution: { .saveAndQuit }))
        XCTAssertEqual(try Data(contentsOf: f.evolutionURL), original)
        XCTAssertTrue(f.store.evolution.hasUnsavedChanges)
        XCTAssertTrue(f.store.evolution.requiresReplacement)
        XCTAssertEqual(f.store.section, .evolution)
        XCTAssertTrue(f.store.status.contains("staying open"))
    }

    @MainActor
    func testFailedWriteToBlockedPathKeepsAppOpenAndRetainsCurrentChoices() throws {
        let f = Fixture(); defer { f.cleanup() }
        // A regular file where the save's parent directory should be is a
        // deterministic write failure, independent of filesystem permissions.
        let blocked = Data("Do not replace this file".utf8)
        try blocked.write(to: f.folder)
        f.store.evolution.confirmRole(.beacon)
        XCTAssertFalse(f.store.confirmQuitRetainingWork(chooseEvolution: { .saveAndQuit }))
        XCTAssertEqual(try Data(contentsOf: f.folder), blocked)
        XCTAssertEqual(f.store.evolution.confirmedRole, .beacon)
        XCTAssertTrue(f.store.evolution.hasUnsavedChanges)
        XCTAssertEqual(f.store.section, .evolution)
    }

    @MainActor
    func testCancellingDocumentReviewDoesNotAdvanceToEvolutionOrSaveIt() {
        let f = Fixture(); defer { f.cleanup() }
        f.store.share(text: "Original", name: "draft.txt")
        f.store.sharedText = "Edited"
        f.store.evolution.confirmRole(.hearth)
        XCTAssertFalse(f.store.confirmQuitRetainingWork(reviewWorkingCopy: { false }, chooseEvolution: {
            XCTFail("Keep working on the document must stop the quit flow")
            return .saveAndQuit
        }))
        XCTAssertTrue(f.store.hasUnexportedWorkingCopy)
        XCTAssertTrue(f.store.evolution.hasUnsavedChanges)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.evolutionURL.path))
    }

    @MainActor
    func testDocumentChangingDuringItsReviewCannotReachEvolutionEvenWithOldDiscardApproval() {
        let f = Fixture(); defer { f.cleanup() }
        f.store.share(text: "Original", name: "draft.txt")
        f.store.sharedText = "Edited"
        f.store.evolution.confirmRole(.hearth)
        XCTAssertFalse(f.store.confirmQuitRetainingWork(reviewWorkingCopy: {
            f.store.sharedText = "A newer edit"
            return true
        }, chooseEvolution: {
            XCTFail("A stale document approval cannot advance to another prompt")
            return .quitWithoutSaving
        }))
        XCTAssertEqual(f.store.sharedText, "A newer edit")
        XCTAssertEqual(f.store.section, .context)
    }

    @MainActor
    func testEvolutionPromptCannotReuseEarlierDocumentApprovalAfterAnySourceChange() {
        for decision in [EvolutionQuitDecision.saveAndQuit, .quitWithoutSaving] {
            for mutation in 0..<3 {
                let f = Fixture(); defer { f.cleanup() }
                f.store.share(text: "Café", name: "draft.txt")
                f.store.evolution.confirmRole(.muse)
                XCTAssertFalse(f.store.confirmQuitRetainingWork(reviewWorkingCopy: { true }, chooseEvolution: {
                    switch mutation {
                    case 0: f.store.sharedText = "Cafe\u{301}"
                    case 1: f.store.sourceName = "another.txt"
                    default: f.store.sourceRevision &+= 1
                    }
                    return decision
                }))
                XCTAssertEqual(f.store.section, .context)
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.evolutionURL.path),
                    "Review changed source before any Evolution save on quit")
                XCTAssertTrue(f.store.evolution.hasUnsavedChanges)
            }
        }
    }

    @MainActor
    func testEvolutionEditAndReversionDuringPromptInvalidatesSaveAndDiscard() {
        for decision in [EvolutionQuitDecision.saveAndQuit, .quitWithoutSaving] {
            let f = Fixture(); defer { f.cleanup() }
            f.store.evolution.confirmRole(.muse)
            XCTAssertFalse(f.store.confirmQuitRetainingWork(chooseEvolution: {
                f.store.evolution.confirmRole(.scout)
                f.store.evolution.confirmRole(.muse)
                return decision
            }))
            XCTAssertEqual(f.store.evolution.confirmedRole, .muse)
            XCTAssertTrue(f.store.evolution.hasUnsavedChanges)
            XCTAssertEqual(f.store.section, .evolution)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.evolutionURL.path))
        }
    }

    @MainActor
    func testSaveDuringPromptWithoutRevisionChangeStillRetiresOldQuitDecision() {
        let f = Fixture(); defer { f.cleanup() }
        f.store.evolution.confirmRole(.scout)
        let revision = f.store.evolution.revision
        XCTAssertFalse(f.store.confirmQuitRetainingWork(chooseEvolution: {
            XCTAssertTrue(f.store.evolution.save())
            XCTAssertEqual(f.store.evolution.revision, revision)
            return .quitWithoutSaving
        }))
        XCTAssertFalse(f.store.evolution.hasUnsavedChanges)
        XCTAssertEqual(f.store.section, .evolution)
    }

    @MainActor
    func testEvolutionChangesDuringDocumentReviewAreIncludedInLaterPrompt() {
        let f = Fixture(); defer { f.cleanup() }
        var evolutionReviews = 0
        XCTAssertFalse(f.store.confirmQuitRetainingWork(reviewWorkingCopy: {
            f.store.evolution.confirmHelpStyle(.concise)
            return true
        }, chooseEvolution: {
            evolutionReviews += 1
            return .review
        }))
        XCTAssertEqual(evolutionReviews, 1)
        XCTAssertTrue(f.store.evolution.hasUnsavedChanges)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.evolutionURL.path))
    }
}
