import AppKit
import SwiftUI

/// Floating panel for shortcut-triggered translation: a compact notice until the first
/// success, then the full translation view, which stays expanded on later errors.
@MainActor @Observable
final class PanelController {
    enum Notice: Equatable {
        case translating
        case permission
        case screenPermission
        case unreadable
        case missingConfig
        /// The message the user reads, and which recovery it offers: a translated message must never
        /// decide whether the way out is the prompt editor or the service settings.
        case failure(String, kind: ModelError.Kind)
        /// The result could not be written back; the result stays copyable.
        case unwritten
        /// The selection cannot hold text, so the result was never typed anywhere.
        case unwritable
        case cancelled
        /// A result is still arriving: what is on screen is not yet one, so replace and copy wait.
        case receiving

        var message: String {
            switch self {
            case .translating: ""
            case .permission: L10n.shared.string("Needs permission to read the selection")
            case .screenPermission: L10n.shared.string("Needs permission to record the screen")
            case .unreadable: L10n.shared.string("Could not read any text")
            case .missingConfig: L10n.shared.string("The model service is not configured")
            case .failure(let message, let kind):
                switch kind {
                case .contract: L10n.shared.string("The reply's format is wrong. Check the prompt.")
                case .connection: L10n.shared.string("Connection failed. Check the model service.")
                case .service: message
                }
            case .unwritten: L10n.shared.string("Could not write back to the other app")
            case .unwritable: L10n.shared.string("The selection cannot be edited")
            case .cancelled: L10n.shared.string("Cancelled")
            case .receiving: L10n.shared.string("Still receiving the result. Replace once it is complete.")
            }
        }

        /// Label of the single recovery entry shown beside the message.
        var actionTitle: String {
            switch self {
            case .translating, .receiving, .unreadable: ""
            case .permission: L10n.shared.string("Permission Settings")
            case .screenPermission: L10n.shared.string("Screen Recording Settings")
            // The expanded source editor is the way out, so the explanation needs no button.
            case .missingConfig: L10n.shared.string("Configure Service")
            case .failure(_, let kind):
                kind == .contract ? L10n.shared.string("Prompt Settings") : L10n.shared.string("Service Settings")
            case .unwritten: L10n.shared.string("Copy Result")
            case .unwritable: L10n.shared.string("Copy Result")
            case .cancelled: L10n.shared.string("Try Again")
            }
        }

        /// Whether the recovery entry puts the result on the pasteboard, so the button can say so
        /// afterwards rather than looking like nothing happened.
        var copiesOnPress: Bool {
            switch self {
            case .unwritten, .unwritable: true
            default: false
            }
        }

    }

    private(set) var expanded = false
    private(set) var notice: Notice?
    private(set) var selection: Selection?
    /// Why a finished result was not written back, if it was not; the expanded view then offers to
    /// copy it instead of pretending the other app took it.
    private(set) var writebackRefusal: Notice?
    /// Set by the translate-and-replace shortcut: write back once the translation succeeds.
    private(set) var autoReplace = false
    /// The in-flight request will write back on success; labels the processing bar.
    private(set) var replacing = false
    /// Bumped each time the source bar's field should take the keyboard.
    private(set) var focusRequest = 0
    /// The screen region's screenshot fills the panel's width, with the source hidden (BDR-0019).
    private(set) var screenshotZoomed = false
    let model: TextProcessingModel
    var read: @MainActor (@escaping @MainActor (Result<Selection, SelectionError>) -> Void) -> Void
    var write: @MainActor (Selection, String) async -> ReplaceOutcome = SelectionBridge.replace
    /// The screen region seams; injectable so a test never touches the screen or Vision.
    var screenAccess: @MainActor () -> Bool = ScreenRegion.hasAccess
    var captureRegion: @MainActor () async throws -> Data? = { try await ScreenRegion.capture() }
    var recognize: @MainActor (Data) async -> String = { await ScreenRegion.recognize($0) }
    /// Copies a result; injectable so a test does not touch the user's real pasteboard.
    var copy: @MainActor (String) -> Void = { Clipboard.copy($0) }
    var openSettings: () -> Void = {}
    /// Opens the settings page on the prompt editor for the operation whose result failed to parse.
    var openPromptSettings: (Operation) -> Void = { _ in }
    var openNotebook: () -> Void = {}
    /// The notebook collect action; nil when the panel is built without one, which the tests do.
    var collection: CollectionAction?
    /// The result's selection toolbar and lookup card; Esc closes it before the panel.
    let lookups: LookupPresenter

    /// Internal read for tests that drive the real window (resign key, drag).
    private(set) var panel: FloatingPanel?
    /// Builds the panel window. A test replaces this with a panel that never goes on screen, so
    /// asserting controller state cannot race the real window's key changes.
    var makeWindow: (PanelRootView) -> FloatingPanel = { FloatingPanel(rootView: $0) }
    /// Guards against a superseded request acting on a newer result.
    private var requestID = 0
    /// Operation whose selection read is still outstanding.
    private var readingID: Int?
    /// Operation whose read ran past the budget and opened the empty editor.
    private var timedOutID: Int?

    private let defaults: UserDefaults

    init(
        model: TextProcessingModel, defaults: UserDefaults = .standard,
        lookups: LookupPresenter = LookupPresenter(store: LookupStore())
    ) {
        self.model = model
        self.defaults = defaults
        self.lookups = lookups
        // Selection bounds cost an extra AX call, so they are read only when placement uses them.
        read = { completion in
            SelectionBridge.read(
                bounds: SettingsStore.panelPosition(in: defaults) == .followSelection,
                wholeFieldText: SettingsStore.usesWholeFieldText(in: defaults),
                completion: completion)
        }
    }

    /// Invalidates the previous operation, then captures the selection before showing anything.
    /// A read that lands after a newer request or close is ignored.
    func processSelection(_ operation: Operation = .translate, replace: Bool = false) {
        requestID += 1
        let id = requestID
        readingID = id
        model.cancel()
        read { [weak self] in self?.accept($0, id: id, operation: operation, replace: replace) }
        Task { [weak self] in
            try? await Task.sleep(for: SelectionBridge.budget)
            self?.readTimedOut(id: id, operation: operation, replace: replace)
        }
    }

    /// Shows the same compact notice a failed read shows when the budget runs out, but leaves the
    /// read running: a browser or Electron app builds its accessibility tree on request, so the
    /// slow answer is usually the right one and still replaces this notice.
    private func readTimedOut(id: Int, operation: Operation, replace: Bool) {
        guard id == requestID, readingID == id else { return }
        timedOutID = id
        model.sourceImage = nil
        model.operation = operation
        autoReplace = replace
        // The previous text is not what the user selected now, so it must not sit beside this notice.
        showManualInput()
        show()
    }

    /// Translates the text in a rectangle the user draws on screen (BDR-0019). The panel closes first,
    /// so it is not in the picture; Esc in the capture leaves nothing on screen.
    func processRegion() {
        close()
        selection = nil
        writebackRefusal = nil
        autoReplace = false
        model.operation = .translate
        guard screenAccess() else {
            model.reset()
            model.input = ""
            model.sourceImage = nil
            notice = .screenPermission
            show()
            return
        }
        requestID += 1
        let id = requestID
        Task { [weak self] in
            guard let self else { return }
            let image: Data?
            do {
                guard let captured = try await captureRegion() else { return }
                image = captured
            } catch {
                image = nil
            }
            let text = if let image { await recognize(image) } else { "" }
            guard id == requestID else { return }
            let kept = image.map { ScreenRegion.keptCopy(of: $0) }
            if text.isEmpty {
                showManualInput()
                model.sourceImage = kept
            } else {
                model.input = text
                model.sourceImage = kept
                // The result opens on the screenshot the way the settings ask; a click still toggles it.
                screenshotZoomed = SettingsStore.screenshotDisplay(in: defaults) == .enlarged
                processCurrentText()
            }
            show()
        }
    }

    /// Nothing could be read, so the source bar itself becomes the input, with the reason as its
    /// placeholder: no notice, no empty panel (BDR-0018).
    private func showManualInput() {
        model.reset()
        model.input = ""
        notice = .unreadable
        expanded = false
        focusRequest += 1
    }

    /// Zooms the screenshot in or out; from the compact bar it opens the panel already zoomed.
    func toggleScreenshotZoom() {
        guard expanded else {
            if notice == .translating { notice = nil }
            expanded = true
            screenshotZoomed = true
            return
        }
        screenshotZoomed.toggle()
    }

    /// Esc in the compact bar first ends the edit; a second Esc, or an empty bar, closes.
    var cancelEndsEditing: Bool { !expanded && !model.input.isEmpty }

    private func accept(
        _ result: Result<Selection, SelectionError>, id: Int, operation: Operation, replace: Bool
    ) {
        guard id == requestID, readingID == id else { return }
        readingID = nil
        // The timeout emptied the editor, so any text in it now is the user's and a late read must
        // not overwrite it.
        if timedOutID == id, !model.input.isEmpty { return }
        model.sourceImage = nil
        model.operation = operation
        autoReplace = replace
        selection = nil
        writebackRefusal = nil
        switch result {
        case .success(let selection):
            self.selection = selection
            // Edge whitespace is layout in the other app, not text to translate; a write-back puts it back.
            model.input = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
            processCurrentText()
        case .failure(.permission):
            model.input = ""
            if expanded { model.fail(Notice.permission.message) }
            notice = .permission
        case .failure(.unreadable), .failure(.secure):
            showManualInput()
        }
        show()
    }

    /// Starts the current operation; the panel expands on the stream's first visible piece, so the
    /// arrival can be watched, and the result itself still only appears once it validated.
    func processCurrentText() {
        // The injected store, not `.standard`: a test must not inherit the developer's settings. The
        // target follows the mapping unless the user pinned one, so the panel and the window agree.
        let language = SettingsStore.resolvedTarget(for: model.input, in: defaults)
        requestID += 1
        let id = requestID
        if expanded { notice = nil }
        let task = model.process(to: language) { [weak self] in
            self?.expandOnFirstPartial(id: id)
        }
        // Auto write-back is one-shot: only the first request after a replace trigger, and only with a selection.
        let auto = autoReplace && selection != nil
        autoReplace = false
        replacing = auto
        if auto, let task {
            Task {
                await task.value
                guard id == requestID, case .success(let text) = model.state else {
                    return
                }
                let outcome = await performReplace(text)
                if !expanded, let refusal = Self.refusal(outcome) { notice = refusal }
            }
        }
        guard !expanded else { return }
        switch model.state {
        case .missingConfig: notice = .missingConfig
        case .idle: notice = .unreadable
        default: notice = .translating
        }
        guard let task else { return }
        Task {
            await task.value
            guard id == requestID, !expanded, notice == .translating else { return }
            switch model.state {
            case .success: if !auto { expanded = true }
            case .failure(let message, let kind): notice = .failure(message, kind: kind)
            default: break
            }
        }
    }

    /// Expands on the stream's first visible piece. A request superseded after this one started
    /// never expands: the piece belongs to whichever request is the newest one.
    private func expandOnFirstPartial(id: Int) {
        guard id == requestID, !expanded, model.isReceiving else { return }
        notice = nil
        expanded = true
    }

    /// Stops the in-flight request without closing; its late result is ignored and never written.
    /// Before expansion, reprocessing keeps the stopped request's write-back intent.
    func stop() {
        requestID += 1
        if !expanded { autoReplace = replacing }
        model.cancel()
        notice = .cancelled
    }

    /// The operation whose prompt editor a contract failure opens; nil for every other notice, so
    /// the panel view can route Prompt Settings to the editor that actually failed.
    func promptSettingsOperation(for notice: Notice) -> Operation? {
        guard case .failure(_, let kind) = notice, kind == .contract else {
            return nil
        }
        return model.operation
    }

    /// Status shown inside the expanded content, derived from the latest request outcome.
    var inlineNotice: Notice? {
        switch model.state {
        case .failure(let message, let kind):
            if notice == .permission || notice == .unreadable { return notice }
            return .failure(message, kind: kind)
        case .missingConfig: return .missingConfig
        case .success: return writebackRefusal
        case .idle: return notice == .cancelled ? .cancelled : nil
        case .loading:
            // While the stream runs, a press on a result action is answered with the reason it
            // must wait (BDR-0017 §1).
            return notice == .receiving ? .receiving : nil
        }
    }

    /// What the result text is, for a lookup in it; nil until there is a finished result.
    var lookupOrigin: LookupOrigin? {
        guard case .success = model.state, let languages = model.languages else { return nil }
        return .result(
            of: model.operation, languages: languages,
            mapping: SettingsStore.targetMapping(in: defaults))
    }

    /// Copies the result and closes the panel: copying is a finished interaction, like a replace.
    func copyResult() {
        guard case .success(let text) = model.state else { return }
        copy(text)
        close()
    }

    /// Writes `text` back once; the source is consumed on success so it is never reused.
    func replace(with text: String) {
        Task { [weak self] in await self?.performReplace(text) }
    }

    /// `text` wrapped in the leading and trailing whitespace of `original`, so replacing an indented
    /// line or one that ends in a newline keeps the surrounding layout.
    static func keepingEdges(of original: String, around text: String) -> String {
        let leading = original.prefix(while: \.isWhitespace)
        let trailing = original.reversed().prefix(while: \.isWhitespace).reversed()
        return leading + text.trimmingCharacters(in: .whitespacesAndNewlines) + String(trailing)
    }

    /// A paste lands asynchronously — the app takes the keystroke and applies it later — so the
    /// outcome decides what the user sees rather than the call itself.
    @discardableResult
    private func performReplace(_ text: String) async -> ReplaceOutcome {
        guard let selection else {
            // A write with nothing selected is a miss; the panel stays with the result to copy.
            writebackRefusal = .unwritten
            return .refused
        }
        // The panel owns the keyboard while it is up and a synthetic ⌘V follows the keyboard, so the
        // panel steps aside first; a miss comes back with the result to copy, a hit closes it.
        panel?.suspendsDismissal = true
        panel?.releaseKeyboard()
        let outcome = await write(selection, Self.keepingEdges(of: selection.text, around: text))
        panel?.suspendsDismissal = false
        if let refusal = Self.refusal(outcome) {
            writebackRefusal = refusal
            show()
            return outcome
        }
        // The other app took the result, so the panel's job is done and it closes.
        self.selection = nil
        writebackRefusal = nil
        close()
        return outcome
    }

    /// The notice for a write-back that did not happen, or nil when the other app took the result.
    private static func refusal(_ outcome: ReplaceOutcome) -> Notice? {
        switch outcome {
        case .pasted: nil
        case .refused: .unwritten
        case .unwritable: .unwritable
        }
    }

    func close() {
        invalidate()
        panel?.close()
    }

    /// The panel's own keys, run from its event monitor: copy the result, write it back, run again,
    /// or dismiss. Esc closes and cancels an in-flight request.
    func run(_ command: FloatingPanel.Command) {
        switch command {
        case .cancel:
            // Esc leaves the innermost layer first: an open toolbar or card, then the panel.
            if !lookups.close() { close() }
        case .copy:
            guard case .success = model.state else {
                explainReceiving()
                return
            }
            copyResult()
        case .retry:
            guard model.state != .loading, !model.input.isEmpty else { return }
            processCurrentText()
        case .replace:
            // A press before anything arrived restarts with the edited text; once text is arriving,
            // the press is told why it must wait.
            guard !model.isReceiving else {
                explainReceiving()
                return
            }
            // With nothing to write back to, ⌘↩ is the editor's submit, as on the main page (BDR-0018).
            if selection != nil, case .success(let text) = model.state {
                replace(with: text)
            } else if !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                processCurrentText()
            }
        }
    }

    /// While a result is still arriving, replace and copy give the visible reason they must wait
    /// instead of failing silently (BDR-0017 §1). The note shows in whatever view is up and clears
    /// as soon as the answer finishes or a newer request starts.
    private func explainReceiving() {
        guard model.isReceiving else { return }
        notice = .receiving
        expanded = true
    }

    /// Drops any outstanding read and returns to the compact, unexpanded state. Closing has to
    /// invalidate even when no panel was ever shown, so a slow answer cannot open one the user
    /// already dismissed.
    private func invalidate() {
        lookups.close(refocus: false)
        requestID += 1
        readingID = nil
        model.cancel()
        notice = nil
        expanded = false
        screenshotZoomed = false
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.show(anchor: anchor())
    }

    private func anchor() -> PanelPlacement.Anchor {
        switch SettingsStore.panelPosition(in: defaults) {
        case .fixed:
            return .topCenter(SettingsStore.panelFixedAnchor(in: defaults))
        case .followSelection:
            // AX coordinates are relative to the primary screen, which is always first.
            let bounds = selection?.bounds.flatMap { rect in
                NSScreen.screens.first.map {
                    PanelPlacement.appKitRect(fromAX: rect, primaryScreenHeight: $0.frame.height)
                }
            }
            return PanelPlacement.followAnchor(selectionBounds: bounds, mouse: NSEvent.mouseLocation)
        }
    }

    private func makePanel() -> FloatingPanel {
        let panel = makeWindow(PanelRootView(controller: self))
        panel.onClose = { [weak self] in self?.invalidate() }
        panel.onDrag = { [weak self] topCenter in
            guard let self, SettingsStore.panelPosition(in: defaults) == .fixed else { return }
            SettingsStore.setPanelFixedAnchor(topCenter, in: defaults)
        }
        panel.onCommand = { [weak self] command in self?.run(command) }
        panel.cancelEndsEditing = { [weak self] in self?.cancelEndsEditing ?? false }
        return panel
    }
}
