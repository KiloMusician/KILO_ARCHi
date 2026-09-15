import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// A disposable native window and profile exercise the actual SwiftUI controls.
/// Import uses decoded fixture bytes; this is not NSOpenPanel or VoiceOver proof.
final class MarketplaceInteractionTests: XCTestCase {
    @MainActor
    func testNativeFullCollectionReviewExplainsLimitAndStillOpensCreate() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_NATIVE"] == "1" else {
            throw XCTSkip("Set ARCHI_MARKETPLACE_NATIVE=1 for disposable native marketplace interaction evidence.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-marketplace-capacity-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifacts = ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_RENDER_DIR"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("capacity-\(UUID())") }
        if let artifacts { try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true) }
        let app = NSApplication.shared, policy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer { _ = app.setActivationPolicy(policy) }
        let assistant = MarketplaceInteractionNoCalls()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
            assistant: assistant, assistantFactory: { _, _ in assistant }, allowsPlay: false)
        for index in 1...CompanionItemPackage.maximumLibraryCount {
            var item = CompanionItemPackage.creatorDefault; item.title = "Capacity \(index)"
            XCTAssertTrue(store.collectMarketItem(item))
        }
        let before = store.itemLibrary
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 630, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "ARCHi · synthetic collection limit"
        panel.contentView = NSHostingView(rootView: MarketplaceWorkspace(store: store)
            .frame(width: 630, height: 500).background(Color(nsColor: .windowBackgroundColor)))
        panel.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer { panel.contentView = nil; panel.close() }
        try await settle()
        try capture("01-full-discover", panel: panel, directory: artifacts)
        guard node("marketplace.import", in: panel) != nil else {
            throw XCTSkip("The visible panel did not expose SwiftUI accessibility proxies; collection-limit native acceptance remains unverified.")
        }
        store.importedMarketItem = try CompanionItemPackage.decode(CompanionItemCatalog.designs[0].encoded())
        try await waitUntil { panel.attachedSheet != nil }
        let review = try XCTUnwrap(panel.attachedSheet)
        try await settle()
        XCTAssertTrue(try text("marketplace.collection-full", in: review).contains("collection is full"))
        let collect = try XCTUnwrap(node("marketplace.collect", in: review))
        XCTAssertFalse(try isEnabled(collect))
        XCTAssertNotNil(node("marketplace.import.status", in: review))
        try capture("02-full-import-review", panel: review, directory: artifacts)
        try press("marketplace.variation", in: review)
        try await waitUntil { panel.attachedSheet == nil && self.node("marketplace.create.title", in: panel) != nil }
        XCTAssertEqual(store.itemLibrary, before)
        XCTAssertTrue(store.preferences.equipment.isEmpty)
        XCTAssertEqual(assistant.calls, 0)
        await store.shutdownAssistant()
    }

    @MainActor
    func testNativeImportVariationOutfitAndWorkTogetherHandoff() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_NATIVE"] == "1" else {
            throw XCTSkip("Set ARCHI_MARKETPLACE_NATIVE=1 for disposable native marketplace interaction evidence.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-marketplace-native-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifactDirectory = ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_RENDER_DIR"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("native-\(UUID())") }
        if let artifactDirectory { try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true) }

        let app = NSApplication.shared, policy = app.activationPolicy()
        let previousApp = NSWorkspace.shared.frontmostApplication
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer {
            _ = app.setActivationPolicy(policy)
            if previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApp?.activate(options: [])
            }
        }
        let assistant = MarketplaceInteractionNoCalls()
        let profile = directory.appendingPathComponent("preferences.json")
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64),
                             welcomedAt: Date(timeIntervalSince1970: 1_800_000_000))
        _ = try NativePreferencePersistence.write(document: NativePreferenceDocument(qiMon: kin), to: profile, expected: nil)
        let store = CompanionStore(preferenceURL: profile, assistant: assistant,
            assistantFactory: { _, _ in assistant }, allowsPlay: false)
        let play = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let identity = try XCTUnwrap(store.activeQiMon)
        let source = "A useful passage. Another sentence."
        store.share(text: source, name: "synthetic-workshop.txt")
        store.open(.marketplace)
        let host = WorkspaceView.makeHostingView(store: store, playHost: play)
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 880, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "ARCHi · synthetic marketplace acceptance"
        panel.contentView = host
        WorkspaceView.applyWindowMinimum(to: panel)
        panel.setContentSize(CGSize(width: 880, height: 640))
        panel.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer { store.stopFocusGesture(); panel.contentView = nil; panel.close() }
        try await settle()
        try capture("01-discover", panel: panel, directory: artifactDirectory)
        guard node("marketplace.import", in: panel) != nil else {
            throw XCTSkip("The visible disposable panel did not expose SwiftUI accessibility proxies. Screenshots were captured; native action acceptance remains unverified.")
        }
        XCTAssertTrue(panel.isVisible)
        XCTAssertLessThanOrEqual(host.bounds.width, 881)
        XCTAssertLessThanOrEqual(host.bounds.height, 641)
        XCTAssertTrue(try text("marketplace.outfit.current", in: panel).contains("No item"))
        XCTAssertTrue(try text("marketplace.outfit.saved", in: panel).contains("no saved outfit"))

        // Exercise the same review sheet using a strictly decoded recipe, without
        // opening a native file chooser or claiming that the chooser was tested.
        let imported = try CompanionItemPackage.decode(CompanionItemCatalog.designs[0].encoded())
        store.marketplaceMessage = "Decoded synthetic recipe. Review it before adding."
        store.importedMarketItem = imported
        try await waitUntil { panel.attachedSheet != nil }
        let review = try XCTUnwrap(panel.attachedSheet)
        try await settle()
        XCTAssertTrue(try text("marketplace.import.status", in: review).contains("Decoded synthetic recipe"))
        try capture("02-import-review", panel: review, directory: artifactDirectory)
        try press("marketplace.variation", in: review)
        try await waitUntil { panel.attachedSheet == nil && self.node("marketplace.create.title", in: panel) != nil }
        XCTAssertNil(store.importedMarketItem)
        XCTAssertNil(panel.attachedSheet, "Create must be revealed after the review sheet closes.")
        XCTAssertTrue(try text("marketplace.create.title", in: panel).contains(imported.title))
        try capture("03-create-variation", panel: panel, directory: artifactDirectory)

        try press("marketplace.collect", in: panel)
        try await waitUntil { store.itemLibrary.count == 1 && self.node("marketplace.equip", in: panel) != nil }
        let variation = try XCTUnwrap(store.itemLibrary.first)
        XCTAssertEqual(variation.title, imported.title)
        XCTAssertEqual(variation.creator, "Local creator")
        XCTAssertNotEqual(variation.id, imported.id)
        XCTAssertTrue(store.preferences.equipment.isEmpty, "Adding a recipe must not equip it implicitly.")
        XCTAssertNil(try NativePreferencePersistence.read(profile).document.preferences)
        try press("marketplace.equip", in: panel)
        try await waitUntil { store.preferences.equipment.design == variation && self.node("marketplace.use-work-together", in: panel) != nil }
        XCTAssertTrue(try text("marketplace.outfit.current", in: panel).contains(variation.title))
        XCTAssertTrue(try text("marketplace.outfit.saved", in: panel).contains("no saved outfit"))

        try press("marketplace.use-work-together", in: panel)
        try await waitUntil { store.section == .context && self.node("work.focus-staff", in: panel) != nil }
        XCTAssertEqual(store.sharedText, source)
        XCTAssertEqual(store.sourceName, "synthetic-workshop.txt")
        XCTAssertNil(store.textSelection, "Navigation cannot invent a selection or read another source.")
        XCTAssertNil(store.focusGesturePlayback)
        XCTAssertEqual(assistant.calls, 0)
        let document = try XCTUnwrap(nodes(panel).compactMap { $0 as? NSTextView }
            .first { $0.identifier?.rawValue == "shared-document-text" })
        XCTAssertEqual(document.string, source, "The app's actual document view must contain the shared copy.")
        panel.makeFirstResponder(document)
        document.setSelectedRange(NSRange(location: 0, length: 17))
        try await waitUntil { store.textSelection?.quote == "A useful passage." }
        try await settle()
        XCTAssertTrue(try text("work.selection-status", in: panel).contains("17"))
        try capture("04-work-together-selection", panel: panel, directory: artifactDirectory)

        // Return through the existing store navigation, then activate the native
        // route to the one existing preference owner and its Save controls.
        store.open(.marketplace)
        try await waitUntil { self.node("marketplace.outfit.review", in: panel) != nil }
        try press("marketplace.outfit.review", in: panel)
        try await waitUntil { store.section == .memory }
        try await settle()
        try capture("05-memory-save-controls", panel: panel, directory: artifactDirectory)
        try pressLabel("Remember my preferences", in: panel)
        try await waitUntil { store.rememberPreferences }
        try pressLabel("Save preferences", in: panel)
        try await waitUntil { store.savedMarketplaceEquipment?.design == variation }
        XCTAssertEqual(try NativePreferencePersistence.read(profile).document.preferences?.equipment.design, variation)
        store.open(.marketplace)
        try await waitUntil { self.node("marketplace.outfit.saved", in: panel) != nil }
        XCTAssertTrue(try text("marketplace.outfit.saved", in: panel).contains(variation.title))
        try capture("05-saved-outfit", panel: panel, directory: artifactDirectory)

        // An imported collected variation displays the real Unequip control.
        store.importedMarketItem = try CompanionItemPackage.decode(variation.encoded())
        try await waitUntil { panel.attachedSheet != nil }
        let equippedReview = try XCTUnwrap(panel.attachedSheet)
        try await settle()
        try press("marketplace.equip", in: equippedReview)
        try await waitUntil { store.preferences.equipment.isEmpty }
        try await settle()
        XCTAssertTrue(try text("marketplace.import.status", in: equippedReview).localizedCaseInsensitiveContains("unequip"))
        XCTAssertNil(node("marketplace.use-work-together", in: equippedReview))
        try press("marketplace.import.done", in: equippedReview)
        try await waitUntil { panel.attachedSheet == nil }
        XCTAssertTrue(try text("marketplace.outfit.current", in: panel).contains("No item"))
        XCTAssertTrue(try text("marketplace.outfit.saved", in: panel).contains(variation.title),
                      "This visit's unequip must not claim to erase the saved outfit.")
        try capture("06-current-vs-next-visit", panel: panel, directory: artifactDirectory)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.presentationForm(for: store.preferences, role: .cursor), .kinSeed)
        XCTAssertEqual(assistant.calls, 0)
        XCTAssertNil(play.webView, "Arena stays absent from this acceptance host.")
        await store.shutdownAssistant()
        await play.shutdown()
        let reopened = CompanionStore(preferenceURL: profile, assistant: assistant,
            assistantFactory: { _, _ in assistant }, allowsPlay: false)
        XCTAssertEqual(reopened.itemLibrary, [variation])
        XCTAssertEqual(reopened.preferences.equipment.design, variation)
        XCTAssertEqual(reopened.activeQiMon, identity)
        XCTAssertEqual(assistant.calls, 0)
        await reopened.shutdownAssistant()
    }

    @MainActor private func settle() async throws { try await Task.sleep(for: .milliseconds(180)) }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(15))
        }
        _ = try XCTUnwrap(condition() ? true : nil,
                          "Native presentation did not reach its expected state within three seconds.")
    }

    @MainActor private func nodes(_ root: NSObject) -> [NSObject] {
        var found: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ node: NSObject, depth: Int) {
            guard depth < 35, found.count < 2500, seen.insert(ObjectIdentifier(node)).inserted else { return }
            found.append(node)
            let selector = NSSelectorFromString("accessibilityChildren")
            if node.responds(to: selector), let children = node.perform(selector)?.takeUnretainedValue() as? [NSObject] {
                for child in children { visit(child, depth: depth + 1) }
            }
            if node.accessibilityAttributeNames().contains(.children) {
                for child in node.accessibilityAttributeValue(.children) as? [NSObject] ?? [] { visit(child, depth: depth + 1) }
            }
            if let window = node as? NSWindow, let content = window.contentView { visit(content, depth: depth + 1) }
            if let view = node as? NSView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        visit(root, depth: 0); return found
    }

    @MainActor private func identifier(_ node: NSObject) -> String? {
        let selector = NSSelectorFromString("accessibilityIdentifier")
        return (node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil)
            ?? (node.accessibilityAttributeNames().contains(.identifier) ? node.accessibilityAttributeValue(.identifier) as? String : nil)
    }

    @MainActor private func role(_ node: NSObject) -> String? {
        let selector = NSSelectorFromString("accessibilityRole")
        return (node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil)
            ?? (node.accessibilityAttributeNames().contains(.role) ? node.accessibilityAttributeValue(.role) as? String : nil)
    }

    @MainActor private func isEnabled(_ node: NSObject) throws -> Bool {
        let selector = NSSelectorFromString("isAccessibilityEnabled")
        if node.responds(to: selector) {
            let getter = unsafeBitCast(node.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
            return getter(node, selector)
        }
        return try XCTUnwrap(node.accessibilityAttributeValue(.enabled) as? NSNumber,
                             "The native action must expose its enabled state.").boolValue
    }

    @MainActor private func texts(_ node: NSObject) -> [String] {
        let modern = ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].compactMap { name -> String? in
            let selector = NSSelectorFromString(name)
            return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil
        }
        return modern + [.title, .value, .description].compactMap { attribute -> String? in
            node.accessibilityAttributeNames().contains(attribute) ? node.accessibilityAttributeValue(attribute) as? String : nil
        }
    }

    @MainActor private func node(_ id: String, in root: NSObject) -> NSObject? { nodes(root).first { identifier($0) == id } }
    @MainActor private func text(_ id: String, in root: NSObject) throws -> String {
        texts(try XCTUnwrap(node(id, in: root), "Missing accessible text \(id)")).joined(separator: " | ")
    }
    @MainActor private func press(_ id: String, in root: NSObject) throws {
        try performPress(XCTUnwrap(node(id, in: root), "Missing native control \(id)"))
    }
    @MainActor private func pressLabel(_ label: String, in root: NSObject) throws {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        let actionableRoles: Set<String> = ["AXButton", "AXCheckBox", "AXSwitch"]
        let match = nodes(root).first {
            texts($0).contains(label) && actionableRoles.contains(role($0) ?? "") && $0.responds(to: selector)
        }
        try performPress(XCTUnwrap(match, "Missing native action \(label)"))
    }
    @MainActor private func performPress(_ node: NSObject) throws {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        _ = try XCTUnwrap(node.responds(to: selector) ? true : nil, "Native element has no accessibility press action.")
        let action = unsafeBitCast(node.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
        _ = try XCTUnwrap(action(node, selector) ? true : nil, "The native accessibility press action failed.")
    }

    @MainActor private func capture(_ name: String, panel: NSWindow, directory: URL?) throws {
        guard let directory, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        }
        let evidence: [String: Any] = ["windowShown": panel.isVisible, "width": content.bounds.width,
            "height": content.bounds.height, "nodes": nodes(panel).map {
                ["id": identifier($0) ?? "", "role": role($0) ?? "", "text": texts($0).joined(separator: " | ")]
            },
            "boundary": "Native SwiftUI action controls with a disposable profile and decoded import fixture. No native Open/Save panel, keyboard navigation, VoiceOver, model or external service proof."]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name + ".json"))
    }
}

@MainActor private final class MarketplaceInteractionNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.configuration
    }
    func disconnect() {}
}
