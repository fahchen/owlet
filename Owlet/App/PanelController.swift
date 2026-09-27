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
    var read: @MainActor (@escaping @MainActor (Result<Selection, SelectionError>) -> Void) -> Void =
        SelectionBridge.read
    var write: (Selection, String) -> Bool = SelectionBridge.replace
    var openSettings: () -> Void = {}
    var openManualInput: () -> Void = {}

    private var panel: FloatingPanel?
    /// Guards against a superseded request acting on a newer result.
    private var requestID = 0
    /// Operation whose selection read is still outstanding.
    private var readingID: Int?

    init(model: TranslationModel) {
        self.model = model
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
            if expanded { model.fail("需要辅助功能权限以读取选区。") } else { notice = .permission }
        case .failure(.unreadable), .failure(.secure):
            if expanded { model.fail("无法读取选中文字。") } else { notice = .unreadable }
        }
        show()
    }

    func translate() {
        let language =
            UserDefaults.standard.string(forKey: SettingsStore.targetLanguageKey)
            ?? SettingsStore.defaultTargetLanguage
        requestID += 1
        let id = requestID
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
                if selection != nil { expanded = true }
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
        panel.setFrameTopLeftPoint(NSEvent.mouseLocation)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel()
        let host = NSHostingController(rootView: PanelView(controller: self))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        panel.onClose = { [weak self] in
            self?.requestID += 1
            self?.model.cancel()
            self?.notice = nil
            self?.expanded = false
        }
        return panel
    }
}

/// Frameless glass panel: no title bar or window buttons; the SwiftUI content draws the
/// rounded container, the window server draws the shadow from its alpha.
final class FloatingPanel: NSPanel {
    var onClose: () -> Void = {}

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
    override func close() {
        onClose()
        super.close()
    }

    /// Content-driven resizes keep the top edge fixed, so the compact bar expands downward.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if isVisible, rect.origin == frame.origin, rect.size != frame.size {
            rect.origin.y = frame.maxY - rect.height
        }
        super.setFrame(rect, display: flag)
        invalidateShadow()
    }
}

/// Owlet Rose Glass tokens (spec/DESIGN.md), OKLCH converted to sRGB.
enum RoseGlass {
    /// oklch(47% .17 350)
    static let accent = Color(red: 0.605, green: 0.127, blue: 0.408)
    /// oklch(27% .012 350)
    static let ink = Color(red: 0.170, green: 0.142, blue: 0.154)
    /// oklch(49% .012 350)
    static let muted = Color(red: 0.400, green: 0.368, blue: 0.381)
    /// oklch(99% .003 350)
    static let paper = Color(red: 0.994, green: 0.984, blue: 0.988)
    static let compactRadius: CGFloat = 16
    static let expandedRadius: CGFloat = 18
}

struct PanelView: View {
    let controller: PanelController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let radius = controller.expanded ? RoseGlass.expandedRadius : RoseGlass.compactRadius
        Group {
            if controller.expanded {
                expandedView.transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                compact.transition(.opacity)
            }
        }
        .glassEffect(
            .regular.tint(RoseGlass.paper.opacity(0.35)),
            in: .rect(cornerRadius: radius, style: .continuous)
        )
        .overlay {
            if isProcessing { ProcessingEdge(cornerRadius: radius) }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: controller.expanded)
    }

    private var isProcessing: Bool {
        guard !controller.expanded else { return false }
        return controller.notice == .translating || controller.notice == nil
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            PanelHeader(operation: Bindable(controller.model).operation, openSettings: settings)
            Divider().opacity(0.6)
            TranslationView(
                model: controller.model, openSettings: controller.openSettings,
                replace: replaceAction,
                replaceMessage: controller.replaceMessage)
        }
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
                stop: controller.close)
        case .permission:
            NoticeStrip(message: "需要辅助功能权限以读取选区。") {
                InlineAction("权限设置") {
                    if let url = SelectionBridge.permissionSettingsURL { NSWorkspace.shared.open(url) }
                }
            }
        case .unreadable:
            NoticeStrip(message: "无法读取选中文字。") { InlineAction("手动输入", action: manualInput) }
        case .missingConfig:
            NoticeStrip(message: "模型服务未配置。") { InlineAction("服务配置", action: settings) }
        case .failure(let message):
            NoticeStrip(message: message) {
                InlineAction("服务设置", action: settings)
                InlineAction("重试") { controller.translate() }
            }
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

/// Replaces the title bar the frameless panel lacks: logo, operation menu, settings.
struct PanelHeader: View {
    @Binding var operation: Operation
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image("OwletMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(RoseGlass.muted)
                    .accessibilityLabel("Owlet")
                Picker("快捷操作", selection: $operation) {
                    ForEach(Operation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .fixedSize()
                .font(.system(size: 12, weight: .semibold))
            }
            Spacer(minLength: 0)
            Button("打开设置", systemImage: "slider.horizontal.3", action: openSettings)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(RoseGlass.muted)
                .help("设置")
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}

/// Compact processing bar: one-line summary of the selected text, status, stop.
struct ProcessingStrip: View {
    let summary: String
    let status: String
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(summary.replacing(/\s+/, with: " "))
                .font(.system(size: 12))
                .foregroundStyle(RoseGlass.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(summary)
            Text(status)
                .font(.system(size: 10))
                .foregroundStyle(RoseGlass.muted)
                .fixedSize()
            Button("停止", systemImage: "stop.fill", action: stop)
                .labelStyle(.iconOnly)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(RoseGlass.muted)
                .frame(width: 22, height: 22)
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(Circle())
                .help("停止处理")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(width: 430)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(status) \(summary)")
    }
}

/// Compact notice bar used before the first result: message plus inline recovery actions.
struct NoticeStrip<Actions: View>: View {
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(RoseGlass.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 430)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .accessibilityElement(children: .contain)
    }
}

private struct InlineAction: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).underline().font(.system(size: 11)).foregroundStyle(RoseGlass.accent)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// Breathing rose edge while processing; a static edge under Reduce Motion.
private struct ProcessingEdge: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    /// oklch(91% .008 265) → oklch(69% .15 350) → oklch(94% .008 265)
    private static let gradient = LinearGradient(
        colors: [
            Color(red: 0.873, green: 0.883, blue: 0.905),
            Color(red: 0.872, green: 0.442, blue: 0.660),
            Color(red: 0.911, green: 0.922, blue: 0.944),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    /// oklch(67% .12 350 / .7)
    private static let still = Color(red: 0.799, green: 0.458, blue: 0.626).opacity(0.7)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if reduceMotion {
                shape.strokeBorder(Self.still, lineWidth: 1.7)
            } else {
                shape.strokeBorder(Self.gradient, lineWidth: 1.7)
                    .opacity(lit ? 1 : 0.22)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { lit = true }
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
