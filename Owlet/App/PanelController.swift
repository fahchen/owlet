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
    let model: TranslationModel
    var read: () -> Result<Selection, SelectionError> = SelectionBridge.read
    var write: (Selection, String) -> Bool = SelectionBridge.replace
    var openSettings: () -> Void = {}
    var openManualInput: () -> Void = {}

    private var panel: FloatingPanel?
    /// Guards against a superseded request acting on a newer result.
    private var requestID = 0

    init(model: TranslationModel) {
        self.model = model
    }

    /// Captures source and selection before showing anything, then translates.
    func trigger(_ operation: Operation = .translate, replace: Bool = false) {
        let result = read()
        model.cancel()
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
        let panel = FloatingPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
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

final class FloatingPanel: NSPanel {
    var onClose: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
    override func close() {
        onClose()
        super.close()
    }
}

private struct PanelView: View {
    let controller: PanelController

    var body: some View {
        if controller.expanded {
            TranslationView(
                model: controller.model, openSettings: controller.openSettings,
                replace: replaceAction,
                replaceMessage: controller.replaceMessage)
        } else {
            compact.padding().frame(minWidth: 260)
        }
    }

    private var replaceAction: ((String) -> Void)? {
        guard controller.selection != nil else { return nil }
        let controller = controller
        return { controller.replace(with: $0) }
    }

    @ViewBuilder private var compact: some View {
        HStack {
            switch controller.notice {
            case .translating, nil:
                ProgressView().controlSize(.small)
                Text("\(controller.model.operation.title)中…")
            case .permission:
                Text("需要辅助功能权限以读取选区。")
                Button("权限设置") {
                    if let url = SelectionBridge.permissionSettingsURL { NSWorkspace.shared.open(url) }
                }
            case .unreadable:
                Text("无法读取选中文字。")
                Button("手动输入") { manualInput() }
            case .missingConfig:
                Text("模型服务未配置。")
                Button("服务配置") { settings() }
            case .failure(let message):
                Text(message)
                Button("服务设置") { settings() }
                Button("重试") { controller.translate() }
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
