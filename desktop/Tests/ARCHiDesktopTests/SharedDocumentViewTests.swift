import AppKit
import Testing
@testable import ARCHiDesktop

@MainActor
struct SharedDocumentViewTests {
    private func setup(_ value: String = "A🌙 café\n" + String(repeating: "Read the exact source.\n", count: 200)) throws -> (CompanionStore, SharedDocumentView.Coordinator, NSScrollView, NSTextView) {
        _ = NSApplication.shared
        let store = CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"))
        store.share(text: value, name: "fixture.txt")
        let coordinator = SharedDocumentView.Coordinator(store: store)
        let scroll = coordinator.makeView()
        let text = try #require(scroll.documentView as? NSTextView)
        scroll.needsLayout = true
        scroll.layoutSubtreeIfNeeded()
        return (store, coordinator, scroll, text)
    }

    @Test func fullSourceAndExactUnicodeSelectionRemainNativeAndReadOnly() throws {
        let source = "A🌙 café\n" + String(repeating: "source line\n", count: 7_000)
        let (store, coordinator, scroll, text) = try setup(source)
        defer { withExtendedLifetime(scroll) { coordinator.dismantle() } }
        #expect(!text.isEditable)
        #expect(text.isSelectable)
        #expect(text.string.utf8.elementsEqual(source.utf8))
        #expect(text.identifier?.rawValue == "shared-document-text")
        text.setSelectedRange(NSRange(location: 1, length: 2))
        #expect(store.textSelection?.quote == "🌙")
        coordinator.render()
        #expect(text.selectedRange() == NSRange(location: 1, length: 2))
        let color = text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 1, effectiveRange: nil)
        #expect(color as? NSColor != nil)
        #expect(text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil)
    }

    @Test func unchangedRenderPreservesSelectionAndCaretForKeyboardExtension() throws {
        let (store, coordinator, scroll, text) = try setup()
        defer { withExtendedLifetime(scroll) { coordinator.dismantle() } }
        text.setSelectedRange(NSRange(location: 1, length: 2))
        let selection = store.textSelection
        let ticket = store.contextTicket()
        coordinator.render()
        coordinator.render()
        #expect(store.textSelection == selection)
        #expect(store.isCurrent(ticket, requireVisible: false))
        text.setSelectedRange(NSRange(location: 5, length: 0))
        coordinator.render()
        #expect(store.textSelection == nil)
        #expect(text.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test func staleSourceDelegateCannotReplaceNewSourceSelection() throws {
        let (store, coordinator, scroll, text) = try setup("old source")
        defer { withExtendedLifetime(scroll) { coordinator.dismantle() } }
        store.share(text: "new exact source", name: "new.txt")
        store.selectText(range: NSRange(location: 4, length: 5), sourceRevision: store.sourceRevision)
        let current = store.textSelection
        text.setSelectedRange(NSRange(location: 0, length: 3))
        #expect(store.textSelection == current)
        coordinator.render()
        #expect(text.string == "new exact source")
        #expect(text.selectedRange() == NSRange(location: 4, length: 5))
    }

    @Test func actualDocumentScrollClearsSelectionAndHighlightSynchronously() throws {
        let (store, coordinator, scroll, text) = try setup()
        defer { coordinator.dismantle() }
        text.setSelectedRange(NSRange(location: 1, length: 2))
        coordinator.render()
        scroll.contentView.setBoundsOrigin(CGPoint(x: 0, y: 20))
        #expect(store.textSelection == nil)
        #expect(text.selectedRange().length == 0)
        #expect(text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 1, effectiveRange: nil) == nil)
        // A delayed delegate notification reads the now-cleared native range;
        // no saved pre-scroll range is queued for later delivery.
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: text))
        #expect(store.textSelection == nil)
    }

    @Test func repeatedBoundsNotificationDoesNotInvalidateCurrentSelection() throws {
        let (store, coordinator, scroll, text) = try setup()
        defer { coordinator.dismantle() }
        text.setSelectedRange(NSRange(location: 1, length: 2))
        coordinator.render()
        let selection = store.textSelection
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        #expect(store.textSelection == selection)
    }

    @Test func resizeAndDismantleReleaseTheReference() throws {
        let (store, coordinator, scroll, text) = try setup()
        text.setSelectedRange(NSRange(location: 1, length: 2))
        coordinator.render()
        scroll.setFrameSize(CGSize(width: 380, height: 280))
        scroll.needsLayout = true
        scroll.layoutSubtreeIfNeeded()
        #expect(store.textSelection == nil)
        text.setSelectedRange(NSRange(location: 1, length: 2))
        coordinator.render()
        coordinator.dismantle()
        #expect(store.textSelection == nil)
        #expect(text.delegate == nil)
        text.setSelectedRange(NSRange(location: 4, length: 3))
        #expect(store.textSelection == nil)
    }

    @Test func firstLayoutDoesNotClearAnExistingSelection() throws {
        _ = NSApplication.shared
        let store = CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"))
        store.share(text: "Selection before mount", name: "fixture.txt")
        store.selectText(range: NSRange(location: 0, length: 9), sourceRevision: store.sourceRevision)
        let expected = store.textSelection
        let coordinator = SharedDocumentView.Coordinator(store: store)
        let scroll = coordinator.makeView()
        defer { coordinator.dismantle() }
        scroll.setFrameSize(CGSize(width: 650, height: 320))
        scroll.needsLayout = true
        scroll.layoutSubtreeIfNeeded()
        #expect(store.textSelection == expected)
    }

    @Test func focusOutKeepsWarmHighlightAndProvenanceThenFocusInRestoresNativeRange() throws {
        let (store, coordinator, scroll, text) = try setup()
        defer { withExtendedLifetime(scroll) { coordinator.dismantle() } }
        text.setSelectedRange(NSRange(location: 1, length: 2))
        coordinator.render()
        let selection = store.textSelection
        let ticket = store.contextTicket()
        // Exercise the callback directly: no window activation or user-focus side effects.
        coordinator.textFocusChanged(false)
        #expect(text.selectedRange().length == 0)
        #expect(store.textSelection == selection)
        #expect(store.isCurrent(ticket, requireVisible: false))
        #expect(text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 1, effectiveRange: nil) as? NSColor != nil)
        #expect(text.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil) as? NSColor == NSColor.black)
        coordinator.render()
        coordinator.render()
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: text))
        #expect(text.selectedRange().length == 0)
        #expect(store.textSelection == selection)
        #expect(store.isCurrent(ticket, requireVisible: false))
        coordinator.textFocusChanged(true)
        #expect(text.selectedRange() == NSRange(location: 1, length: 2))
        #expect(store.textSelection == selection)
        #expect(store.isCurrent(ticket, requireVisible: false))
    }

    @Test func focusReturnCannotRestoreAReferenceInvalidatedWhileTyping() throws {
        let (store, coordinator, scroll, text) = try setup()
        defer { coordinator.dismantle() }
        text.setSelectedRange(NSRange(location: 1, length: 2))
        coordinator.render()
        coordinator.textFocusChanged(false)
        scroll.contentView.setBoundsOrigin(CGPoint(x: 0, y: 20))
        #expect(store.textSelection == nil)
        coordinator.textFocusChanged(true)
        #expect(text.selectedRange().length == 0)
        #expect(text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 1, effectiveRange: nil) == nil)
    }
}
