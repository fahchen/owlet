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
            case .failure(let message): message == ModelError.format.message ? "提示词设置" : "服务设置"
            case .unwritten: "复制结果"
            case .unwritable: "复制结果"
            case .cancelled: "重新处理"
            }
        }

        /// Network, auth and HTTP failures read as a connection problem; `State.failure` keeps only the text.
        private static func isConnection(_ message: String) -> Bool {
            message == ModelError.unauthorized.message
                || message.hasPrefix(ModelError.network("").message)
                || message.hasPrefix("Service returned HTTP")
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
    let model: TranslationModel
    var read: @MainActor (@escaping @MainActor (Result<Selection, SelectionError>) -> Void) -> Void
    var write: @MainActor (Selection, String) async -> ReplaceOutcome = SelectionBridge.replace
    var openSettings: () -> Void = {}
    var openManualInput: () -> Void = {}

    /// Internal read for tests that drive the real window (resign key, drag).
    private(set) var panel: FloatingPanel?
    /// Builds the panel window. A test replaces this with a panel that never goes on screen, so
    /// asserting controller state cannot race the real window's key changes.
    var makeWindow: (PanelView) -> FloatingPanel = { FloatingPanel(rootView: $0) }
    /// Guards against a superseded request acting on a newer result.
    private var requestID = 0
    /// Operation whose selection read is still outstanding.
    private var readingID: Int?

    private let defaults: UserDefaults

    init(model: TranslationModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        // Selection bounds cost an extra AX call, so they are read only when placement uses them.
        read = { completion in
            SelectionBridge.read(
                bounds: SettingsStore.panelPosition(in: defaults) == .followSelection, completion: completion)
        }
    }

    /// Invalidates the previous operation, then captures the selection before showing anything.
    /// A read that lands after a newer trigger or close is ignored.
    func trigger(_ operation: Operation = .translate, replace: Bool = false) {
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
            model.input = selection.text
            translate()
        case .failure(.permission):
            if expanded { model.fail(Notice.permission.message) }
            notice = .permission
        case .failure(.unreadable), .failure(.secure):
            if expanded { model.fail(Notice.unreadable.message) }
            notice = .unreadable
        }
        show()
    }

    func translate() {
        // The injected store, not `.standard`: a test must not inherit the developer's settings.
        let language =
            defaults.string(forKey: SettingsStore.targetLanguageKey)
            ?? SettingsStore.defaultTargetLanguage
        requestID += 1
        let id = requestID
        if expanded { notice = nil }
        let task = model.translate(to: language)
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

    /// Writes `text` back once; the source is consumed on success so it is never reused.
    func replace(with text: String) {
        Task { [weak self] in await self?.performReplace(text) }
    }

    /// A paste lands asynchronously — the app takes the keystroke and applies it later — so the
    /// outcome decides what the user sees rather than the call itself.
    @discardableResult
    private func performReplace(_ text: String) async -> ReplaceOutcome {
        guard let selection else {
            writebackRefusal = .unwritten
            return .refused
        }
        // The panel owns the keyboard while it is up and a synthetic ⌘V follows the keyboard, so the
        // panel steps aside first; it comes back if the text never changed, because a miss is exactly
        // when the user needs the result to copy.
        let wasVisible = panel?.isVisible == true
        panel?.suspendsDismissal = true
        panel?.releaseKeyboard()
        let outcome = await write(selection, text)
        panel?.suspendsDismissal = false
        guard let refusal = Self.refusal(outcome) else {
            self.selection = nil
            writebackRefusal = nil
            close()
            return outcome
        }
        writebackRefusal = refusal
        if wasVisible { show() }
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

    /// The panel's own keys, run from its event monitor: copy the result, write it back, or
    /// dismiss. Esc stops an in-flight request first, which is what the footer hint promises.
    func run(_ command: FloatingPanel.Command) {
        switch command {
        case .cancel:
            if model.state == .loading { stop() } else { close() }
        case .copy:
            guard case .success(let text) = model.state else { return }
            Clipboard.copy(text)
        case .replace:
            guard case .success(let text) = model.state, selection != nil else { return }
            replace(with: text)
        }
    }

    /// Drops any outstanding read and returns to the compact, unexpanded state. Closing has to
    /// invalidate even when no panel was ever shown, so a slow answer cannot open one the user
    /// already dismissed.
    private func invalidate() {
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
        let panel = makeWindow(PanelView(controller: self))
        panel.onClose = { [weak self] in self?.invalidate() }
        panel.onDrag = { [weak self] topCenter in
            guard let self, SettingsStore.panelPosition(in: defaults) == .fixed else { return }
            SettingsStore.setPanelFixedAnchor(topCenter, in: defaults)
        }
        panel.onCommand = { [weak self] command in self?.run(command) }
        return panel
    }
}

/// Frameless, fully transparent panel whose only content is a native glass view, so the window
/// server draws the glass alone. Closes (cancelling, like Esc) on losing key.
/// Not final: tests that only assert controller state substitute a panel that stays off screen.
class FloatingPanel: NSPanel, NSWindowDelegate {
    /// What the panel does with a key it claims. Owlet is an accessory app whose panel never
    /// activates it, so a SwiftUI key equivalent would have to travel through a menu bar that is
    /// never active: the panel reads the key event itself instead.
    enum Command {
        case replace
        case copy
        case cancel
    }

    var onClose: () -> Void = {}
    /// User drag ended at this top-center point; the panel then stays anchored there.
    var onDrag: (NSPoint) -> Void = { _ in }
    var onCommand: (Command) -> Void = { _ in }
    /// While a write-back is in flight the panel lets go of the keyboard without dismissing itself:
    /// the keystroke has to reach the app underneath, and the panel has to survive to report a miss.
    var suspendsDismissal = false
    private var anchor = PanelPlacement.Anchor.topCenter(nil)
    /// Set while the panel moves itself, so only user drags reach `onDrag`.
    private var placing = false
    private let host: NSHostingController<PanelView>
    private var sizeObservation: NSKeyValueObservation?
    private var closing = false
    /// The rounded shape the window presents to the window server, so the shadow follows the glass
    /// instead of the rectangle around it.
    private let shape = NSView()
    /// Live while the panel is up; removed on close so the panel holds nothing after it goes.
    private var keys: Any?

    init(rootView: PanelView) {
        host = NSHostingController(rootView: rootView)
        host.sizingOptions = .preferredContentSize
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        // The glass needs a shadow to read against a light background, and a borderless window takes
        // its shape — and so its shadow — from its content layer.
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        delegate = self
        // The glass keeps its own default corner radius and style. It is wrapped in a container
        // masked to that same shape, because a square layer is what used to cast a square shadow
        // around rounded glass: the rounded mask is what the window server now follows.
        let glass = NSGlassEffectView()
        glass.contentView = host.view
        glass.frame = shape.bounds
        glass.autoresizingMask = [.width, .height]
        shape.addSubview(glass)
        shape.wantsLayer = true
        shape.layer?.cornerRadius = glass.cornerRadius
        shape.layer?.masksToBounds = true
        contentView = shape
        sizeObservation = host.observe(\.preferredContentSize) { [weak self] host, _ in
            MainActor.assumeIsolated { self?.fit(host.preferredContentSize) }
        }
    }

    /// Shows at `anchor`, kept inside the visible frame of the screen containing it.
    func show(anchor: PanelPlacement.Anchor) {
        self.anchor = anchor
        place(size: host.preferredContentSize)
        orderFrontRegardless()
        makeKey()
        // Becoming key hands the responder to SwiftUI's key view proxy, which focuses the first
        // control; the panel has nothing to type into on open, so it starts with nothing focused.
        // A click or Tab still reaches every control.
        makeFirstResponder(nil)
        if keys == nil { keys = watchKeys() }
    }

    /// Hands the keyboard to whatever is underneath without dismissing the panel: a synthetic ⌘V
    /// follows the keyboard, so the panel cannot still own it when the keystroke goes out.
    func releaseKeyboard() {
        orderOut(nil)
    }

    /// ⌘↩ replaces, ⌘⇧C copies, Esc dismisses; every other key stays with the panel's controls.
    /// Return and keypad Enter both count, so a full keyboard reaches replace either way.
    static func command(for event: NSEvent) -> Command? {
        switch (event.keyCode, event.modifierFlags.intersection(.deviceIndependentFlagsMask)) {
        case (36, .command), (76, .command): .replace
        case (8, [.command, .shift]): .copy
        case (53, []): .cancel
        default: nil
        }
    }

    /// Consumes the keys this panel claims, so they never reach a text field behind them.
    private func watchKeys() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self, let command = Self.command(for: event) else {
                return event
            }
            onCommand(command)
            return nil
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !placing else { return }
        let topCenter = NSPoint(x: frame.midX, y: frame.maxY)
        anchor = .topCenter(topCenter)
        onDrag(topCenter)
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
    override func resignKey() {
        super.resignKey()
        if isVisible, !suspendsDismissal { close() }
    }
    override func close() {
        guard !closing else { return }
        closing = true
        defer { closing = false }
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        onClose()
        super.close()
    }

    /// Content-driven resizes re-place from the anchor, so the compact bar expands downward
    /// (or, below a selection near the screen bottom, flips above it).
    private func fit(_ size: NSSize) {
        guard size != frame.size else { return }
        place(size: size)
    }

    private func place(size: NSSize) {
        let screen = anchor.reference.flatMap { point in
            NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
        }
        placing = true
        defer { placing = false }
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else {
            // No screen to place on: keep the current top-center so the panel still expands downward.
            let top = NSPoint(x: frame.midX, y: frame.maxY)
            setFrame(
                NSRect(x: top.x - size.width / 2, y: top.y - size.height, width: size.width, height: size.height),
                display: true)
            invalidateShadow()
            return
        }
        setFrame(PanelPlacement.frame(size: size, anchor: anchor, within: visible), display: true)
        // The shape changed with the size, so the shadow has to be recomputed from it.
        invalidateShadow()
    }
}

struct PanelView: View {
    let controller: PanelController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if controller.expanded {
                expandedView.transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                compact.transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: controller.expanded)
    }

    private var expandedView: some View {
        ExpandedPanel(
            model: controller.model,
            replace: replaceAction,
            notice: controller.inlineNotice,
            recover: recover,
            retry: controller.translate,
            cancel: controller.stop,
            openSettings: settings)
    }

    private var replaceAction: ((String) -> Void)? {
        guard controller.selection != nil else { return nil }
        let controller = controller
        return { controller.replace(with: $0) }
    }

    @ViewBuilder private var compact: some View {
        switch controller.notice {
        case .translating, nil:
            ProcessingStrip(
                summary: controller.model.input,
                status: controller.replacing ? "翻译并替换…" : "\(controller.model.operation.title)中…",
                stop: controller.stop)
        case let notice?:
            NoticeStrip(message: notice.message) {
                Button(notice.actionTitle) { recover(notice) }
                if case .failure = notice {
                    Button("重试", systemImage: "arrow.clockwise") { controller.translate() }
                        .labelStyle(.iconOnly)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("重试")
                }
            }
        }
    }

    /// Runs the recovery entry of a compact or in-content notice.
    private func recover(_ notice: PanelController.Notice) {
        switch notice {
        case .permission:
            if let url = SelectionBridge.permissionSettingsURL { NSWorkspace.shared.open(url) }
        case .unreadable: manualInput()
        case .missingConfig, .failure: settings()
        case .unwritten, .unwritable:
            guard case .success(let text) = controller.model.state else { return }
            Clipboard.copy(text)
        case .cancelled: controller.translate()
        case .translating: break
        }
    }

    private func manualInput() {
        controller.close()
        controller.openManualInput()
    }

    private func settings() {
        controller.close()
        controller.openSettings()
    }
}

/// Compact processing bar: one-line summary of the selected text, spinner, status, stop.
struct ProcessingStrip: View {
    let summary: String
    let status: String
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(summary.replacing(/\s+/, with: " "))
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(summary)
            ProgressView().controlSize(.small)
            Text(status)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize()
            GlassEffectContainer {
                Button("停止", systemImage: "stop.fill", action: stop)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .help("停止处理")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(width: 430)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(status) \(summary)")
    }
}

/// Compact notice bar used before the first result: message left, glass recovery buttons right.
struct NoticeStrip<Actions: View>: View {
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            GlassEffectContainer {
                HStack(spacing: 6) { actions }.buttonStyle(.glass)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .frame(width: 430)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .accessibilityElement(children: .contain)
    }
}
