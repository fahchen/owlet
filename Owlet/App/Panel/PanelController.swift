import AppKit
import SwiftUI

/// Floating panel for shortcut-triggered translation: a compact notice until the first
/// success, then the full translation view, which stays expanded on later errors.
@MainActor @Observable
final class PanelController {
    enum Notice: Equatable {
        case translating
        case permission
        case unreadable
        case missingConfig
        case failure(String)
        /// The result could not be written back; the result stays copyable.
        case unwritten
        /// The selection cannot hold text, so the result was never typed anywhere.
        case unwritable
        case cancelled

        var message: String {
            switch self {
            case .translating: ""
            case .permission: "需要选区读取权限"
            case .unreadable: "未能读取到文字"
            case .missingConfig: "模型服务未配置"
            case .failure(let message):
                if message == ModelError.format.message {
                    "返回格式错误，请检查提示词"
                } else if Self.isConnection(message) {
                    "连接失败，请检查模型服务"
                } else {
                    message
                }
            case .unwritten: "未能写回原应用"
            case .unwritable: "原选区不可编辑"
            case .cancelled: "已取消处理"
            }
        }

        /// Label of the single recovery entry shown beside the message.
        var actionTitle: String {
            switch self {
            case .translating: ""
            case .permission: "权限设置"
            case .unreadable: "手动输入"
            case .missingConfig: "配置服务"
            case .failure(let message): ModelError.isContractFailure(message) ? "提示词设置" : "服务设置"
            case .unwritten: "复制结果"
            case .unwritable: "复制结果"
            case .cancelled: "重新处理"
            }
        }

        /// Network, auth and HTTP failures read as a connection problem; `State.failure` keeps only the text.
        private static func isConnection(_ message: String) -> Bool {
            message == ModelError.unauthorized.message
                || message.hasPrefix(ModelError.network("").message)
                || message.hasPrefix("服务返回 HTTP")
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
    let model: TextProcessingModel
    var read: @MainActor (@escaping @MainActor (Result<Selection, SelectionError>) -> Void) -> Void
    var write: @MainActor (Selection, String) async -> ReplaceOutcome = SelectionBridge.replace
    /// Copies a result; injectable so a test does not touch the user's real pasteboard.
    var copy: @MainActor (String) -> Void = { Clipboard.copy($0) }
    var openSettings: () -> Void = {}
    /// Opens the settings page on the prompt editor for the operation whose result failed to parse.
    var openPromptSettings: (Operation) -> Void = { _ in }
    var openManualInput: () -> Void = {}
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
                bounds: SettingsStore.panelPosition(in: defaults) == .followSelection, completion: completion)
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
        model.operation = operation
        autoReplace = replace
        // The previous text is not what the user selected now, so it must not sit beside this notice.
        model.input = ""
        if expanded { model.fail(Notice.unreadable.message) }
        notice = .unreadable
        show()
    }

    private func accept(
        _ result: Result<Selection, SelectionError>, id: Int, operation: Operation, replace: Bool
    ) {
        guard id == requestID, readingID == id else { return }
        readingID = nil
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
            model.input = ""
            if expanded { model.fail(Notice.unreadable.message) }
            notice = .unreadable
        }
        show()
    }

    func processCurrentText() {
        // The injected store, not `.standard`: a test must not inherit the developer's settings. The
        // target follows the mapping unless the user pinned one, so the panel and the window agree.
        let language = SettingsStore.resolvedTarget(for: model.input, in: defaults)
        requestID += 1
        let id = requestID
        if expanded { notice = nil }
        let task = model.process(to: language)
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
            case .failure(let message): notice = .failure(message)
            default: break
            }
        }
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
    /// the panel view can route 提示词设置 to the editor that actually failed.
    func promptSettingsOperation(for notice: Notice) -> Operation? {
        guard case .failure(let message) = notice, ModelError.isContractFailure(message) else {
            return nil
        }
        return model.operation
    }

    /// Status shown inside the expanded content, derived from the latest request outcome.
    var inlineNotice: Notice? {
        switch model.state {
        case .failure(let message):
            if notice == .permission || notice == .unreadable { return notice }
            return .failure(message)
        case .missingConfig: return .missingConfig
        case .success: return writebackRefusal
        case .idle: return notice == .cancelled ? .cancelled : nil
        case .loading: return nil
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
            copyResult()
        case .retry:
            guard model.state != .loading, !model.input.isEmpty else { return }
            processCurrentText()
        case .replace:
            guard case .success(let text) = model.state, selection != nil else { return }
            replace(with: text)
        }
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
        return panel
    }
}
