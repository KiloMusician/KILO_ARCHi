import AppKit
import Testing
@testable import ARCHiDesktop

@MainActor
struct SelectedPassageGeometryTests {
    @Test func duplicateTextUsesSelectedOccurrenceAndGlobalBottomLeftCoordinates() throws {
        let fixture = try PassageGeometryFixture(text: "Target phrase\nSpacer line\nTarget phrase")
        defer { fixture.close() }
        let firstRange = (fixture.text.string as NSString).range(of: "Target phrase")
        let lastRange = (fixture.text.string as NSString).range(of: "Target phrase", options: .backwards)
        fixture.select(firstRange)
        let first = try #require(fixture.observe())
        fixture.select(lastRange)
        let second = try #require(fixture.observe())
        #expect(first.selection.quote == second.selection.quote)
        #expect(first.selection.range != second.selection.range)
        #expect(second.selection.range == lastRange)
        let firstRect = try #require(first.rects.first)
        let secondRect = try #require(second.rects.first)
        #expect(firstRect.midY > secondRect.midY)
        #expect(second.rects.allSatisfy { second.viewport.contains($0) && second.windowFrame.contains($0) })
        #expect(second.windowNumber == fixture.window.windowNumber)
        #expect(second.screenID != 0)
        #expect(second.screenFrame.contains(second.viewport))
        #expect(fixture.store.onObserveSelectedPassage?() == nil) // Test window never takes key focus.
    }

    @Test func emojiAndMultilineSelectionProduceActualVisibleGlyphRectangles() throws {
        let fixture = try PassageGeometryFixture(text: "A🌙 café\nsecond line\nthird line")
        defer { fixture.close() }
        let range = (fixture.text.string as NSString).range(of: "🌙 café\nsecond line")
        fixture.select(range)
        let geometry = try #require(fixture.observe())
        #expect(geometry.selection.range == range)
        #expect(geometry.selection.quote == "🌙 café\nsecond line")
        #expect(geometry.rects.count >= 2)
        #expect(geometry.rects.allSatisfy { $0.width > 0 && $0.height > 0 && geometry.viewport.contains($0) })
        // Composer focus hides only native selection; geometry still comes from
        // the exact stored passage rather than an inactive caret or quote search.
        fixture.coordinator.textFocusChanged(false)
        #expect(fixture.text.selectedRange().length == 0)
        #expect(fixture.observe() == geometry)
    }

    @Test func partialAndOffscreenSelectionsAreRejectedWithoutScrolling() throws {
        let fixture = try PassageGeometryFixture(text: String(repeating: "One source line.\n", count: 150), height: 90)
        defer { fixture.close() }
        fixture.select(NSRange(location: 0, length: (fixture.text.string as NSString).length))
        let origin = fixture.scroll.contentView.bounds.origin
        #expect(fixture.observe() == nil)
        #expect(fixture.scroll.contentView.bounds.origin == origin)
        #expect(fixture.store.textSelection != nil)
        fixture.select((fixture.text.string as NSString).range(of: "One source line.", options: .backwards))
        #expect(fixture.observe() == nil)
        #expect(fixture.scroll.contentView.bounds.origin == origin)
    }

    @Test func changedSourceOrDetachedWindowCannotYieldOldGeometry() throws {
        let fixture = try PassageGeometryFixture(text: "Selected old source")
        defer { fixture.close() }
        fixture.select(NSRange(location: 0, length: 8))
        #expect(fixture.observe() != nil)
        fixture.store.share(text: "Selected new source", name: "new.txt")
        fixture.store.selectText(range: NSRange(location: 0, length: 8), sourceRevision: fixture.store.sourceRevision)
        #expect(fixture.observe() == nil)
        fixture.coordinator.render()
        #expect(fixture.observe() != nil)
        fixture.window.contentView = nil
        #expect(fixture.observe() == nil)
        #expect(fixture.store.textSelection == nil)
    }

    @Test func hiddenWindowAndMissingTargetAreIneligible() throws {
        let fixture = try PassageGeometryFixture(text: "A visible source")
        defer { fixture.close() }
        #expect(fixture.observe() == nil)
        fixture.select(NSRange(location: 2, length: 7))
        #expect(fixture.observe() != nil)
        fixture.window.orderOut(nil)
        #expect(fixture.observe() == nil)
    }

    @Test func oldCoordinatorCannotClearReplacementObserverOrItsSelection() throws {
        let fixture = try PassageGeometryFixture(text: "A selected source")
        defer { fixture.close() }
        let oldCallback = fixture.store.onObserveSelectedPassage
        let replacement = SharedDocumentView.Coordinator(store: fixture.store)
        let replacementView = replacement.makeView()
        defer { withExtendedLifetime(replacementView) { replacement.dismantle() } }
        let replacementID = fixture.store.selectedPassageObserverID
        fixture.store.selectText(range: NSRange(location: 2, length: 8), sourceRevision: fixture.store.sourceRevision)
        let selection = fixture.store.textSelection
        fixture.text.setSelectedRange(NSRange(location: 0, length: 1))
        fixture.coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: fixture.text))
        #expect(fixture.store.textSelection == selection)
        fixture.coordinator.dismantle()
        #expect(fixture.store.selectedPassageObserverID == replacementID)
        #expect(fixture.store.onObserveSelectedPassage != nil)
        #expect(fixture.store.textSelection == selection)
        #expect(oldCallback?() == nil)
        replacement.dismantle()
        #expect(fixture.store.onObserveSelectedPassage == nil)
        #expect(fixture.store.selectedPassageObserverID == nil)
    }
}

@MainActor
private final class PassageGeometryFixture {
    let store: CompanionStore
    let coordinator: SharedDocumentView.Coordinator
    let scroll: NSScrollView
    let text: NSTextView
    let window: NSPanel

    init(text source: String, height: CGFloat = 280) throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main ?? NSScreen.screens.first, "Native geometry tests require a display")
        store = CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"))
        store.share(text: source, name: "fixture.txt")
        coordinator = SharedDocumentView.Coordinator(store: store)
        scroll = coordinator.makeView()
        text = try #require(scroll.documentView as? NSTextView)
        let area = screen.visibleFrame
        window = NSPanel(contentRect: CGRect(x: area.minX + 24, y: area.minY + 24, width: 440, height: height),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.contentView = scroll
        window.orderBack(nil)
        scroll.needsLayout = true
        scroll.layoutSubtreeIfNeeded()
        let container = try #require(text.textContainer)
        text.layoutManager?.ensureLayout(for: container)
        coordinator.render()
    }

    func select(_ range: NSRange) {
        store.selectText(range: range, sourceRevision: store.sourceRevision)
        coordinator.render()
    }

    func observe() -> SelectedPassageGeometry? { coordinator.observeSelectedPassage(requireKeyWindow: false) }

    func close() {
        coordinator.dismantle()
        window.orderOut(nil)
        window.close()
    }
}
