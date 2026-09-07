import Foundation
import Combine

enum EvolutionFamily: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case lumen, fen, frame, pop, relic, veil
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var summary: String {
        switch self {
        case .lumen: "A luminous presence with a soft, guiding glow."
        case .fen: "An organic companion with a curious, woodland character."
        case .frame: "A geometric presence that gives ideas a clear outline."
        case .pop: "A playful, graphic companion with bright expression."
        case .relic: "A sculptural companion with a quiet, timeworn character."
        case .veil: "A flowing, translucent presence with gentle movement."
        }
    }
}

enum EvolutionRole: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case hearth, muse, scout, beacon, keeper, guardian
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var summary: String {
        switch self {
        case .hearth: "Help me settle into my work."
        case .muse: "Help me explore creative possibilities."
        case .scout: "Help me find what deserves a closer look."
        case .beacon: "Help me find a clear next step."
        case .keeper: "Help me organize what I choose to keep."
        case .guardian: "Help me review decisions and boundaries."
        }
    }
}

enum EvolutionHelpStyle: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case concise, exploratory, stepByStep, reflective
    var id: String { rawValue }
    var title: String {
        switch self {
        case .concise: "Concise"
        case .exploratory: "Exploratory"
        case .stepByStep: "Step by step"
        case .reflective: "Reflective"
        }
    }
}

enum EvolutionPreferenceCategory: String, CaseIterable, Identifiable, Sendable {
    case role, helpStyle, family
    var id: String { rawValue }
}

struct EvolutionPreferences: Equatable, Sendable {
    var role: EvolutionRole?
    var helpStyle: EvolutionHelpStyle?
    var family: EvolutionFamily?
    var confirmedCount: Int { [role != nil, helpStyle != nil, family != nil].filter { $0 }.count }
}

/// These identifiers refer to user-marked, completed requests. They contain no
/// document, question, answer, account, or model training data.
struct EvolutionUsefulReceipt: Codable, Equatable, Identifiable, Sendable {
    let requestID: UUID
    let sourceDigest: String
    var id: UUID { requestID }
}

struct EvolutionProposal: Equatable, Identifiable, Sendable {
    let id: UUID
    let revision: UInt64
    let family: EvolutionFamily
    let preferences: EvolutionPreferences
    let evidence: [EvolutionUsefulReceipt]
    let basis: EvolutionProposalBasis
    let appearanceRecipe: CompanionAppearanceRecipe?

    init(id: UUID, revision: UInt64, family: EvolutionFamily, preferences: EvolutionPreferences,
         evidence: [EvolutionUsefulReceipt], basis: EvolutionProposalBasis,
         appearanceRecipe: CompanionAppearanceRecipe? = nil) {
        self.id = id; self.revision = revision; self.family = family; self.preferences = preferences
        self.evidence = evidence; self.basis = basis; self.appearanceRecipe = appearanceRecipe
    }
}

struct EvolutionHistoryEntry: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable { case kept, returned }
    let kind: Kind
    let family: EvolutionFamily?
    // History is a bounded cosmetic sequence, not a character identity ledger.
    let id: UUID
    let appearanceRecipe: CompanionAppearanceRecipe?

    init(kind: Kind, family: EvolutionFamily?, id: UUID, appearanceRecipe: CompanionAppearanceRecipe? = nil) {
        self.kind = kind; self.family = family; self.id = id; self.appearanceRecipe = appearanceRecipe
    }
}

@MainActor
final class EvolutionStore: ObservableObject {
    static let maximumUsefulReceipts = 32
    static let maximumHistoryEntries = 32
    static let maximumSaveBytes = 32 * 1024
    static let schema = "archi-companion-evolution/v4"
    static let maximumReviewedPractices = 8
    static let retentionExplanation = "Evolution stays in this session until you choose Save. A save contains confirmed choices, up to 32 useful-request references, up to 8 reviewed practice references, a Journey binding, and up to 32 kept/returned appearances with their individual recipes and reasons. It contains no source text or assistant conversation. Journey owns the identity and battle history. Load is explicit; Forget clears this session and attempts to delete this save."

    // A cosmetic starting form, not a character/passport identity. Only an
    // explicit validated Load may restore a different saved starting form.
    @Published private(set) var origin: CompanionForm
    let saveURL: URL?
    @Published private(set) var preferences = EvolutionPreferences()
    @Published private(set) var usefulReceipts: [EvolutionUsefulReceipt] = []
    @Published private(set) var practiceJourneyOriginDigest: String?
    @Published private(set) var reviewedPractices: [PracticeEvolutionReference] = []
    @Published private(set) var keptBasis: EvolutionProposalBasis?
    @Published private(set) var keptAppearanceRecipe: CompanionAppearanceRecipe?
    // An ephemeral observation from the existing host, never another identity writer.
    @Published private(set) var observedJourneyOriginDigest: String?
    @Published private(set) var proposal: EvolutionProposal?
    @Published private(set) var previewFamily: EvolutionFamily?
    @Published private(set) var activeFamily: EvolutionFamily?
    @Published private(set) var history: [EvolutionHistoryEntry] = []
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var requiresReplacement = false
    @Published private(set) var status = "Your individual is already distinct. Appearance choices and shared history stay in this session until saved."
    private let deleteFile: (URL) throws -> Void

    var confirmedRole: EvolutionRole? { preferences.role }
    var confirmedHelpStyle: EvolutionHelpStyle? { preferences.helpStyle }
    var confirmedFamily: EvolutionFamily? { preferences.family }
    var activeAppearanceRecipe: CompanionAppearanceRecipe? {
        guard let recipe = keptAppearanceRecipe, recipe.family == activeFamily,
              recipe.originDigest == practiceJourneyOriginDigest,
              observedJourneyOriginDigest == nil || observedJourneyOriginDigest == recipe.originDigest else { return nil }
        return recipe
    }
    /// Natural variation belongs to the current Journey, independent of help
    /// preferences or activity counts. A validated saved binding is a fallback
    /// until the existing native host supplies the current Journey at launch.
    var naturalVariation: CompanionNaturalVariation? {
        (observedJourneyOriginDigest ?? practiceJourneyOriginDigest).flatMap {
            CompanionNaturalVariation.make(originDigest: $0)
        }
    }

    /// Called only with a validated projection from the existing native play host.
    /// A different observed Journey retires previews and hides another origin's
    /// individual details without rewriting the saved binding or kept history.
    func observeJourneyOrigin(_ originDigest: String) {
        guard PracticeEvolutionReference.isDigest(originDigest), observedJourneyOriginDigest != originDigest else { return }
        observedJourneyOriginDigest = originDigest
        proposal = nil; previewFamily = nil
        if let bound = practiceJourneyOriginDigest, bound != originDigest {
            status = "A different individual is open. Its natural details follow this Journey; earlier personal history remains linked to its original Journey."
        }
        revision &+= 1
    }
    var canProposeForm: Bool { confirmedFamily != nil }

    @discardableResult
    func bindPracticeJourney(_ originDigest: String) -> Bool {
        guard PracticeEvolutionReference.isDigest(originDigest) else { status = "That Journey origin reference is invalid."; return false }
        guard practiceJourneyOriginDigest != originDigest else { return true }
        let rebinding = practiceJourneyOriginDigest != nil
        practiceJourneyOriginDigest = originDigest
        reviewedPractices = []
        changed(rebinding
            ? "Journey history reconnected. Earlier practice references stay with their original Journey; your kept appearance remains."
            : "Journey connected for personal history. Its natural details are already present.", preservingKeptAppearance: true)
        return true
    }

    /// The host integration supplies an exact reference from its current validated
    /// projection only after the user presses Review. This store cannot replay TS battles.
    @discardableResult
    func reviewPractice(_ reference: PracticeEvolutionReference, currentOriginDigest: String) -> Bool {
        guard reference.isValid, reference.originDigest == currentOriginDigest,
              practiceJourneyOriginDigest == currentOriginDigest else {
            status = "Review a valid outcome from the bound Journey. Bind a different Journey explicitly first."; return false
        }
        guard !reviewedPractices.contains(where: { $0.id == reference.id }) else {
            status = "This Journey outcome has already been reviewed."; return false
        }
        guard reviewedPractices.count < Self.maximumReviewedPractices else {
            status = "Eight practice references are retained. Withdraw an older reference before reviewing another."; return false
        }
        reviewedPractices.append(reference)
        changed("Practice added to your shared history. It does not unlock a body or measure personal growth.", preservingKeptAppearance: true)
        return true
    }

    func withdrawPractice(id: String) {
        guard reviewedPractices.contains(where: { $0.id == id }) else { return }
        reviewedPractices.removeAll { $0.id == id }
        changed("Practice reference removed from shared history. Your appearance stays the same.", preservingKeptAppearance: true)
    }

    init(origin: CompanionForm = .companion, saveURL: URL? = nil,
         deleteFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.origin = origin
        self.saveURL = saveURL
        self.deleteFile = deleteFile
        // No implicit disk read or write; the existing appearance preference file
        // and all provider, identity, battle, and source state stay outside this store.
    }

    func confirmRole(_ role: EvolutionRole) {
        preferences.role = role; changed("Work role confirmed.")
    }
    func confirmHelpStyle(_ style: EvolutionHelpStyle) {
        preferences.helpStyle = style; changed("Help style confirmed.")
    }
    func confirmFamily(_ family: EvolutionFamily) {
        preferences.family = family; changed("Visual family confirmed.")
    }
    func revoke(_ category: EvolutionPreferenceCategory) {
        switch category {
        case .role: preferences.role = nil
        case .helpStyle: preferences.helpStyle = nil
        case .family: preferences.family = nil
        }
        changed("Preference withdrawn.")
    }

    /// The integration must supply a current completed lane and the digest of
    /// its nonempty shared source. This boundary also rejects unfinished lanes.
    /// Both Compare lanes have one request ID and therefore count only once.
    @discardableResult
    func markUseful(receipt: AssistantLaneReceipt, sourceDigest: String) -> Bool {
        guard receipt.state == .complete, let requestID = UUID(uuidString: receipt.requestID),
              Self.validDigest(sourceDigest), Self.validDigest(receipt.inputDigest),
              receipt.sourceDigest?.lowercased() == sourceDigest.lowercased() else {
            status = "Only a completed request with valid source evidence can count."; return false
        }
        guard !usefulReceipts.contains(where: { $0.requestID == requestID }) else {
            status = "This request is already counted, including its other comparison answer."; return false
        }
        guard usefulReceipts.count < Self.maximumUsefulReceipts else {
            status = "The 32-request limit is reached. Withdraw an older receipt before adding another."; return false
        }
        usefulReceipts.append(EvolutionUsefulReceipt(requestID: requestID, sourceDigest: sourceDigest.lowercased()))
        changed("Completed request marked useful.")
        return true
    }

    func withdrawUseful(requestID: UUID) {
        guard usefulReceipts.contains(where: { $0.requestID == requestID }) else { return }
        usefulReceipts.removeAll { $0.requestID == requestID }
        changed("Useful-request evidence withdrawn.")
    }

    func preview(_ family: EvolutionFamily) {
        if proposal?.family != family { proposal = nil }
        previewFamily = family
        status = "Exploring \(family.title) in this workspace. Your desktop appearance has not changed."
    }
    func dismissPreview() { previewFamily = nil; proposal = nil }

    @discardableResult
    func proposeEvolution() -> EvolutionProposal? {
        guard let family = confirmedFamily else {
            proposal = nil; status = "Choose a form to preview. No tasks or battles are required."; return nil
        }
        let candidate = EvolutionProposal(id: UUID(), revision: revision, family: family,
            preferences: preferences, evidence: usefulReceipts,
            basis: EvolutionProposalBasis(kind: .appearanceChoice, practice: nil))
        proposal = candidate
        previewFamily = family
        status = "Previewing \(family.title). This is an appearance choice; your individual and experiences continue."
        return candidate
    }

    @discardableResult
    func keepEvolution() -> Bool {
        guard let candidate = proposal else { status = "Create a fresh evolution proposal first."; return false }
        return keepEvolution(candidate)
    }

    @discardableResult
    func keepEvolution(_ candidate: EvolutionProposal) -> Bool {
        guard proposal == candidate, candidate.revision == revision,
              candidate.family == confirmedFamily, candidate.family == previewFamily, candidate.preferences == preferences,
              candidate.evidence == usefulReceipts, candidate.basis == EvolutionProposalBasis(kind: .appearanceChoice, practice: nil),
              candidate.appearanceRecipe == nil else {
            status = "That proposal is no longer current. Review your choices and propose again."; return false
        }
        activeFamily = candidate.family
        keptBasis = candidate.basis
        keptAppearanceRecipe = candidate.appearanceRecipe
        appendHistory(.kept, family: candidate.family, recipe: candidate.appearanceRecipe)
        changed("\(candidate.family.title) kept for this session. Save explicitly to reopen it later.")
        previewFamily = nil
        return true
    }

    func returnToStarter() {
        if activeFamily != nil { appendHistory(.returned, family: nil) }
        activeFamily = nil
        keptBasis = nil
        keptAppearanceRecipe = nil
        previewFamily = nil
        changed("Returned to your \(origin.rawValue) starter. Your confirmed choices remain.")
    }

    /// All file operations are synchronous and bounded on the store actor. An
    /// older pending Save or Load cannot finish after Forget and restore state.
    @discardableResult
    func forget() -> Bool {
        preferences = EvolutionPreferences(); usefulReceipts = []; proposal = nil
        previewFamily = nil; activeFamily = nil; history = []
        practiceJourneyOriginDigest = nil; reviewedPractices = []; keptBasis = nil; keptAppearanceRecipe = nil
        revision &+= 1; hasUnsavedChanges = true
        guard let url = saveURL else {
            hasUnsavedChanges = false; requiresReplacement = false
            status = "Evolution choices and evidence cleared from this session. No save location is configured."
            return true
        }
        do {
            if let type = try entryType(url) {
                guard type == .typeRegular || type == .typeSymbolicLink else { throw EvolutionFileError.unsupportedItem }
                try deleteFile(url)
            }
            hasUnsavedChanges = false; requiresReplacement = false
            status = "Evolution choices and evidence cleared; no saved evolution remains at this location."
            return true
        } catch {
            requiresReplacement = true
            status = "This session is cleared, but the saved evolution could not be deleted. It may still be loaded. \(boundedError(error))"
            return false
        }
    }

    @discardableResult
    func save(replacingInvalidFile: Bool = false) -> Bool {
        guard let url = saveURL else { status = "No evolution save location is configured."; return false }
        do {
            let existingType = try entryType(url)
            if existingType != nil, !replacingInvalidFile {
                do { _ = try decode(readBounded(url)) }
                catch {
                    requiresReplacement = true
                    status = "The existing save could not be validated and was preserved. Choose Replace saved evolution explicitly to replace it. \(boundedError(error))"
                    return false
                }
            }
            guard existingType == nil || existingType == .typeRegular || existingType == .typeSymbolicLink else {
                throw EvolutionFileError.unsupportedItem
            }
            let bytes = try encodeCurrentState()
            guard bytes.count <= Self.maximumSaveBytes else { throw EvolutionFileError.invalid }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url, options: .atomic)
            hasUnsavedChanges = false; requiresReplacement = false
            status = "Evolution choices, evidence identifiers, and kept appearance saved on this Mac."
            return true
        } catch {
            status = "Evolution was not saved. \(boundedError(error))"
            return false
        }
    }

    @discardableResult
    func load() -> Bool {
        guard let url = saveURL else { status = "No evolution save location is configured."; return false }
        do {
            guard try entryType(url) != nil else {
                status = "No saved evolution was found. This session is unchanged."; return false
            }
            let loaded = try decode(readBounded(url))
            origin = loaded.origin
            preferences = loaded.preferences; usefulReceipts = loaded.receipts
            activeFamily = loaded.active; history = loaded.history
            practiceJourneyOriginDigest = loaded.practiceOrigin
            reviewedPractices = loaded.practices; keptBasis = loaded.basis
            keptAppearanceRecipe = loaded.recipe
            proposal = nil; previewFamily = nil; revision &+= 1
            hasUnsavedChanges = false; requiresReplacement = false
            status = "Saved cosmetic evolution loaded. Its receipt identifiers are retained records, not fresh assistant observations."
            return true
        } catch {
            requiresReplacement = true
            status = "The saved evolution could not be loaded. This session and the file are unchanged. \(boundedError(error))"
            return false
        }
    }

    private func changed(_ message: String, preservingKeptAppearance: Bool = false) {
        proposal = nil; hasUnsavedChanges = true
        // Appearance is a user choice. Editing help preferences or withdrawing
        // activity feedback must never demote or redraw the kept individual.
        status = message
        // Publish the revision after the complete transition so native snapshots,
        // placement and Reactor references see one consistent chosen appearance.
        revision &+= 1
    }

    private func appendHistory(_ kind: EvolutionHistoryEntry.Kind, family: EvolutionFamily?, recipe: CompanionAppearanceRecipe? = nil) {
        history.append(EvolutionHistoryEntry(kind: kind, family: family, id: UUID(), appearanceRecipe: recipe))
        if history.count > Self.maximumHistoryEntries { history.removeFirst(history.count - Self.maximumHistoryEntries) }
    }

    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }
    private func boundedError(_ error: Error) -> String { String(error.localizedDescription.prefix(220)) }
    private func entryType(_ url: URL) throws -> FileAttributeType? {
        // attributesOfItem examines the last path entry, including a dangling
        // symbolic link. fileExists follows it and can incorrectly report absence.
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let type = attributes[.type] as? FileAttributeType else { throw EvolutionFileError.unsupportedItem }
            return type
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }
    private func readBounded(_ url: URL) throws -> Data {
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw EvolutionFileError.invalid }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: Self.maximumSaveBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= Self.maximumSaveBytes else { throw EvolutionFileError.oversized }
        return data
    }

    private struct SavedState {
        let origin: CompanionForm
        let preferences: EvolutionPreferences
        let receipts: [EvolutionUsefulReceipt]
        let active: EvolutionFamily?
        let history: [EvolutionHistoryEntry]
        let practiceOrigin: String?
        let practices: [PracticeEvolutionReference]
        let basis: EvolutionProposalBasis?
        let recipe: CompanionAppearanceRecipe?
    }

    private func encodeCurrentState() throws -> Data {
        let object: [String: Any] = [
            "schema": Self.schema, "origin": origin.rawValue,
            "role": preferences.role?.rawValue as Any? ?? NSNull(),
            "helpStyle": preferences.helpStyle?.rawValue as Any? ?? NSNull(),
            "family": preferences.family?.rawValue as Any? ?? NSNull(),
            "activeFamily": activeFamily?.rawValue as Any? ?? NSNull(),
            "usefulReceipts": usefulReceipts.map { ["requestID": $0.requestID.uuidString, "sourceDigest": $0.sourceDigest] },
            "history": try history.map { ["kind": $0.kind.rawValue, "family": $0.family?.rawValue as Any? ?? NSNull(), "id": $0.id.uuidString,
                "appearanceRecipe": try encodedRecipe($0.appearanceRecipe)] as [String: Any] },
            "practiceJourneyOriginDigest": practiceJourneyOriginDigest as Any? ?? NSNull(),
            "reviewedPractices": try JSONSerialization.jsonObject(with: JSONEncoder().encode(reviewedPractices)),
            "keptBasis": try keptBasis.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull(),
            "keptAppearanceRecipe": try encodedRecipe(keptAppearanceRecipe)
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    }

    private func decode(_ data: Data) throws -> SavedState {
        guard data.count <= Self.maximumSaveBytes else { throw EvolutionFileError.oversized }
        var scanner = EvolutionJSONKeyScanner(bytes: Array(data)); try scanner.validate()
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw EvolutionFileError.invalid }
        let legacy = object["schema"] as? String == "archi-companion-evolution/v1"
        let prior = object["schema"] as? String == "archi-companion-evolution/v2"
        let current = object["schema"] as? String == Self.schema
        let hasRecipes = current || object["schema"] as? String == "archi-companion-evolution/v3"
        let baseKeys: Set<String> = ["schema", "origin", "role", "helpStyle", "family", "activeFamily", "usefulReceipts", "history"]
        let v2Keys = baseKeys.union(["practiceJourneyOriginDigest", "reviewedPractices", "keptBasis"])
        guard Set(object.keys) == (legacy ? baseKeys : hasRecipes ? v2Keys.union(["keptAppearanceRecipe"]) : v2Keys),
              legacy || prior || hasRecipes,
              let rawOrigin = object["origin"] as? String, let savedOrigin = CompanionForm(rawValue: rawOrigin),
              let rawReceipts = object["usefulReceipts"] as? [[String: Any]], rawReceipts.count <= Self.maximumUsefulReceipts,
              let rawHistory = object["history"] as? [[String: Any]], rawHistory.count <= Self.maximumHistoryEntries else { throw EvolutionFileError.invalid }
        let preferences = EvolutionPreferences(role: try optionalEnum(object["role"], EvolutionRole.self),
            helpStyle: try optionalEnum(object["helpStyle"], EvolutionHelpStyle.self),
            family: try optionalEnum(object["family"], EvolutionFamily.self))
        let active = try optionalEnum(object["activeFamily"], EvolutionFamily.self)
        var ids = Set<UUID>()
        let receipts = try rawReceipts.map { item -> EvolutionUsefulReceipt in
            guard Set(item.keys) == ["requestID", "sourceDigest"],
                  let rawID = item["requestID"] as? String, let id = UUID(uuidString: rawID), ids.insert(id).inserted,
                  let digest = item["sourceDigest"] as? String, Self.validDigest(digest) else { throw EvolutionFileError.invalid }
            return EvolutionUsefulReceipt(requestID: id, sourceDigest: digest.lowercased())
        }
        var historyIDs = Set<UUID>()
        let history = try rawHistory.map { item -> EvolutionHistoryEntry in
            guard Set(item.keys) == (hasRecipes ? ["kind", "family", "id", "appearanceRecipe"] : ["kind", "family", "id"]), let rawKind = item["kind"] as? String,
                  let kind = EvolutionHistoryEntry.Kind(rawValue: rawKind),
                  let rawID = item["id"] as? String, let id = UUID(uuidString: rawID), historyIDs.insert(id).inserted else { throw EvolutionFileError.invalid }
            let family = try optionalEnum(item["family"], EvolutionFamily.self)
            let recipe = hasRecipes ? try decodedRecipe(item["appearanceRecipe"]) : nil
            guard (kind == .kept && family != nil) || (kind == .returned && family == nil) else { throw EvolutionFileError.invalid }
            guard recipe == nil || (kind == .kept && recipe?.family == family) else { throw EvolutionFileError.invalid }
            return EvolutionHistoryEntry(kind: kind, family: family, id: id, appearanceRecipe: recipe)
        }
        let practiceOrigin: String?
        let practices: [PracticeEvolutionReference]
        let basis: EvolutionProposalBasis?
        if legacy {
            practiceOrigin = nil; practices = []
            basis = active == nil ? nil : EvolutionProposalBasis(kind: .usefulWork, practice: nil)
        } else {
            if object["practiceJourneyOriginDigest"] is NSNull { practiceOrigin = nil }
            else if let raw = object["practiceJourneyOriginDigest"] as? String, PracticeEvolutionReference.isDigest(raw) { practiceOrigin = raw }
            else { throw EvolutionFileError.invalid }
            guard let rows = object["reviewedPractices"] as? [[String: Any]], rows.count <= Self.maximumReviewedPractices,
                  rows.allSatisfy({ Set($0.keys) == PracticeEvolutionReference.keys }) else { throw EvolutionFileError.invalid }
            practices = try JSONDecoder().decode([PracticeEvolutionReference].self, from: JSONSerialization.data(withJSONObject: rows))
            guard practices.allSatisfy({ $0.isValid && $0.originDigest == practiceOrigin }),
                  Set(practices.map(\.id)).count == practices.count else { throw EvolutionFileError.invalid }
            if object["keptBasis"] is NSNull { basis = nil }
            else {
                guard let raw = object["keptBasis"] as? [String: Any],
                      Set(raw.keys) == ["kind", "practice"] || Set(raw.keys) == ["kind"] else { throw EvolutionFileError.invalid }
                if let practice = raw["practice"], !(practice is NSNull) {
                    guard let value = practice as? [String: Any], Set(value.keys) == PracticeEvolutionReference.keys else { throw EvolutionFileError.invalid }
                }
                basis = try JSONDecoder().decode(EvolutionProposalBasis.self, from: JSONSerialization.data(withJSONObject: raw))
                guard basis?.isValid == true, current || basis?.kind != .appearanceChoice else { throw EvolutionFileError.invalid }
            }
        }
        let recipe = hasRecipes ? try decodedRecipe(object["keptAppearanceRecipe"]) : nil
        if let active {
            guard (current || (preferences.confirmedCount == 3 && active == preferences.family)),
                  history.last?.kind == .kept, history.last?.family == active, basis?.isValid == true else { throw EvolutionFileError.invalid }
            guard history.last?.appearanceRecipe == recipe else { throw EvolutionFileError.invalid }
            if let recipe {
                guard basis?.kind != .appearanceChoice, recipe.family == active, recipe.basisKind == basis?.kind,
                      basis?.practice == nil || basis?.practice?.originDigest == recipe.originDigest else { throw EvolutionFileError.invalid }
            }
            // A v2 kept basis records the reviewed choice at Keep time. Later
            // evidence withdrawal can retire new-proposal eligibility without
            // invalidating that historical choice or making its save unreadable.
            if legacy {
                guard preferences.confirmedCount == 3, receipts.count >= 2, active == preferences.family else { throw EvolutionFileError.invalid }
            }
        } else if history.last?.kind == .kept { throw EvolutionFileError.invalid }
        else if basis != nil || recipe != nil { throw EvolutionFileError.invalid }
        return SavedState(origin: savedOrigin, preferences: preferences, receipts: receipts, active: active, history: history,
            practiceOrigin: practiceOrigin, practices: practices, basis: basis, recipe: recipe)
    }

    private func encodedRecipe(_ recipe: CompanionAppearanceRecipe?) throws -> Any {
        try recipe.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
    }

    private func decodedRecipe(_ value: Any?) throws -> CompanionAppearanceRecipe? {
        if value is NSNull { return nil }
        guard let object = value as? [String: Any] else { throw EvolutionFileError.invalid }
        return try JSONDecoder().decode(CompanionAppearanceRecipe.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func optionalEnum<T: RawRepresentable>(_ value: Any?, _ type: T.Type) throws -> T? where T.RawValue == String {
        if value is NSNull { return nil }
        guard let raw = value as? String, let result = T(rawValue: raw) else { throw EvolutionFileError.invalid }
        return result
    }
}

private enum EvolutionFileError: LocalizedError {
    case invalid, oversized, unsupportedItem
    var errorDescription: String? {
        switch self {
        case .invalid: "The save has an unsupported version, invalid fields, or an unknown starter form."
        case .oversized: "The save is empty or exceeds the 32 KB limit."
        case .unsupportedItem: "The save location is a directory or special file and was preserved."
        }
    }
}

/// Foundation's object decoder collapses duplicate keys. Reject them, including
/// escaped equivalents, before validating the closed saved-state contract.
private struct EvolutionJSONKeyScanner {
    let bytes: [UInt8]
    private var index = 0
    init(bytes: [UInt8]) { self.bytes = bytes }
    mutating func validate() throws {
        try value(depth: 0); whitespace()
        guard index == bytes.count else { throw EvolutionFileError.invalid }
    }
    private mutating func value(depth: Int) throws {
        whitespace()
        guard depth <= 16, index < bytes.count else { throw EvolutionFileError.invalid }
        switch bytes[index] {
        case 123:
            index += 1; whitespace()
            if take(125) { return }
            var keys = Set<String>()
            while true {
                whitespace(); let key = try string()
                guard keys.insert(key).inserted else { throw EvolutionFileError.invalid }
                whitespace(); guard take(58) else { throw EvolutionFileError.invalid }
                try value(depth: depth + 1); whitespace()
                if take(125) { return }
                guard take(44) else { throw EvolutionFileError.invalid }
            }
        case 91:
            index += 1; whitespace()
            if take(93) { return }
            while true {
                try value(depth: depth + 1); whitespace()
                if take(93) { return }
                guard take(44) else { throw EvolutionFileError.invalid }
            }
        case 34: _ = try string()
        default:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            guard index > start else { throw EvolutionFileError.invalid }
        }
    }
    private mutating func string() throws -> String {
        let start = index
        guard take(34) else { throw EvolutionFileError.invalid }
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
            if byte == 92 {
                guard index < bytes.count else { throw EvolutionFileError.invalid }; index += 1
            } else if byte < 32 { throw EvolutionFileError.invalid }
        }
        throw EvolutionFileError.invalid
    }
    private mutating func whitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    private mutating func take(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1; return true
    }
}
