import AppKit
import Testing
@testable import ARCHiDesktop

@MainActor
struct WorkingCopyStoreTests {
    @Test func applyTargetsExactOccurrenceAndUndoRestoresExactUnicodeBytes() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        let original = "Café 👩🏽‍💻. Repeat. Repeat. e\u{301}\r\n"
        let range = (original as NSString).range(of: "Repeat.", options: .backwards)
        try await rig.begin(text: original, range: range)
        let proposal = try rig.local.complete(replacement: "Revised!")
        try await rig.wait { rig.store.compareResults[.qwen]?.state == .complete }
        #expect(rig.store.sharedText == original, "Receiving a candidate cannot apply it")
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        #expect(rig.store.sharedText == "Café 👩🏽‍💻. Repeat. Revised! e\u{301}\r\n")
        #expect(rig.store.canUndoWorkingCopyEdit)
        let applied = rig.store.sharedText, revision = rig.store.sourceRevision
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        #expect(rig.store.sharedText == applied)
        #expect(rig.store.sourceRevision == revision)
        rig.store.undoWorkingCopyEdit()
        #expect(rig.store.sharedText.utf8.elementsEqual(original.utf8))
        #expect(rig.store.sourceRevision == revision + 1)
        #expect(!rig.store.canUndoWorkingCopyEdit)
    }

    @Test func compareCapturesSameTargetAndApplyCancelsUnfinishedSiblingAndLateOutput() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin(compare: true)
        let localRequest = try #require(rig.local.request)
        let cloudRequest = try #require(rig.cloud.request)
        #expect(localRequest.revisionTarget == cloudRequest.revisionTarget)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(localRequest.input.utf8)) ==
                    JSONDecoder().decode(JSONValue.self, from: Data(cloudRequest.input.utf8)))
        let proposal = try rig.local.complete(replacement: "Reviewed copy.")
        try await rig.wait { rig.store.compareResults[.qwen]?.state == .complete }
        #expect(rig.store.assistantActivity == .working)
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        #expect(!rig.store.isWorking)
        _ = try rig.cloud.complete(replacement: "Late conflicting copy.")
        await Task.yield()
        #expect(rig.store.sharedText == "Reviewed copy.")
        #expect(rig.store.compareResults.isEmpty)
        #expect(rig.store.canUndoWorkingCopyEdit)
    }

    @Test func stopSelectionPlacementAndSourceChangesRevokeCandidates() async throws {
        for change in 0..<4 {
            let rig = RevisionStoreRig(); defer { rig.drain() }
            try await rig.begin()
            let proposal = try rig.local.complete(replacement: "Revised copy.")
            try await rig.wait { !rig.store.isWorking }
            switch change {
            case 0: rig.store.cancelWork()
            case 1: rig.store.clearTextSelection()
            case 2: rig.store.placed(at: CGPoint(x: 10, y: 20))
            default: rig.store.share(text: "New source.", name: "new.txt")
            }
            let before = rig.store.sharedText, revision = rig.store.sourceRevision
            rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
            #expect(rig.store.sharedText == before)
            #expect(rig.store.sourceRevision == revision)
            #expect(!rig.store.canUndoWorkingCopyEdit)
            #expect(rig.store.compareResults.values.allSatisfy { $0.revision == nil })
        }
    }

    @Test func stoppedPendingRevisionCannotReturnAsReady() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        rig.store.cancelWork()
        _ = try rig.local.complete(replacement: "Too late.")
        await Task.yield()
        #expect(rig.store.assistantActivity == .stopped)
        #expect(rig.store.compareResults[.qwen]?.revision == nil)
        #expect(rig.store.sharedText == "Original copy.")
    }

    @Test func clarifyDismissWrongIDAndSourceMutationCannotApply() async throws {
        for mutation in 0..<4 {
            let rig = RevisionStoreRig(); defer { rig.drain() }
            try await rig.begin()
            let proposal = try rig.local.complete(replacement: mutation == 0 ? "" : "Revised copy.",
                decision: mutation == 0 ? .clarify : .propose)
            try await rig.wait { !rig.store.isWorking }
            if mutation == 1 { rig.store.dismissPassageRevision(provider: .qwen) }
            if mutation == 3 { rig.store.sharedText = "Intervening bytes." }
            let before = rig.store.sharedText
            rig.store.applyPassageRevision(provider: .qwen, targetID: mutation == 2 ? UUID().uuidString : proposal.target.id)
            #expect(rig.store.sharedText == before)
            #expect(!rig.store.canUndoWorkingCopyEdit)
        }
    }

    @Test func rawTextCannotMasqueradeAsRevisionAndModeChangesAffectOnlyNextSend() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        rig.store.requestsRevision = false
        rig.local.handler?(.text("An unstructured replacement."))
        rig.local.resolve()
        await Task.yield()
        #expect(rig.store.compareResults[.qwen]?.state == .failed)
        #expect(rig.store.sharedText == "Original copy.")
        #expect(rig.local.request?.revisionTarget != nil)
    }

    @Test func newerSharedCopyInvalidatesUndoEvenWithIdenticalBytes() async throws {
        let rig = RevisionStoreRig(); defer { rig.drain() }
        try await rig.begin()
        let proposal = try rig.local.complete(replacement: "Revised copy.")
        try await rig.wait { !rig.store.isWorking }
        rig.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        rig.store.share(text: rig.store.sharedText, name: "another.txt")
        rig.store.undoWorkingCopyEdit()
        #expect(rig.store.sharedText == "Revised copy.")
        #expect(!rig.store.canUndoWorkingCopyEdit)
    }

    @Test func exportVerifiesBytesPreservesOriginalRejectsStaleAndFailedWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.txt")
        let bytes = Data("Original 👩🏽‍💻 e\u{301}\r\n".utf8)
        try bytes.write(to: original)
        let rig = RevisionStoreRig(); defer { rig.drain() }
        #expect(rig.store.importWorkingCopy(from: original))
        let revision = rig.store.sourceRevision
        #expect(!rig.store.exportWorkingCopy(to: original, expectedRevision: revision))
        let alias = directory.appendingPathComponent("alias.txt")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        #expect(!rig.store.exportWorkingCopy(to: alias, expectedRevision: revision))
        let hardLink = directory.appendingPathComponent("hard-link.txt")
        try FileManager.default.linkItem(at: original, to: hardLink)
        #expect(!rig.store.exportWorkingCopy(to: hardLink, expectedRevision: revision))
        let caseAlias = directory.appendingPathComponent("ORIGINAL.TXT")
        if FileManager.default.fileExists(atPath: caseAlias.path) {
            #expect(!rig.store.exportWorkingCopy(to: caseAlias, expectedRevision: revision))
        }
        let draft = directory.appendingPathComponent("draft.txt")
        #expect(!rig.store.exportWorkingCopy(to: draft, expectedRevision: revision - 1))
        #expect(!FileManager.default.fileExists(atPath: draft.path))
        #expect(rig.store.exportWorkingCopy(to: draft, expectedRevision: revision))
        #expect(try Data(contentsOf: draft) == bytes)
        #expect(try Data(contentsOf: original) == bytes)
        #expect(!rig.store.exportWorkingCopy(to: original.appendingPathComponent("cannot-write.txt"), expectedRevision: revision))
        #expect(Data(rig.store.sharedText.utf8) == bytes)
        #expect(rig.store.sourceRevision == revision)
    }
}

@MainActor
private final class RevisionStoreRig {
    let local = RevisionStoreClient(), cloud = RevisionStoreClient()
    lazy var store = CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"), assistant: local,
        assistantFactory: { [cloud] _, _ in cloud }, tokenSteward: TokenStewardStore())

    func begin(text: String = "Original copy.", range: NSRange? = nil, compare: Bool = false) async throws {
        store.share(text: text, name: "fixture.txt")
        store.selectText(range: range ?? NSRange(location: 0, length: text.utf16.count), sourceRevision: store.sourceRevision)
        store.preparePassageRevision()
        if compare { store.setAssistantRoute(.compare) }
        store.connectAssistant()
        try await wait { store.connectionState == .ready }
        store.submit()
        try await wait { self.local.request != nil && (!compare || self.cloud.request != nil) }
    }
    func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw AssistantFailure.timedOut
    }
    func drain() {
        store.disconnectAssistant(provider: .qwen); store.disconnectAssistant(provider: .codex)
        local.resolve(); cloud.resolve()
    }
}

@MainActor
private final class RevisionStoreClient: AssistantClient {
    var request: AssistantRequest?
    var handler: (@MainActor (AssistantEvent) -> Void)?
    var continuation: CheckedContinuation<Void, Error>?
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        self.request = request; handler = onEvent
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete(replacement: String, decision: RevisionDecision = .propose) throws -> PassageRevisionProposal {
        let target = try #require(request?.revisionTarget)
        let proposal = PassageRevisionProposal(target: target, decision: decision, replacement: replacement,
            explanation: "Review the proposed wording.", sourceIDs: ["selected-passage"], memoryIDs: [])
        handler?(.revision(proposal)); resolve()
        return proposal
    }
    func resolve() { let pending = continuation; continuation = nil; pending?.resume() }
}
