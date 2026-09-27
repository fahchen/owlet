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
        /// Direct replace refused because the selection changed; the result stays copyable.
        case stale
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
            case .stale: "原选区已变化，未替换"
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
            case .stale: "复制结果"
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
    /// Shown in the expanded view when a write-back was refused.
    private(set) var replaceMessage: String?
    /// Set by the translate-and-replace shortcut: write back once the translation succeeds.
    private(set) var autoReplace = false
    /// The in-flight request will write back on success; labels the processing bar.
    private(set) var replacing = false
    let model: TranslationModel
    var read: @MainActor (@escaping @MainActor (Result<Selection, SelectionError>) -> Void) -> Void
    var write: (Selection, String) -> Bool = SelectionBridge.replace
    var openSettings: () -> Void = {}
    var openManualInput: () -> Void = {}

    private var panel: FloatingPanel?
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
    /// A read that misses the budget, or lands after a newer trigger or close, is ignored.
    func trigger(_ operation: Operation = .translate, replace: Bool = false) {
        requestID += 1
        let id = requestID
        readingID = id
        model.cancel()
        read { [weak self] in self?.accept($0, id: id, operation: operation, replace: replace) }
        Task { [weak self] in
            try? await Task.sleep(for: SelectionBridge.budget)
            self?.accept(.failure(.unreadable), id: id, operation: operation, replace: replace)
        }
    }

    private func accept(
        _ result: Result<Selection, SelectionError>, id: Int, operation: Operation, replace: Bool
    ) {
        guard id == requestID, readingID == id else { return }
        readingID = nil
        model.operation = operation
        autoReplace = replace
        selection = nil
        replaceMessage = nil
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
        let language =
            UserDefaults.standard.string(forKey: SettingsStore.targetLanguageKey)
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
                replace(with: text)
                if selection != nil, !expanded { notice = .stale }
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
        case .success: return replaceMessage == nil ? nil : .stale
        case .idle: return notice == .cancelled ? .cancelled : nil
        case .loading: return nil
        }
    }

    /// Writes `text` back once; the source is consumed on success so it is never reused.
    func replace(with text: String) {
        guard let selection, write(selection, text) else {
            replaceMessage = "原选区已变化或无法确认，未替换。可复制结果。"
            return
        }
        self.selection = nil
        replaceMessage = nil
        close()
    }

    func close() {
        panel?.close()
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
        let panel = FloatingPanel(rootView: PanelView(controller: self))
        panel.onClose = { [weak self] in
            self?.requestID += 1
            self?.model.cancel()
            self?.notice = nil
            self?.expanded = false
        }
        panel.onDrag = { [weak self] topCenter in
            guard let self, SettingsStore.panelPosition(in: defaults) == .fixed else { return }
            SettingsStore.setPanelFixedAnchor(topCenter, in: defaults)
        }
        return panel
    }
}

/// Frameless, fully transparent panel whose only content is a native glass view, so the window
/// server draws just the rounded glass and its shadow. Closes (cancelling, like Esc) on losing key.
final class FloatingPanel: NSPanel, NSWindowDelegate {
    var onClose: () -> Void = {}
    /// User drag ended at this top-center point; the panel then stays anchored there.
    var onDrag: (NSPoint) -> Void = { _ in }
    private var anchor = PanelPlacement.Anchor.topCenter(nil)
    /// Set while the panel moves itself, so only user drags reach `onDrag`.
    private var placing = false
    private let host: NSHostingController<PanelView>
    private var sizeObservation: NSKeyValueObservation?
    private var closing = false

    init(rootView: PanelView) {
        host = NSHostingController(rootView: rootView)
        host.sizingOptions = .preferredContentSize
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        delegate = self
        let glass = NSGlassEffectView()
        glass.cornerRadius = 16
        glass.contentView = host.view
        contentView = glass
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
        if isVisible { close() }
    }
    override func close() {
        guard !closing else { return }
        closing = true
        defer { closing = false }
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
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        placing = true
        defer { placing = false }
        setFrame(PanelPlacement.frame(size: size, anchor: anchor, within: visible), display: true)
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
        case .stale:
            guard case .success(let text) = controller.model.state else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
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
