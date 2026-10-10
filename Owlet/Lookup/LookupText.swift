import AppKit
import SwiftUI

/// Read-only reading text that can be looked up. A native text view keeps drag and double-click
/// selection, ⌘C and the system menu; a settled selection offers 查询 and nothing is requested
/// until the user picks it from the toolbar, the menu, Return or the accessibility action.
struct LookupText: NSViewRepresentable {
    let text: String
    var size: CGFloat = 17
    var weight: NSFont.Weight = .regular
    var lineSpacing: CGFloat = 2
    var justified = false
    /// nil keeps the text selectable without offering a lookup.
    let origin: LookupOrigin?
    let presenter: LookupPresenter

    func makeNSView(context: Context) -> LookupTextView {
        let view = LookupTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isRichText = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.setAccessibilityLabel("结果")
        return view
    }

    func updateNSView(_ view: LookupTextView, context: Context) {
        view.origin = origin
        view.presenter = presenter
        let style: [CGFloat] = [size, weight.rawValue, lineSpacing, justified ? 1 : 0]
        guard view.string != text || view.style != style else { return }
        // New text is a new reading, so a toolbar or card for the old one goes with it.
        if view.string != text { presenter.textReplaced(in: view) }
        view.style = style
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = justified ? .justified : .natural
        paragraph.lineSpacing = lineSpacing
        view.textStorage?.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: weight),
                    // labelColor reads lighter over the panel glass; textColor matches the editable source.
                    .foregroundColor: NSColor.textColor,
                    .paragraphStyle: paragraph,
                ]))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: LookupTextView, context: Context)
        -> CGSize?
    {
        guard let width = proposal.width, width.isFinite, let container = view.textContainer,
            let layout = view.layoutManager
        else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(layout.usedRect(for: container).height))
    }
}

final class LookupTextView: NSTextView {
    var origin: LookupOrigin?
    weak var presenter: LookupPresenter?
    /// Size, weight, line spacing and alignment last applied, so an unchanged update leaves the selection.
    var style: [CGFloat] = []

    /// The selection as a lookup, or why it cannot be one; nil when nothing is selected.
    var selectedQuery: Result<LookupQuery, LookupQuery.Refusal>? {
        let range = selectedRange()
        guard range.length > 0, let origin else { return nil }
        return LookupQuery.make(selection: range, in: string, origin: origin)
    }

    /// Only a finished gesture — mouse up, a double-click, a keyboard step — offers the toolbar;
    /// a drag in progress does not.
    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !stillSelecting, let presenter else { return }
        if let query = selectedQuery {
            presenter.showToolbar(query, at: rect(for: selectedRange()), in: self)
        } else {
            presenter.selectionCleared(in: self)
        }
    }

    /// The panel never activates Owlet, so ⌘C cannot count on reaching an Edit menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "c", window?.firstResponder === self,
            selectedRange().length > 0
        {
            copy(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func lookUpSelection(_ sender: Any?) {
        guard case .success(let query)? = selectedQuery else { return }
        presenter?.lookUp(query, at: rect(for: selectedRange()), in: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard selectedQuery != nil else { return menu }
        let item = NSMenuItem(
            title: "查询所选", action: #selector(lookUpSelection(_:)), keyEquivalent: "")
        item.target = self
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(lookUpSelection(_:)) {
            guard case .success? = selectedQuery else { return false }
            return true
        }
        return super.validateMenuItem(item)
    }

    /// Return on a selection is the keyboard's 查询; the text is read-only, so Return had no use.
    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        if plain, [36, 76].contains(event.keyCode), case .success? = selectedQuery {
            lookUpSelection(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard case .success? = selectedQuery else { return super.accessibilityCustomActions() }
        return [
            NSAccessibilityCustomAction(name: "查询所选") { [weak self] in
                self?.lookUpSelection(nil)
                return true
            }
        ]
    }

    /// The selection's bounds in this view, which is where the popover points.
    func rect(for range: NSRange) -> NSRect {
        guard let layout = layoutManager, let container = textContainer else { return bounds }
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect
    }
}
