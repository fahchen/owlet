import AppKit
import NaturalLanguage
import SwiftUI

/// Read-only reading text that can be looked up. A native text view keeps drag and double-click
/// selection, ⌘C and the system menu; a settled selection offers 查询 and nothing is requested
/// until the user picks it from the toolbar, the menu, Return or the accessibility action. ⌘-click
/// looks up the word under the pointer, and holding ⌘ previews which word that is.
struct LookupText: NSViewRepresentable {
    let text: String
    var size: CGFloat = 17
    var weight: NSFont.Weight = .regular
    var lineSpacing: CGFloat = 2
    var justified = false
    /// Secondary text, such as a polish's 润色前, which reads quieter than what replaced it.
    var secondary = false
    /// What the text is, for VoiceOver.
    var label = "结果"
    /// nil keeps the text selectable without offering a lookup.
    let origin: LookupOrigin?
    /// The sentence this text was taken from; a selection in the text is looked up inside it.
    var sentence: String? = nil
    /// Whether this text has a source sentence at all. A standalone expression — a notebook entry's
    /// own form — has none, so looking it up asks for the general meaning and the card says
    /// 无原句语境 instead of passing the expression off as its own context.
    var hasSentence = true
    /// Set on a learning row: a plain click is the row's own action (collect); ⌘-click and a
    /// selection still look up.
    var onPlainClick: (() -> Void)? = nil
    @Environment(\.lookups) private var presenter

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
        return view
    }

    func updateNSView(_ view: LookupTextView, context: Context) {
        view.origin = presenter == nil ? nil : origin
        view.presenter = presenter
        view.sentence = sentence
        view.hasSentence = hasSentence
        view.onPlainClick = onPlainClick
        view.setAccessibilityLabel(label)
        let style: [CGFloat] = [size, weight.rawValue, lineSpacing, justified ? 1 : 0, secondary ? 1 : 0]
        guard view.string != text || view.style != style else { return }
        // New text is a new reading, so a toolbar or card for the old one goes with it.
        if view.string != text { presenter?.textReplaced(in: view) }
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
                    .foregroundColor: secondary ? NSColor.secondaryLabelColor : NSColor.textColor,
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
    var sentence: String?
    /// Whether a lookup in this text has a source sentence to explain it inside (see `LookupText`).
    var hasSentence = true
    var onPlainClick: (() -> Void)?
    /// Size, weight, line spacing and alignment last applied, so an unchanged update leaves the selection.
    var style: [CGFloat] = []
    /// A learning row's plain click, waiting out the double-click interval.
    private var pendingClick: Task<Void, Never>?
    /// The word under the pointer while ⌘ is held, tinted until ⌘ or the pointer leaves.
    private var hovered: NSRange?
    /// Watches ⌘ while the pointer is over the text, so pressing or releasing it without moving
    /// the mouse updates the tint and cursor at once.
    private var modifierMonitor: Any?
    private let words = NLTokenizer(unit: .word)

    /// The ⌘ hover tints the word with the selection color at reduced strength (DESIGN 封闭例外):
    /// the same color as a selection, so it reads as "this can be picked", but clearly weaker.
    static let hoverOpacity: CGFloat = 0.3

    /// Leaving the window — another page, a closed panel — takes this text's toolbar or card with it,
    /// so a late answer has nothing to reopen.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            presenter?.textReplaced(in: self)
            stopWatchingModifiers()
        }
    }

    /// Esc closes this text's toolbar or card first; with none up it goes on as before.
    override func cancelOperation(_ sender: Any?) {
        if presenter?.isShown == true, presenter?.close() == true { return }
        super.cancelOperation(sender)
    }

    /// ⌘-click looks up the word under the pointer at once; a plain click is an ordinary text click,
    /// so double-click word selection, drag selection and copy are untouched.
    override func mouseDown(with event: NSEvent) {
        pendingClick?.cancel()
        pendingClick = nil
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command), let word = word(at: point),
            case .success(let query)? = query(for: word)
        {
            setHover(nil)
            presenter?.lookUp(query, at: rect(for: word), in: self)
            // The text owns this click to its end; otherwise the mouse up reaches the row around it,
            // and a learning row would also collect.
            _ = window?.nextEvent(matching: .leftMouseUp)
            return
        }
        setHover(nil)
        // NSTextView tracks the whole gesture here and returns on mouse up.
        super.mouseDown(with: event)
        guard let onPlainClick, event.clickCount == 1, selectedRange().length == 0 else { return }
        // A learning row collects on a click, but waits out a double-click so selecting a word in
        // it never also collects it.
        pendingClick = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard !Task.isCancelled, self?.selectedRange().length == 0 else { return }
            onPlainClick()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        // The panel never activates Owlet, so hover has to track while the app is inactive.
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard modifierMonitor == nil else { return }
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.refreshHover(command: event.modifierFlags.contains(.command))
            return event
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        refreshHover(command: event.modifierFlags.contains(.command))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHover(nil)
        stopWatchingModifiers()
    }

    /// While ⌘ is held the word under the pointer is tinted and the cursor becomes the pointing
    /// hand; otherwise the text reads as text, with the I-beam. Cursor rects do not apply while Owlet
    /// is inactive, which the panel always leaves it, so the cursor is set here.
    private func refreshHover(command: Bool) {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let word = command && origin != nil ? word(at: point) : nil
        // A selection already shows its own highlight; the tint never stacks on it.
        setHover(word.flatMap { NSIntersectionRange($0, selectedRange()).length == 0 ? $0 : nil })
        (word == nil ? NSCursor.iBeam : NSCursor.pointingHand).set()
    }

    private func stopWatchingModifiers() {
        if let modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }
        modifierMonitor = nil
    }

    /// A temporary attribute is drawn by the layout manager without changing layout.
    private func setHover(_ range: NSRange?) {
        guard range != hovered, let layout = layoutManager else { return }
        if let hovered { layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: hovered) }
        hovered = range
        if let range {
            layout.addTemporaryAttribute(
                .backgroundColor,
                value: NSColor.selectedTextBackgroundColor.withAlphaComponent(Self.hoverOpacity),
                forCharacterRange: range)
        }
    }

    /// The word whose glyph is actually under `point`: the nearest glyph is not enough, so empty
    /// space after a line, between lines or past the text hits nothing.
    func word(at point: NSPoint) -> NSRange? {
        guard let layout = layoutManager, let container = textContainer, !string.isEmpty else {
            return nil
        }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: local, in: container)
        guard glyph < layout.numberOfGlyphs,
            layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
                .contains(local)
        else { return nil }
        if words.string != string { words.string = string }
        return Self.word(at: layout.characterIndexForGlyph(at: glyph), in: string, tokenizer: words)
    }

    /// The system word around a character; whitespace and punctuation are not part of any word,
    /// so a click on them looks nothing up instead of a neighbour.
    static func word(at index: Int, in text: String, tokenizer: NLTokenizer) -> NSRange? {
        guard let position = Range(NSRange(location: index, length: 1), in: text)?.lowerBound else {
            return nil
        }
        let token = tokenizer.tokenRange(at: position)
        guard token.contains(position),
            text[position].unicodeScalars.contains(where: CharacterSet.alphanumerics.contains)
        else { return nil }
        return NSRange(token, in: text)
    }

    /// The selection as a lookup, or why it cannot be one; nil when nothing is selected.
    var selectedQuery: Result<LookupQuery, LookupQuery.Refusal>? {
        let range = selectedRange()
        return range.length > 0 ? query(for: range) : nil
    }

    /// A range of this text as a lookup, inside its source sentence when the text is a phrase taken
    /// from one, so the explanation is the meaning there rather than the phrase on its own. A text
    /// that stands alone has no sentence to be read in, and says so rather than posing as one.
    func query(for range: NSRange) -> Result<LookupQuery, LookupQuery.Refusal>? {
        guard let origin else { return nil }
        if let sentence, let within = sentence.range(of: string) {
            let base = NSRange(within, in: sentence).location
            return LookupQuery.make(
                selection: NSRange(location: base + range.location, length: range.length), in: sentence,
                origin: origin)
        }
        guard hasSentence else {
            guard let text = Self.trimmed(self.string, range: range) else { return .failure(.empty) }
            return .success(LookupQuery.withoutContext(text, origin: origin))
        }
        return LookupQuery.make(selection: range, in: string, origin: origin)
    }

    /// The selected characters with surrounding whitespace dropped, or nil when only whitespace was
    /// selected; punctuation still has to pass `LookupQuery`'s own check.
    static func trimmed(_ text: String, range: NSRange) -> String? {
        guard let range = Range(range, in: text) else { return nil }
        let trimmed = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Only a finished gesture — mouse up, a double-click, a keyboard step — offers the toolbar;
    /// a drag in progress does not.
    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !stillSelecting, let presenter else { return }
        if selectedRange().length > 0 { presenter.selectionTaken(by: self) }
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
