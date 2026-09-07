import AppKit
import Combine
import UniformTypeIdentifiers
import CryptoKit

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case assistant = "Assistant"
    case play = "Habitat & Arena"
    case appearance = "Appearance"
    case evolution = "Evolution"
    case rhythm = "Personal rhythm"
    case memory = "What I remember"
    case context = "Work together"
    case connections = "Connections"
    case accessibility = "Accessibility"
    case advanced = "Advanced"
    var id: String { rawValue }
}

enum CompanionForm: String, CaseIterable, Identifiable, Codable {
    case companion = "Companion", light = "Guide light", ribbon = "Ribbon", ink = "Ink", pixel = "Pixel"
    var id: String { rawValue }
}

struct CompanionPreferences: Codable, Equatable {
    var form: CompanionForm = .companion
    var visualTreatment: CompanionVisualTreatment = .original
    var tone = "Calm"
    var replyLength = 0.35
    var size = 1.0
    var adaptive = true
    var reduceMotion = false
    var quiet = false

    var isValid: Bool {
        size.isFinite && (0.65...1.6).contains(size)
        && replyLength.isFinite && (0...1).contains(replyLength)
        && ["Calm", "Direct", "Playful", "Warm"].contains(tone)
    }
}

extension CompanionPreferences {
    // All historical fields retain their decoding requirements. Only the newly
    // introduced treatment can be absent from older saved preferences.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        form = try values.decode(CompanionForm.self, forKey: .form)
        visualTreatment = try values.decodeIfPresent(CompanionVisualTreatment.self, forKey: .visualTreatment) ?? .original
        tone = try values.decode(String.self, forKey: .tone)
        replyLength = try values.decode(Double.self, forKey: .replyLength)
        size = try values.decode(Double.self, forKey: .size)
        adaptive = try values.decode(Bool.self, forKey: .adaptive)
        reduceMotion = try values.decode(Bool.self, forKey: .reduceMotion)
        quiet = try values.decode(Bool.self, forKey: .quiet)
    }
}

struct ContextTicket: Equatable, Sendable {
    let generation: UInt64
    let placement: UInt64
    let source: UInt64
    let selection: UInt64
}

@MainActor
final class CompanionStore: ObservableObject {
    @Published var section: WorkspaceSection = .assistant
    @Published var preferences = CompanionPreferences() {
        didSet {
            if preferences != oldValue { invalidatePlacementPreview(reason: "Appearance or preferences changed. Preview again.") }
            refreshReactorReference()
        }
    }
    @Published var isVisible = true { didSet { refreshReactorReference() } }
    @Published var position = CGPoint.zero
    @Published var placementRevision: UInt64 = 0
    @Published var sharedText = ""
    @Published var sourceName: String?
    @Published var sourceRevision: UInt64 = 0
    @Published private(set) var textSelection: DocumentSelection?
    @Published private(set) var replySourceSelection: DocumentSelection?
    @Published private(set) var spatialPreview: SpatialPreview?
    @Published private(set) var lastPlacementReceipt: SpatialPlacementReceipt?
    @Published private(set) var isRecordingSpatial = false
    @Published private(set) var spatialRecordCount = 0
    @Published private(set) var spatialRecordingMessage = "Recording is off. Geometry stays in this session until you export it."
    @Published var spatialMessage = "Preview a spot without moving ARCHi."
    @Published var reply = "Choose a text document to bring some context into this workspace."
    @Published var prompt = ""
    @Published var requestsRevision = false
    @Published private(set) var workingCopyNotice = "Select a passage to begin."
    private var workingCopyUndo: WorkingCopyEditReceipt?
    private var openedWorkingCopyDigest: String?
    private var exportedWorkingCopyDigest: String?
    var hasUnexportedWorkingCopy: Bool {
        guard sourceName != nil, let openedWorkingCopyDigest else { return false }
        let current = SHA256.hash(data: Data(sharedText.utf8)).map { String(format: "%02x", $0) }.joined()
        return current != openedWorkingCopyDigest && current != exportedWorkingCopyDigest
    }
    private var importedSourceURL: URL?
    @Published var activity: [String] = []
    @Published var isWorking = false
    @Published private(set) var isShuttingDown = false
    @Published var connectionState: AssistantConnectionState = .disconnected
    @Published var connectionMessage = "Connect Qwen on this Mac when you are ready."
    @Published private(set) var assistantProvider: AssistantProvider
    @Published private(set) var route: AssistantRoute
    @Published private(set) var compareResults: [AssistantProvider: AssistantLaneResult] = [:]
    @Published private var connectionStates: [AssistantProvider: AssistantConnectionState] = [:]
    @Published private var connectionMessages: [AssistantProvider: String] = [:]
    @Published private(set) var qwenModel = QwenAssistant.defaultModel
    @Published private(set) var qwenContextModel = HamptonReasonsAssistant.defaultContextModel
    @Published private(set) var sessionContextEnabled = false
    @Published private(set) var hamptonSnapshot = HamptonAssistantSnapshot()
    @Published var rememberPreferences = false
    @Published private(set) var keptLessons: [KeptLesson] = []
    @Published private(set) var lessonRevision: UInt64 = 0
    @Published var lessonDraft: LessonCorrectionDraft?
    @Published private(set) var lessonMessage = "Keep only what you want ARCHi to use again."
    @Published var status = "Desktop preview · assistant not connected"
    var onShowCompanion: (() -> Void)?
    var onHideCompanion: (() -> Void)?
    var onOpenLab: (() -> Void)?
    var onOpenPlay: (() -> Void)?
    var onOpenWorkspace: ((WorkspaceSection) -> Void)?
    var selectedPassageObserverID: UUID?
    var onObserveSelectedPassage: (() -> SelectedPassageGeometry?)?
    var onObserveSpatialEnvironment: (() -> SpatialEnvironment?)?
    var onMoveCompanion: ((CGRect) -> Void)?
    var onPresentPlacementPreview: ((SpatialPreview?) -> Void)?
    private var workGeneration: UInt64 = 0
    private var selectionRevision: UInt64 = 0
    private var connectionGenerations: [AssistantProvider: UInt64] = [:]
    private var connectionTasks: [AssistantProvider: Task<Void, Never>] = [:]
    private var replyTasks: [AssistantProvider: Task<Void, Never>] = [:]
    private var replyOwners: [AssistantProvider: UUID] = [:]
    private var laneStartedAt: [AssistantProvider: TimeInterval] = [:]
    private var laneTimeoutTasks: [AssistantProvider: Task<Void, Never>] = [:]
    private var previewExpiryTask: Task<Void, Never>?
    private let spatialRecorder = SpatialRecorder()
    private let monotonicTime: () -> TimeInterval
    private var assistants: [AssistantProvider: any AssistantClient] = [:]
    private let assistantFactory: @MainActor (AssistantProvider, String) -> any AssistantClient
    private var retiringAssistants: [UUID: Task<Void, Never>] = [:]
    private let preferenceURL: URL
    private var preferenceDocument = NativePreferenceDocument()
    private var preferenceBaseline: Data?
    private var preferenceFileReadable = true
    private let wallClock: () -> Date
    let evolution: EvolutionStore
    let reactor = ReactorExpressionStore()
    private var evolutionSubscriptions = Set<AnyCancellable>()
    private var lastEvolutionAppearanceID: String?

    var nextReplySettings: AssistantSettingsSnapshot {
        AssistantSettingsSnapshot(tone: preferences.tone, replyLength: preferences.replyLength,
            role: evolution.confirmedRole, helpStyle: evolution.confirmedHelpStyle)
    }

    var assistantActivity: AssistantActivity {
        AssistantActivity.derive(owned: Set(replyOwners.keys), results: compareResults)
    }

    var assistantAccessibilityValue: String {
        CompanionVisualAsset.label(form: preferences.form, family: evolution.activeFamily,
            treatment: preferences.visualTreatment, recipe: evolution.activeAppearanceRecipe, naturalVariation: evolution.naturalVariation) + ". Assistant: " + assistantActivity.title
    }

    var nextCallBudget: String {
        let local = sessionContextEnabled ? "1 local answer call, plus up to 2 context calls" : "1 local answer call"
        switch route {
        case .local: return local
        case .codex: return "1 Codex request"
        case .compare: return local + " · 1 Codex request"
        }
    }

    init(preferenceURL: URL? = nil, assistant: (any AssistantClient)? = nil,
         provider: AssistantProvider = .qwen,
         assistantFactory: @escaping @MainActor (AssistantProvider, String) -> any AssistantClient = { provider, model in
             provider == .qwen ? HamptonReasonsAssistant(model: model) : CodexAssistant()
         },
         monotonicTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         wallClock: @escaping () -> Date = Date.init) {
        self.monotonicTime = monotonicTime
        self.wallClock = wallClock
        self.assistantProvider = provider
        self.route = provider == .qwen ? .local : .codex
        self.assistantFactory = assistantFactory
        self.assistants[provider] = assistant ?? assistantFactory(provider, QwenAssistant.defaultModel)
        self.connectionMessage = "Connect \(provider.destination) when you are ready."
        let resolvedPreferenceURL = preferenceURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ARCHiDesktop/preferences.json")
        self.preferenceURL = resolvedPreferenceURL
        do {
            let loaded = try NativePreferencePersistence.read(resolvedPreferenceURL)
            preferenceDocument = loaded.document
            preferenceBaseline = loaded.baseline
            keptLessons = loaded.document.lessons
            lessonRevision = loaded.document.revision
        } catch {
            preferenceFileReadable = false
            lessonMessage = "The saved settings file could not be read. It has been preserved; reopen after restoring a valid file before saving."
        }
        let initialPreferences = preferenceDocument.preferences
        self.evolution = EvolutionStore(origin: initialPreferences?.form ?? .companion,
            saveURL: resolvedPreferenceURL.deletingPathExtension().appendingPathExtension("evolution.json"))
        if let saved = initialPreferences {
            preferences = saved
            rememberPreferences = true
        }
        bindHamptonAssistant()
        evolution.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &evolutionSubscriptions)
        reactor.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &evolutionSubscriptions)
        $compareResults.combineLatest($isWorking).receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }; self.reactor.updateCue(self.assistantActivity)
        }.store(in: &evolutionSubscriptions)
        refreshReactorReference()
        lastEvolutionAppearanceID = CompanionVisualAsset.appearanceID(form: preferences.form,
            family: evolution.activeFamily, treatment: preferences.visualTreatment, recipe: evolution.activeAppearanceRecipe, naturalVariation: evolution.naturalVariation)
        evolution.$revision.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            let id = CompanionVisualAsset.appearanceID(form: self.preferences.form, family: self.evolution.activeFamily,
                treatment: self.preferences.visualTreatment, recipe: self.evolution.activeAppearanceRecipe, naturalVariation: self.evolution.naturalVariation)
            guard id != self.lastEvolutionAppearanceID else { return }
            self.lastEvolutionAppearanceID = id
            self.invalidatePlacementPreview(reason: "ARCHi's chosen appearance changed. Preview placement again.")
            self.refreshReactorReference()
        }.store(in: &evolutionSubscriptions)
    }

    func placed(at point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        position = point
        placementRevision &+= 1
        invalidateTextSelection(reason: "ARCHi moved. Select the passage again to restore its reference.")
        cancelWork(reason: "Placement changed; old spatial work cancelled.")
    }

    func showCompanion() { isVisible = true; onShowCompanion?() }
    func hideCompanion() {
        isVisible = false
        invalidateTextSelection(reason: "Companion hidden; passage reference cleared.")
        cancelWork(reason: "Companion hidden.")
        onHideCompanion?()
    }
    func open(_ section: WorkspaceSection) { self.section = section; onOpenWorkspace?(section) }

    func chooseDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a text document to share with ARCHi locally."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard confirmDiscardWorkingCopy(before: "changing documents", discardTitle: "Discard edits and change document") else { return }
        if importWorkingCopy(from: url) { open(.context) }
    }

    @discardableResult
    func importWorkingCopy(from url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 100_000 else {
                status = "Choose a text file smaller than 100 KB."; return false
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            share(text: text, name: url.lastPathComponent)
            importedSourceURL = url.resolvingSymlinksInPath().standardizedFileURL
            return true
        } catch { status = "Could not read that UTF-8 text document."; return false }
    }

    func share(text: String, name: String) {
        guard text.utf8.count <= 100_000 else {
            status = "Choose a text file no larger than 100 KB. The current source is unchanged."
            return
        }
        invalidateTextSelection(reason: "Shared source changed.")
        cancelWork(reason: "Shared source changed.")
        clearSessionContext()
        sharedText = text
        openedWorkingCopyDigest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        exportedWorkingCopyDigest = nil
        sourceName = name
        importedSourceURL = nil
        workingCopyUndo = nil
        requestsRevision = false
        workingCopyNotice = "Working copy opened · select a passage to begin."
        sourceRevision &+= 1
        compareResults = [:]
        reply = "This copy is shared locally. Send a question using your chosen assistant route."
        status = "Shared locally · no content sent"
        record("Opened \(name) locally")
    }

    /// User-facing retention check; programmatic sharing and test helpers keep
    /// their existing deterministic behavior through stopSharing().
    func requestStopSharing() {
        guard confirmDiscardWorkingCopy(before: "stopping sharing", discardTitle: "Discard edits and stop sharing") else { return }
        stopSharing()
    }

    func confirmQuitWithWorkingCopy() -> Bool {
        confirmDiscardWorkingCopy(before: "quitting", discardTitle: "Quit without exporting")
    }

    private func confirmDiscardWorkingCopy(before action: String, discardTitle: String) -> Bool {
        guard hasUnexportedWorkingCopy else { return true }
        let reviewedRevision = sourceRevision
        let reviewedSourceName = sourceName
        let reviewedBytes = Data(sharedText.utf8)
        let alert = NSAlert()
        alert.messageText = "Keep this draft before \(action)?"
        alert.informativeText = "Your working copy has edits that have not been exported. Keep working to export a separate draft, or discard these session edits. The original file stays unchanged."
        alert.alertStyle = .warning
        let keep = alert.addButton(withTitle: "Keep working")
        keep.keyEquivalent = "\r"
        let discard = alert.addButton(withTitle: discardTitle)
        discard.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        // A modal alert can service callbacks. Discard approval belongs only to
        // the exact working copy reviewed when this alert was presented.
        guard sourceRevision == reviewedRevision, sourceName == reviewedSourceName,
              Data(sharedText.utf8) == reviewedBytes else {
            workingCopyNotice = "The working copy changed while this choice was open. Your latest copy is unchanged; review it before discarding."
            return false
        }
        return true
    }

    func stopSharing() {
        invalidateTextSelection(reason: "Sharing stopped.")
        cancelWork(reason: "Sharing stopped.")
        clearSessionContext()
        sharedText = ""; sourceName = nil; sourceRevision &+= 1
        openedWorkingCopyDigest = nil; exportedWorkingCopyDigest = nil
        importedSourceURL = nil; workingCopyUndo = nil; requestsRevision = false
        workingCopyNotice = "Select a text document to begin."
        compareResults = [:]
        reply = "Nothing is shared."
        status = "Shared context cleared"
    }

    func selectText(range: NSRange, sourceRevision: UInt64) {
        // Late native callbacks from a replaced document cannot clear or replace a newer selection.
        guard sourceName != nil, sourceRevision == self.sourceRevision else { return }
        if range.length == 0 {
            guard range.location >= 0, range.location <= sharedText.utf16.count else { return }
            clearTextSelection(); return
        }
        guard let selection = DocumentSelection(range: range, text: sharedText, sourceRevision: sourceRevision),
              selection != textSelection else { return }
        invalidateTextSelection(reason: "Selected passage changed.")
        cancelWork(reason: "Selected passage changed.")
        textSelection = selection
        selectionRevision &+= 1
        workingCopyNotice = "Passage selected · ask about it or prepare a revision."
        status = "Passage selected · nothing sent"
    }

    func clearTextSelection() { invalidateTextSelection(reason: "Passage selection cleared.") }

    func invalidateTextSelection(reason: String) {
        invalidatePlacementPreview(reason: reason)
        guard textSelection != nil || replySourceSelection != nil else { return }
        let hadScopedReply = replySourceSelection != nil
        textSelection = nil
        replySourceSelection = nil
        selectionRevision &+= 1
        cancelWork(reason: reason)
        if hadScopedReply {
            hamptonSnapshot.proposal = nil
            compareResults = [:]
            reply = "The passage reference changed. Select text again to ask about it."
        }
        status = reason
    }

    func askAboutSelection() {
        guard let selection = textSelection, selection.matches(text: sharedText, sourceRevision: sourceRevision) else {
            status = "Select a passage in the document first."; return
        }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt = "Explain the selected passage."
        }
        status = "Question ready · press Send when you are ready"
    }

    func preparePassageExplanation() {
        requestsRevision = false
        prompt = "Explain the selected passage."
        askAboutSelection()
    }

    func preparePassageRevision(shorten: Bool = false) {
        guard let textSelection, textSelection.matches(text: sharedText, sourceRevision: sourceRevision) else {
            status = "Select a passage in the document first."; return
        }
        requestsRevision = true
        prompt = shorten ? "Shorten the selected passage while preserving its meaning."
            : "Make the selected passage clearer while preserving its meaning."
        status = "Revision prepared · describe what you want, then Send"
    }

    var canUndoWorkingCopyEdit: Bool {
        workingCopyUndo?.canUndo(text: sharedText, revision: sourceRevision) == true
    }

    /// A candidate stays inside its original lane until this explicit action.
    /// There is no await between checking the exact source and replacing it.
    func applyPassageRevision(provider: AssistantProvider, targetID: String) {
        guard let lane = compareResults[provider], lane.state == .complete,
              let proposal = lane.revision, proposal.decision == .propose,
              proposal.target.id == targetID, let receipt = lane.receipt,
              isCurrent(receipt.context, requireVisible: false),
              textSelection == proposal.target.selection else {
            workingCopyNotice = "This revision is no longer current. Select the passage and request a new one."; return
        }
        do {
            let before = sharedText
            let after = try WorkingCopyEditReceipt.applying(proposal: proposal, to: before, sourceRevision: sourceRevision)
            // Cancels a still-running Compare sibling and revokes both previews.
            invalidateTextSelection(reason: "A reviewed revision was applied.")
            cancelWork(reason: "Working copy changed; earlier proposals cleared.")
            clearSessionContext()
            sharedText = after
            sourceRevision &+= 1
            compareResults = [:]
            workingCopyUndo = WorkingCopyEditReceipt(before: before,
                afterDigest: SHA256.hash(data: Data(after.utf8)).map { String(format: "%02x", $0) }.joined(),
                afterRevision: sourceRevision)
            requestsRevision = false
            guard sharedText.utf8.elementsEqual(after.utf8), canUndoWorkingCopyEdit else {
                workingCopyNotice = "The working copy could not be verified."; return
            }
            workingCopyNotice = "Applied to working copy · Undo is available. Export to keep a separate draft."
            reply = proposal.explanation
            status = "Reviewed revision applied · original file unchanged"
            record("Applied reviewed \(provider.name) passage revision \(targetID) to working copy revision \(sourceRevision)")
        } catch {
            workingCopyNotice = "This revision could not be applied to the current copy. Nothing changed."
        }
    }

    func dismissPassageRevision(provider: AssistantProvider) {
        guard compareResults[provider]?.state == .complete else { return }
        compareResults[provider]?.revision = nil
        compareResults[provider]?.status = "Revision dismissed · copy unchanged"
        workingCopyNotice = "Revision dismissed · your working copy is unchanged."
    }

    func undoWorkingCopyEdit() {
        guard let undo = workingCopyUndo, undo.canUndo(text: sharedText, revision: sourceRevision) else {
            workingCopyNotice = "That Undo belongs to an earlier copy and cannot change this one."; return
        }
        invalidateTextSelection(reason: "Working-copy revision undone.")
        cancelWork(reason: "Working-copy revision undone.")
        clearSessionContext()
        sharedText = undo.before
        sourceRevision &+= 1
        compareResults = [:]
        workingCopyUndo = nil
        requestsRevision = false
        workingCopyNotice = "Undone · the exact previous working copy is restored."
        status = workingCopyNotice
        record("Undid working-copy edit; source revision \(sourceRevision)")
    }

    func exportWorkingCopy() {
        guard sourceName != nil else { return }
        let revision = sourceRevision
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.utf8PlainText]
        let stem = ((sourceName ?? "ARCHi") as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(stem)-draft.txt"
        panel.message = "Save a separate UTF-8 draft of the working copy."
        guard panel.runModal() == .OK, let url = panel.url else {
            workingCopyNotice = "Export cancelled · your working copy is unchanged."; return
        }
        _ = exportWorkingCopy(to: url, expectedRevision: revision)
    }

    @discardableResult
    func exportWorkingCopy(to url: URL, expectedRevision: UInt64) -> Bool {
        guard sourceName != nil, sourceRevision == expectedRevision,
              url.isFileURL, sharedText.utf8.count <= 100_000 else {
            workingCopyNotice = "The copy changed while choosing a destination. Export the current copy again."; return false
        }
        let destination = url.resolvingSymlinksInPath().standardizedFileURL
        guard destination != importedSourceURL && !isImportedFile(destination) else {
            workingCopyNotice = "Choose a separate draft filename to preserve the imported original."; return false
        }
        let bytes = Data(sharedText.utf8)
        do {
            try bytes.write(to: url, options: .atomic)
            guard try Data(contentsOf: url) == bytes else {
                workingCopyNotice = "The exported file could not be verified. Your working copy is retained."; return false
            }
            exportedWorkingCopyDigest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            workingCopyNotice = "Exported \(url.lastPathComponent) · saved bytes verified."
            status = workingCopyNotice
            return true
        } catch {
            workingCopyNotice = "The draft could not be exported. Your working copy is retained."
            return false
        }
    }

    private func isImportedFile(_ destination: URL) -> Bool {
        guard let importedSourceURL,
              let original = try? FileManager.default.attributesOfItem(atPath: importedSourceURL.path),
              let candidate = try? FileManager.default.attributesOfItem(atPath: destination.path),
              let originalDevice = original[.systemNumber] as? NSNumber,
              let originalInode = original[.systemFileNumber] as? NSNumber,
              let candidateDevice = candidate[.systemNumber] as? NSNumber,
              let candidateInode = candidate[.systemFileNumber] as? NSNumber else { return false }
        // Covers case aliases and hard links in addition to resolved URL equality.
        return originalDevice == candidateDevice && originalInode == candidateInode
    }

    func cancelWork(reason: String = "Stopped.") {
        invalidatePlacementPreview(reason: reason)
        let wasWorking = isWorking
        let hadDerivedReply = !compareResults.isEmpty || hamptonSnapshot.proposal != nil
        workGeneration &+= 1
        for provider in Array(replyOwners.keys) { cancelLane(provider, reason: reason) }
        // Completed lanes are also bound to the superseded request ticket.
        for provider in Array(compareResults.keys) {
            setLane(provider, text: "", status: reason, state: .cancelled)
        }
        if wasWorking || hadDerivedReply {
            hamptonSnapshot.proposal = nil
            replySourceSelection = nil
            // A global source/position invalidation also removes a sibling that
            // finished before the other lane. Neither result has a current ticket.
            reply = wasWorking ? "The previous response was stopped."
                : "The previous answer was cleared because its context changed."
            status = reason
            workingCopyNotice = "Earlier work cleared · your working copy is unchanged."
        }
        isWorking = !replyOwners.isEmpty
        refreshRouteConnection()
        if activity.last != reason { record(reason) }
    }

    func submit() {
        guard !isShuttingDown else { return }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard prompt.utf8.count <= 16_000 else { status = "Keep the message below 16 KB. Nothing was sent."; return }
        guard textSelection == nil || textSelection?.matches(text: sharedText, sourceRevision: sourceRevision) == true else {
            invalidateTextSelection(reason: "The selected passage is no longer current. Nothing was sent.")
            return
        }
        let revisionTarget: RevisionTarget?
        if requestsRevision {
            guard let selection = textSelection,
                  let target = RevisionTarget(text: sharedText, sourceRevision: sourceRevision, selection: selection) else {
                status = "Select a current passage before requesting a revision. Nothing was sent."; return
            }
            revisionTarget = target
        } else { revisionTarget = nil }
        cancelWork(reason: "New request replaces prior work.")
        let selectedRoute = route
        guard selectedRoute.providers.allSatisfy({ connection(for: $0) == .ready }) else {
            replySourceSelection = nil
            compareResults = [:]
            reply = "Connect \(selectedRoute == .compare ? "both assistants" : assistantProvider.name) to send this message. This request has not been sent."
            status = "Not sent · assistant not connected"
            return
        }
        let ticket = contextTicket()
        if selectedRoute.providers.contains(.qwen) { hamptonSnapshot.proposal = nil }
        let request = AssistantRequest(prompt: prompt, sourceName: sourceName, sourceText: sharedText,
            sourceRevision: sourceRevision, placementRevision: placementRevision, settings: nextReplySettings,
            selection: textSelection, revisionTarget: revisionTarget)
        replySourceSelection = textSelection
        // The same immutable current-input contract is dispatched to both lanes.
        // Hampton may add local-only excerpts internally; no answer is forwarded.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let input = try? JSONDecoder().decode(JSONValue.self, from: Data(request.input.utf8)),
              let bytes = try? encoder.encode(input) else {
            status = "The current request could not be prepared. Nothing was sent."; return
        }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let requestID = UUID().uuidString
        compareResults = [:]
        isWorking = true; reply = ""; status = "Sending · \(selectedRoute.title)…"
        if revisionTarget != nil { workingCopyNotice = "Preparing a revision · your working copy is unchanged." }
        let capturedLessons = matchingLessons(question: request.prompt)
        for provider in selectedRoute.providers {
            let laneRequest = AssistantRequest(prompt: request.prompt, sourceName: request.sourceName,
                sourceText: request.sourceText, sourceRevision: request.sourceRevision,
                placementRevision: request.placementRevision, settings: request.settings,
                selection: request.selection, localLessons: provider == .qwen ? capturedLessons : [],
                revisionTarget: request.revisionTarget)
            launchLane(provider, request: laneRequest, ticket: ticket, route: selectedRoute,
                       requestID: requestID, inputDigest: digest)
        }
    }

    private func launchLane(_ provider: AssistantProvider, request: AssistantRequest, ticket: ContextTicket,
                            route: AssistantRoute, requestID: String, inputDigest: String) {
        let assistant = client(for: provider)
        let owner = UUID(), epoch = connectionGenerations[provider, default: 0]
        let seconds = provider == .qwen ? 180 : 90
        let deadline = Date().addingTimeInterval(Double(seconds))
        replyOwners[provider] = owner
        laneStartedAt[provider] = monotonicTime()
        compareResults[provider] = AssistantLaneResult(text: "", status: "Preparing \(provider.name) answer…", state: .pending,
            receipt: AssistantLaneReceipt(requestID: requestID, route: route, provider: provider, context: ticket,
                inputDigest: inputDigest, inputContract: AssistantRequest.inputContract, deadline: deadline,
                modelIdentity: nil, state: .pending, settings: request.settings,
                localInvocations: assistant is HamptonReasonsAssistant ? [] : nil))
        compareResults[provider]?.receipt?.sourceDigest = SHA256.hash(data: Data(request.sourceText.utf8))
            .map { String(format: "%02x", $0) }.joined()
        compareResults[provider]?.receipt?.localLessons = request.localLessons
        compareResults[provider]?.receipt?.localLessonDigest = request.localLessonDigest
        if let local = assistant as? HamptonReasonsAssistant {
            local.onSnapshot = { [weak self, weak local] snapshot in
                guard let self, let local,
                      self.isCurrentLane(provider, owner: owner, epoch: epoch, client: local, ticket: ticket) else { return }
                self.hamptonSnapshot = snapshot
                self.compareResults[provider]?.receipt?.usedLessonIDs = snapshot.proposal?.memoryIDs.filter {
                    request.localLessons.map(\.modelID).contains($0)
                } ?? []
                self.compareResults[provider]?.receipt?.localInvocations = snapshot.attemptedInvocations
                if let receipt = snapshot.receipts.last(where: { $0.role == .reasoning }) {
                    self.compareResults[provider]?.receipt?.modelIdentity = receipt.model.name + " @ " + receipt.model.digest
                }
                self.compareResults[provider]?.status = snapshot.phase
                if self.route != .compare { self.status = snapshot.phase }
            }
        }
        laneTimeoutTasks[provider] = Task { [weak self, assistant] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket) else { return }
            self.failLane(provider, message: "\(provider.name) reached its \(seconds)-second reply limit.")
        }
        replyTasks[provider] = Task { [weak self, assistant] in
            do {
                guard let self, self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket), !Task.isCancelled else { return }
                self.compareResults[provider]?.receipt?.requestStarted = true
                try await assistant.reply(to: request) { [weak self] event in
                    guard let self, self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket) else { return }
                    switch event {
                    case .text(let text):
                        guard request.revisionTarget == nil else {
                            self.failLane(provider, message: "The revision response was not a validated proposal."); return
                        }
                        self.setLane(provider, text: text, status: "\(provider.name) is replying…", state: .pending)
                        if provider == self.assistantProvider { self.reply = text }
                        self.status = self.route == .compare ? "Receiving independent answers…" : "ARCHi is replying…"
                    case .revision(let proposal):
                        guard proposal.target == request.revisionTarget,
                              proposal.target.matches(text: self.sharedText, sourceRevision: self.sourceRevision) else {
                            self.failLane(provider, message: "The revision target changed. Select the passage again."); return
                        }
                        self.compareResults[provider]?.revision = proposal
                        self.compareResults[provider]?.receipt?.usedLessonIDs = proposal.memoryIDs.filter {
                            request.localLessons.map(\.modelID).contains($0)
                        }
                        self.setLane(provider, text: proposal.explanation, status: "Revision received · validating completion", state: .pending)
                        if provider == self.assistantProvider { self.reply = proposal.explanation }
                    }
                }
                guard self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket), !Task.isCancelled else { return }
                if request.revisionTarget != nil && self.compareResults[provider]?.revision == nil {
                    self.failLane(provider, message: "No validated revision completed. Your copy is unchanged."); return
                }
                self.finishOwnership(provider)
                self.setLane(provider, status: request.revisionTarget == nil ? "Reply ready" : "Revision ready for review", state: .complete)
                if request.revisionTarget != nil {
                    self.workingCopyNotice = "Review Before and After. Apply changes only the working copy."
                }
                self.refreshWorkStatus()
                self.record("\(provider.name) reply received for shared source revision \(ticket.source)")
            } catch {
                guard let self, self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket), !Task.isCancelled else { return }
                self.failLane(provider, message: (error as? LocalizedError)?.errorDescription ?? "The assistant connection stopped. Try connecting again.")
            }
        }
    }

    func connection(for provider: AssistantProvider) -> AssistantConnectionState { connectionStates[provider] ?? .disconnected }
    func message(for provider: AssistantProvider) -> String {
        connectionMessages[provider] ?? "Connect \(provider.destination) when you are ready."
    }

    func connectAssistant() { for provider in route.providers { connectAssistant(provider: provider) } }

    func connectAssistant(provider: AssistantProvider) {
        guard !isShuttingDown, connection(for: provider) != .connecting, connection(for: provider) != .ready else { return }
        let assistant = client(for: provider)
        connectionGenerations[provider, default: 0] &+= 1
        let generation = connectionGenerations[provider, default: 0]
        connectionStates[provider] = .connecting
        connectionMessages[provider] = provider == .qwen
            ? "Checking the installed local Qwen model…"
            : "Checking your existing Codex account and shared-text connection…"
        refreshRouteConnection()
        connectionTasks[provider] = Task { [weak self, assistant] in
            do {
                try await assistant.connect()
                guard let self, !self.isShuttingDown, self.assistants[provider] === assistant,
                      self.connectionGenerations[provider] == generation, !Task.isCancelled else { return }
                self.connectionStates[provider] = .ready; self.connectionTasks[provider] = nil
                self.connectionMessages[provider] = provider == .qwen
                    ? "\(self.qwenModel) is available locally. Send runs inference on this Mac; the first reply may take longer to load."
                    : "Connected through your ChatGPT login. Send includes only your message and shared copy."
                self.refreshRouteConnection()
                if self.route.providers.contains(provider), !self.isWorking { self.status = "\(provider.name) connected · nothing sent yet" }
            } catch {
                guard let self, !self.isShuttingDown, self.assistants[provider] === assistant,
                      self.connectionGenerations[provider] == generation, !Task.isCancelled else { return }
                self.connectionStates[provider] = .failed; self.connectionTasks[provider] = nil
                self.connectionMessages[provider] = (error as? LocalizedError)?.errorDescription ?? "Could not connect to \(provider.name). Try again."
                self.refreshRouteConnection()
                if self.route.providers.contains(provider), !self.isWorking { self.status = self.message(for: provider) }
            }
        }
    }

    func disconnectAssistant() {
        for provider in route.providers { disconnectAssistant(provider: provider) }
    }

    func disconnectAssistant(provider: AssistantProvider) {
        let hadWork = replyOwners[provider] != nil
        cancelLane(provider, reason: "\(provider.name) disconnected.")
        if !hadWork { closeConnection(provider) }
        connectionMessages[provider] = "Disconnected. Your shared copy stays here until you stop sharing."
        refreshRouteConnection()
        if !isWorking { status = "\(provider.name) disconnected" }
    }

    func setAssistantRoute(_ selected: AssistantRoute) {
        guard !isShuttingDown, selected != route else { return }
        cancelWork(reason: "Assistant route changed.")
        route = selected; assistantProvider = selected.primaryProvider
        for provider in selected.providers { _ = client(for: provider) }
        compareResults = [:]; replySourceSelection = nil; hamptonSnapshot.proposal = nil
        reply = "\(selected.title) selected. Send when you are ready."
        refreshRouteConnection()
        status = "Assistant route changed · nothing sent"
    }

    func selectAssistantProvider(_ provider: AssistantProvider) {
        setAssistantRoute(provider == .qwen ? .local : .codex)
    }

    func selectQwenModel(_ model: String) {
        guard !isShuttingDown, QwenAssistant.supportedModels.contains(model), model != qwenModel else { return }
        qwenModel = model
        replaceLocalAssistant()
    }

    func selectQwenContextModel(_ model: String) {
        guard !isShuttingDown, QwenAssistant.supportedModels.contains(model), model != qwenContextModel else { return }
        qwenContextModel = model
        replaceLocalAssistant()
    }

    func setSessionContextEnabled(_ enabled: Bool) {
        guard !isShuttingDown, sessionContextEnabled != enabled else { return }
        cancelLocalWork(reason: "Session context setting changed.")
        sessionContextEnabled = enabled
        (assistants[.qwen] as? HamptonReasonsAssistant)?.setContextEnabled(enabled)
        hamptonSnapshot = (assistants[.qwen] as? HamptonReasonsAssistant)?.snapshot ?? HamptonAssistantSnapshot()
        if route == .local {
            replySourceSelection = nil
            reply = enabled ? "Temporary context is on for local Qwen. Send a question to begin." : "Temporary context is off and has been cleared."
        }
        if !isWorking { status = enabled ? "Session context enabled · nothing sent" : "Session context cleared" }
    }

    func clearSessionContext() {
        cancelLocalWork(reason: "Session context cleared.")
        (assistants[.qwen] as? HamptonReasonsAssistant)?.clearSessionContext()
        hamptonSnapshot = HamptonAssistantSnapshot(phase: "Session context cleared")
        if route == .local {
            replySourceSelection = nil
            reply = "Session context cleared. Your current draft and shared copy stay here."
        }
        if !isWorking { status = "Session context cleared" }
    }

    private func bindHamptonAssistant() {
        hamptonSnapshot = HamptonAssistantSnapshot()
        guard let client = assistants[.qwen] as? HamptonReasonsAssistant else { return }
        client.setContextModel(qwenContextModel)
        client.setContextEnabled(sessionContextEnabled)
        hamptonSnapshot = client.snapshot
        // Each reply installs a callback bound to its own operation and ticket.
        client.onSnapshot = nil
    }

    private func replaceLocalAssistant() {
        guard let previous = assistants[.qwen] else { return }
        cancelLocalWork(reason: "Local model changed.")
        closeConnection(.qwen)
        (previous as? HamptonReasonsAssistant)?.onSnapshot = nil
        (previous as? HamptonReasonsAssistant)?.clearSessionContext()
        assistants[.qwen] = assistantFactory(.qwen, qwenModel)
        bindHamptonAssistant()
        if route == .local {
            invalidateTextSelection(reason: "Local model changed. Select the passage again to restore its reference.")
            replySourceSelection = nil
            reply = "The local model changed. Connect Qwen, then Send when you are ready."
        }
        connectionMessages[.qwen] = "Connect Qwen on this Mac when you are ready."
        refreshRouteConnection()
        if !isWorking { status = "Local model changed · nothing sent" }
        let retirement = UUID()
        retiringAssistants[retirement] = Task { [weak self, previous] in
            await previous.shutdown()
            self?.retiringAssistants[retirement] = nil
        }
    }

    func shutdownAssistant() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        cancelWork(reason: "App is shutting down.")
        let current = Array(assistants.values)
        for provider in Array(assistants.keys) { closeConnection(provider) }
        // Begin both cleanups before awaiting either; one slow child cannot hide
        // another owned process from shutdown.
        let cleanup = current.map { client in Task { await client.shutdown() } }
        for task in cleanup { await task.value }
        hamptonSnapshot = HamptonAssistantSnapshot(phase: "Session context cleared")
        for retirement in Array(retiringAssistants.values) { await retirement.value }
    }

    private func client(for provider: AssistantProvider) -> any AssistantClient {
        if let existing = assistants[provider] { return existing }
        let created = assistantFactory(provider, qwenModel)
        assistants[provider] = created
        if provider == .qwen { bindHamptonAssistant() }
        return created
    }

    private func isCurrentLane(_ provider: AssistantProvider, owner: UUID, epoch: UInt64,
                               client: any AssistantClient, ticket: ContextTicket) -> Bool {
        !isShuttingDown && replyOwners[provider] == owner && assistants[provider] === client
            && connectionGenerations[provider, default: 0] == epoch
            && isCurrent(ticket, requireVisible: false)
    }

    private func finishOwnership(_ provider: AssistantProvider) {
        if let local = assistants[provider] as? HamptonReasonsAssistant,
           let attempts = local.inFlightInvocations {
            compareResults[provider]?.receipt?.localInvocations = attempts
        }
        if let started = laneStartedAt.removeValue(forKey: provider) {
            compareResults[provider]?.receipt?.elapsedMilliseconds = max(0, Int((monotonicTime() - started) * 1000))
        }
        replyOwners[provider] = nil
        replyTasks[provider] = nil
        laneTimeoutTasks.removeValue(forKey: provider)?.cancel()
        isWorking = !replyOwners.isEmpty
    }

    private func closeConnection(_ provider: AssistantProvider) {
        connectionGenerations[provider, default: 0] &+= 1
        connectionTasks.removeValue(forKey: provider)?.cancel()
        assistants[provider]?.disconnect()
        connectionStates[provider] = .disconnected
        refreshRouteConnection()
    }

    private func cancelLane(_ provider: AssistantProvider, reason: String) {
        guard replyOwners[provider] != nil else { return }
        replyTasks[provider]?.cancel()
        finishOwnership(provider)
        closeConnection(provider)
        setLane(provider, text: "", status: reason, state: .cancelled)
        connectionMessages[provider] = "Response stopped. Connect again when you are ready."
        if provider == .qwen { hamptonSnapshot.proposal = nil }
        if provider == assistantProvider { reply = "The previous response was stopped." }
        if !isWorking { replySourceSelection = nil }
        refreshRouteConnection()
        refreshWorkStatus()
    }

    private func cancelLocalWork(reason: String) {
        let hadLocalWork = replyOwners[.qwen] != nil
        cancelLane(.qwen, reason: reason)
        if hadLocalWork && !isWorking && route == .local { workGeneration &+= 1 }
        // Completed local answers can refer to excerpts that have just been
        // revoked, so remove that lane while leaving Codex's result intact.
        if compareResults[.qwen] != nil { setLane(.qwen, text: "", status: reason, state: .cancelled) }
    }

    private func failLane(_ provider: AssistantProvider, message: String) {
        replyTasks[provider]?.cancel()
        finishOwnership(provider)
        closeConnection(provider)
        connectionStates[provider] = .failed
        connectionMessages[provider] = message
        setLane(provider, text: "", status: message, state: .failed)
        workingCopyNotice = "\(provider.name) could not finish · your working copy is unchanged."
        if provider == .qwen { hamptonSnapshot.proposal = nil }
        if provider == assistantProvider { reply = "This reply did not finish." }
        if !isWorking && route != .compare { replySourceSelection = nil }
        refreshRouteConnection()
        refreshWorkStatus()
    }

    private func setLane(_ provider: AssistantProvider, text: String? = nil, status: String, state: AssistantLaneState) {
        guard var result = compareResults[provider] else { return }
        if let text { result.text = text }
        if state == .cancelled || state == .failed { result.revision = nil }
        result.status = status; result.state = state; result.receipt?.state = state
        compareResults[provider] = result
    }

    private func refreshRouteConnection() {
        if route == .compare {
            let states = route.providers.map { connection(for: $0) }
            connectionState = states.allSatisfy { $0 == .ready } ? .ready
                : states.contains(.connecting) ? .connecting : states.contains(.failed) ? .failed : .disconnected
            connectionMessage = route.providers.map { "\($0.name): \(connection(for: $0).rawValue)" }.joined(separator: " · ")
        } else {
            connectionState = connection(for: assistantProvider)
            connectionMessage = message(for: assistantProvider)
        }
    }

    private func refreshWorkStatus() {
        isWorking = !replyOwners.isEmpty
        if route == .compare {
            if isWorking { status = "Waiting for " + route.providers.filter { replyOwners[$0] != nil }.map(\.name).joined(separator: " and ") + "…" }
            else {
                let completed = compareResults.values.filter { $0.state == .complete }.count
                status = completed == 2 ? "Comparison ready · independent answers" : completed == 1 ? "One answer ready · other lane did not finish" : "No completed answers"
            }
        } else if let result = compareResults[assistantProvider] {
            if result.state == .complete { status = sourceName == nil ? "Reply ready" : "Reply ready · shared copy revision \(sourceRevision)" }
            else { status = result.status }
        }
    }

    func savePreferences() {
        guard rememberPreferences else { status = "Preferences apply to this visit."; return }
        guard preferences.isValid else { status = "Choose valid appearance and reply settings before saving."; return }
        var document = preferenceDocument
        document.preferences = preferences
        if commitPreferenceDocument(document) {
            status = "Preferences saved on this device."
        }
    }

    func forgetPreferences() {
        var document = preferenceDocument
        document.preferences = nil
        if commitPreferenceDocument(document) {
            rememberPreferences = false
            status = "Saved appearance and rhythm removed. Kept lessons and current visit are unchanged."
        }
    }

    func contextTicket() -> ContextTicket {
        ContextTicket(generation: workGeneration, placement: placementRevision, source: sourceRevision, selection: selectionRevision)
    }

    /// Only the native document and window adapters supply observations. A reply
    /// or generated body has no path into this local geometry contract.
    func previewPlacement() {
        invalidatePlacementPreview(reason: "Preview replaced.")
        let ticket = contextTicket()
        guard isVisible, !isWorking, let selection = textSelection,
              selection.matches(text: sharedText, sourceRevision: sourceRevision),
              let geometry = onObserveSelectedPassage?(), geometry.selection == selection,
              let environment = onObserveSpatialEnvironment?(),
              let display = environment.displays.first(where: { $0.id == geometry.screenID }),
              display.frame == geometry.screenFrame,
              let candidate = SpatialPlacementPlanner.propose(geometry: geometry,
                  companionFrame: environment.companionFrame, visibleDisplay: display.visibleFrame),
              isCurrent(ticket) else {
            spatialMessage = "Keep the whole selected passage visible and ARCHi shown, then preview again."
            return
        }
        let now = monotonicTime()
        guard now.isFinite else { return }
        let preview = SpatialPreview(id: UUID(), candidate: candidate, geometry: geometry,
                                     environment: environment, ticket: ticket, createdAt: now)
        spatialPreview = preview
        spatialRecorder.capture(preview, now: now)
        refreshSpatialRecordingState()
        spatialMessage = candidate.reason
        onPresentPlacementPreview?(preview)
        record("Placement preview created from the current shared passage")
        previewExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SpatialPreview.lifetime))
            guard !Task.isCancelled else { return }
            self?.expirePlacementPreview()
        }
    }

    func dismissPlacementPreview() {
        invalidatePlacementPreview(reason: "Preview dismissed. ARCHi stayed in place.", recordingOutcome: .dismissed)
    }

    func invalidatePlacementPreview(reason: String, recordingOutcome: SpatialRecordingOutcome = .invalidated) {
        guard let preview = spatialPreview else { return }
        // Applying consumes the on-screen preview before moving. Its recording
        // stays pending until the actual result has been observed below.
        if recordingOutcome != .pending {
            spatialRecorder.finish(previewID: preview.id, kind: recordingOutcome, now: monotonicTime())
            refreshSpatialRecordingState()
        }
        previewExpiryTask?.cancel(); previewExpiryTask = nil
        spatialPreview = nil
        onPresentPlacementPreview?(nil)
        spatialMessage = reason
    }

    func expirePlacementPreview() {
        guard let preview = spatialPreview else { return }
        if !preview.isFresh(at: monotonicTime()) {
            invalidatePlacementPreview(reason: "Preview expired. Preview again using the current passage.", recordingOutcome: .expired)
        }
    }

    func applyPlacementPreview() {
        guard let preview = spatialPreview else { return }
        guard preview.isFresh(at: monotonicTime()) else {
            invalidatePlacementPreview(reason: "Preview expired. Preview again using the current passage.", recordingOutcome: .expired)
            return
        }
        // The complete observation is reacquired immediately before mutation.
        // No await, animation, or model call can intervene in this local step.
        guard !isWorking, isCurrent(preview.ticket), preview.isFresh(at: monotonicTime()),
              textSelection == preview.geometry.selection,
              preview.geometry.selection.matches(text: sharedText, sourceRevision: sourceRevision),
              onObserveSelectedPassage?() == preview.geometry,
              onObserveSpatialEnvironment?() == preview.environment,
              isCurrent(preview.ticket), spatialPreview?.id == preview.id,
              let move = onMoveCompanion else {
            invalidatePlacementPreview(reason: "The passage, display, or ARCHi changed. Preview again.")
            return
        }
        invalidatePlacementPreview(reason: "Applying the reviewed placement…", recordingOutcome: .pending)
        if preview.candidate.staysPut {
            spatialRecorder.finish(previewID: preview.id, kind: .stayed,
                actualFrame: preview.environment.companionFrame, now: monotonicTime())
            refreshSpatialRecordingState()
            spatialMessage = "ARCHi stayed here. The selected passage remains clear."
            record("Current placement retained after a fresh layout check")
            return
        }
        move(preview.candidate.frame)
        // Inspect the frame AppKit actually accepted. A request alone is not a move receipt.
        let receipt = SpatialPlacementReceipt(requestedFrame: preview.candidate.frame,
                                              actualFrame: onObserveSpatialEnvironment?()?.companionFrame)
        lastPlacementReceipt = receipt
        spatialRecorder.finish(previewID: preview.id, kind: receipt.matched ? .moved : .unconfirmed,
            actualFrame: receipt.actualFrame, now: monotonicTime())
        refreshSpatialRecordingState()
        if receipt.matched {
            spatialMessage = "ARCHi moved beside the passage. Select again to continue from his new position."
            record("Reviewed placement applied and actual frame checked")
        } else {
            spatialMessage = "The requested placement was not confirmed. Preview again from ARCHi’s current position."
            record("Requested placement did not match the observed frame")
        }
    }

    func startSpatialRecording() {
        guard !spatialRecorder.isRecording else { return }
        spatialRecorder.clear()
        spatialRecorder.start()
        refreshSpatialRecordingState()
        spatialRecordingMessage = "Recording locally. Return to Shared context and try placement previews."
    }

    func stopSpatialRecording() {
        spatialRecorder.stop(now: monotonicTime())
        refreshSpatialRecordingState()
        spatialRecordingMessage = "Stopped · \(spatialRecordCount) placement previews retained locally."
    }

    func clearSpatialRecording() {
        guard !spatialRecorder.isRecording else { return }
        spatialRecorder.clear()
        refreshSpatialRecordingState()
        spatialRecordingMessage = "Recording cleared from this session. Exported files are unchanged."
    }

    /// Exact stopped projection used by the save action and cross-runtime tests.
    /// Its Codable contract excludes source text and identifying metadata.
    func spatialRecordingData() throws -> Data { try spatialRecorder.exportData() }

    func exportSpatialRecording() {
        do {
            let data = try spatialRecordingData()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "archi-placement-recording.json"
            panel.message = "Save geometry and timing for local Node Lab replay. No document text or filenames are included."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            spatialRecordingMessage = "Recording exported. Import this JSON in Node Lab → Native recordings."
        } catch let error as SpatialRecordingError {
            spatialRecordingMessage = error.localizedDescription
        } catch {
            spatialRecordingMessage = "Could not write the recording. Choose a writable location and try again."
        }
    }

    private func refreshSpatialRecordingState() {
        let wasRecording = isRecordingSpatial
        isRecordingSpatial = spatialRecorder.isRecording
        spatialRecordCount = spatialRecorder.records.count
        if spatialRecorder.limitReached {
            spatialRecordingMessage = "Recording stopped at 100 previews. Export or start a new recording."
        } else if wasRecording && !isRecordingSpatial {
            spatialRecordingMessage = "Recording stopped. Retained previews are available for export."
        }
    }

    /// Used by future asynchronous adapters immediately before publishing a contextual result.
    func isCurrent(_ ticket: ContextTicket, requireVisible: Bool = true) -> Bool {
        (!requireVisible || isVisible) && ticket == contextTicket()
    }

    private func record(_ message: String) {
        activity.append(message)
        if activity.count > 40 { activity.removeFirst(activity.count - 40) }
    }
}

// The existing preference owner is the only durable lesson write boundary.
// Model clients receive immutable snapshots and have no way to keep a lesson.
extension CompanionStore {
    var currentLessonSource: LessonSource? {
        guard let name = sourceName else { return nil }
        return LessonSource(name: name, digest: SHA256.hash(data: Data(sharedText.utf8))
            .map { String(format: "%02x", $0) }.joined())
    }

    var nextReplyLessons: [LessonSnapshot] {
        route == .codex ? [] : matchingLessons(question: prompt)
    }

    func matchingLessons(question: String) -> [LessonSnapshot] {
        keptLessons.filter { $0.matches(question: question, sourceName: sourceName,
            sourceText: sharedText, now: wallClock()) }.map(LessonSnapshot.init(lesson:))
    }

    func lessonAvailability(_ lesson: KeptLesson) -> String {
        if let expiry = lesson.expiresAt, expiry <= wallClock() { return "Expired · revise to use again" }
        if let source = lesson.source, source != currentLessonSource {
            return "Waiting for the same shared copy · \(source.name)"
        }
        return "Available when your question contains “\(lesson.topic)”"
    }

    func beginLessonCorrection(for provider: AssistantProvider? = nil, revisingID: String? = nil) {
        guard !isShuttingDown else { return }
        if let revisingID {
            guard let prior = keptLessons.first(where: { $0.id == revisingID }) else { return }
            lessonDraft = LessonCorrectionDraft(lessonID: prior.id, expectedRevision: lessonRevision,
                prior: prior, topic: prior.topic, text: prior.text, reason: prior.reason,
                source: prior.source, origin: prior.origin, expiresAt: prior.expiresAt)
        } else {
            var origin: LessonOrigin?
            if let provider, let result = compareResults[provider], result.state == .complete,
               !result.text.isEmpty, let receipt = result.receipt {
                origin = LessonOrigin(requestID: receipt.requestID, inputDigest: receipt.inputDigest)
            }
            lessonDraft = LessonCorrectionDraft(expectedRevision: lessonRevision, prior: nil, origin: origin)
        }
        lessonMessage = "Review the lesson and when to use it. Nothing is saved until you press Keep."
        open(.memory)
    }

    func discardLessonDraft() {
        lessonDraft = nil
        lessonMessage = "Draft discarded. Nothing was saved."
    }

    @discardableResult
    func keepLesson(_ draft: LessonCorrectionDraft) -> Bool {
        guard !isShuttingDown, draft.expectedRevision == lessonRevision,
              draft.prior == keptLessons.first(where: { $0.id == draft.lessonID }),
              (draft.lessonID == nil) == (draft.prior == nil) else {
            lessonMessage = "Saved choices changed while this draft was open. Close it and review a fresh draft."
            return false
        }
        if let source = draft.source, source != currentLessonSource {
            lessonMessage = "The shared copy changed. Share the original copy again, or remove its scope before keeping."
            return false
        }
        let now = wallClock()
        guard draft.prior?.revision != UInt64.max else { return false }
        let lesson = KeptLesson(id: draft.lessonID ?? UUID().uuidString,
            revision: (draft.prior?.revision ?? 0) + 1,
            topic: draft.topic.trimmingCharacters(in: .whitespacesAndNewlines),
            text: draft.text.trimmingCharacters(in: .whitespacesAndNewlines),
            reason: draft.reason.trimmingCharacters(in: .whitespacesAndNewlines),
            source: draft.source, origin: draft.origin,
            createdAt: draft.prior?.createdAt ?? now, updatedAt: now, expiresAt: draft.expiresAt)
        guard lesson.isValid, lesson.expiresAt == nil || lesson.expiresAt! > now else {
            lessonMessage = "Use a topic phrase of 2–80 characters, a lesson of 1–600 characters, an optional reason up to 300 characters, and a future expiry if set."
            return false
        }
        var document = preferenceDocument
        if let index = document.lessons.firstIndex(where: { $0.id == lesson.id }) {
            document.lessons[index] = lesson
        } else {
            guard document.lessons.count < NativePreferenceDocument.maximumLessons else {
                lessonMessage = "You can keep up to 16 lessons. Withdraw an unused lesson before adding another."
                return false
            }
            document.lessons.append(lesson)
        }
        guard commitPreferenceDocument(document) else { return false }
        if draft.prior != nil { revokeLocalLessonSnapshot(lesson.id) }
        lessonDraft = nil
        lessonMessage = "Lesson kept on this Mac. It will be considered for the next matching local question."
        status = lessonMessage
        return true
    }

    @discardableResult
    func withdrawLesson(id: String, expectedRevision: UInt64) -> Bool {
        guard !isShuttingDown, expectedRevision == lessonRevision,
              keptLessons.contains(where: { $0.id == id }) else {
            lessonMessage = "Saved lessons changed. Review the current list before withdrawing."
            return false
        }
        var document = preferenceDocument
        document.lessons.removeAll { $0.id == id }
        guard commitPreferenceDocument(document) else { return false }
        revokeLocalLessonSnapshot(id)
        if lessonDraft?.lessonID == id { lessonDraft = nil }
        lessonMessage = "Lesson withdrawn from this Mac. It will not be included in future replies."
        status = lessonMessage
        return true
    }

    func lessonExportData() throws -> Data {
        var export = preferenceDocument
        export.preferences = nil
        return try export.encoded()
    }

    func exportLessons() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ARCHi-kept-lessons.json"
        panel.message = "Exports all kept lessons, including expired ones, their text and source references. Appearance, conversations and Journey are excluded."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try lessonExportData().write(to: url, options: .atomic)
            lessonMessage = "Exported \(keptLessons.count) kept lessons, including expired or unavailable ones."
        } catch { lessonMessage = "Could not export lessons. The saved originals are unchanged." }
    }

    private func commitPreferenceDocument(_ proposed: NativePreferenceDocument) -> Bool {
        guard preferenceFileReadable, preferenceDocument.revision < UInt64.max else {
            lessonMessage = "The saved settings file is unavailable. It has been preserved; reopen after restoring a valid file."
            status = lessonMessage
            return false
        }
        var next = proposed
        next.revision = preferenceDocument.revision + 1
        do {
            let baseline = try NativePreferencePersistence.write(document: next, to: preferenceURL, expected: preferenceBaseline)
            // Atomic write completes before any admitted state or request changes.
            preferenceBaseline = baseline
            preferenceDocument = next
            keptLessons = next.lessons
            lessonRevision = next.revision
            return true
        } catch {
            lessonMessage = "Could not save: \(error.localizedDescription) Previous saved choices are unchanged."
            status = lessonMessage
            return false
        }
    }

    private func revokeLocalLessonSnapshot(_ id: String) {
        let heldLesson = compareResults[.qwen]?.receipt?.localLessons.contains(where: { $0.id == id }) == true
        // Removing or changing a lesson also clears possible earlier excerpts.
        // The existing lane owner fences late events; Codex keeps its own work.
        clearSessionContext()
        if heldLesson { compareResults[.qwen] = nil }
        if assistantProvider == .qwen { reply = "Local lesson changed. Send a new question when you are ready." }
    }
}
