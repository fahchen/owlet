import AppKit
import SwiftUI

/// The one selection toolbar or lookup card of a reading area. Both live in a system popover; only
/// one is shown, and a closed one is never brought back by a late answer.
@MainActor @Observable
final class LookupPresenter: NSObject, NSPopoverDelegate {
    enum Mode: Equatable {
        /// The current selection, or why it cannot be looked up.
        case toolbar(Result<LookupQuery, LookupQuery.Refusal>)
        /// `other` is a compatible answer from another sentence, shown until the user rechecks.
        case card(LookupQuery, other: LookupQuery?)
    }

    private(set) var mode: Mode?
    let store: LookupStore
    let speech: LookupSpeech
    /// The notebook a card's 加入生词本 writes to; nil keeps the card read-only, which is how the
    /// tests and previews build it.
    var collection: CollectionAction?
    private var popover: NSPopover?
    private weak var anchor: NSView?
    /// The text holding this window's selection; a new selection elsewhere clears it, so a window
    /// never shows two selections, the older one gray.
    private weak var selectionOwner: NSTextView?

    init(store: LookupStore, speech: LookupSpeech = .live) {
        self.store = store
        self.speech = speech
    }

    var isShown: Bool { mode != nil }

    /// A settled selection only offers 查询; nothing is requested until the user picks it.
    func showToolbar(
        _ query: Result<LookupQuery, LookupQuery.Refusal>, at rect: NSRect, in view: NSView?
    ) {
        present(.toolbar(query), at: rect, in: view)
    }

    /// A new selection in `view` takes over from any other text in the window.
    func selectionTaken(by view: NSTextView) {
        if let old = selectionOwner, old !== view {
            old.setSelectedRange(NSRange(location: old.selectedRange().location, length: 0))
        }
        selectionOwner = view
    }

    /// The selection went away, so its toolbar cannot query it any more. A card stays.
    func selectionCleared(in view: NSView) {
        guard anchor === view, case .toolbar? = mode else { return }
        close()
    }

    /// The text under the popover was replaced, so neither its toolbar nor its card applies.
    func textReplaced(in view: NSView) {
        guard anchor === view else { return }
        close(refocus: false)
    }

    /// The toolbar's 查询: the card replaces it in the same popover.
    func confirmToolbar() {
        guard case .toolbar(.success(let query))? = mode else { return }
        lookUp(query, at: nil, in: nil)
    }

    /// An explicit lookup; with no anchor it reuses the popover already on screen.
    func lookUp(_ query: LookupQuery, at rect: NSRect?, in view: NSView?) {
        speech.stop()
        let query = store.stamped(query)
        let other = store.open(query)
        if let rect, let view {
            present(.card(query, other: other), at: rect, in: view)
        } else {
            mode = .card(query, other: other)
        }
    }

    /// 重试 and 按当前语境重查: the current query only, re-stamped so a changed model or reading
    /// notation reaches the request and the key it is cached under together. A failed recheck keeps
    /// the other answer.
    func requestCurrent() {
        guard case .card(let query, let other)? = mode else { return }
        let stamped = store.stamped(query)
        mode = .card(stamped, other: other)
        store.request(stamped)
    }

    func speak(_ text: String, language: String) {
        speech.speak(text, language)
    }

    /// Closes whichever popover is up and, unless the reading area itself is going away, hands
    /// focus back to the text; false when nothing was up.
    @discardableResult
    func close(refocus: Bool = true) -> Bool {
        guard mode != nil || popover != nil else { return false }
        let popover = popover
        self.popover = nil
        popover?.close()
        finish(refocus: refocus)
        return true
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        popover = nil
        finish()
    }

    private func finish(refocus: Bool = true) {
        mode = nil
        speech.stop()
        if refocus, let anchor, let window = anchor.window {
            window.makeKey()
            window.makeFirstResponder(anchor)
        }
    }

    private func present(_ mode: Mode, at rect: NSRect, in view: NSView?) {
        speech.stop()
        self.mode = mode
        guard let view, view.window != nil else { return }
        anchor = view
        if let popover, popover.isShown, popover.positioningRect == rect {
            return
        }
        let old = popover
        popover = nil
        old?.close()
        let host = NSHostingController(rootView: LookupPopoverContent(presenter: self))
        host.sizingOptions = .preferredContentSize
        let next = NSPopover()
        next.behavior = .transient
        next.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        next.contentViewController = host
        next.delegate = self
        popover = next
        next.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        // A popover takes the keyboard when shown. The toolbar must not, or a keyboard selection
        // would stop growing after its first step; the card keeps it so Tab reaches its buttons.
        if case .toolbar = mode {
            view.window?.makeKey()
            view.window?.makeFirstResponder(view)
        }
    }
}

extension EnvironmentValues {
    /// The reading area's lookup presenter; reading text without one stays plain selectable text.
    @Entry var lookups: LookupPresenter?
}

/// The popover's content: the one-action selection toolbar, or the card.
private struct LookupPopoverContent: View {
    let presenter: LookupPresenter

    var body: some View {
        switch presenter.mode {
        // The popover is the toolbar's surface, so the action inside carries no bezel of its own; its
        // title says what it does, so it needs no hover tip either.
        case .toolbar(.success)?:
            Button {
                presenter.confirmToolbar()
            } label: {
                Label("查询", systemImage: "character.book.closed").foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        case .toolbar(.failure(let refusal))?:
            Label(refusal.message, systemImage: "character.book.closed")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        case .card(let query, let other)?:
            LookupCard(presenter: presenter, query: query, other: other)
        case nil:
            EmptyView()
        }
    }
}
