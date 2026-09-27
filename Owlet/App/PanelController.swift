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
    let model: TranslationModel
    var openSettings: () -> Void = {}
    var openManualInput: () -> Void = {}

    private var panel: FloatingPanel?

    init(model: TranslationModel) {
        self.model = model
    }

    /// Captures source and selection before showing anything, then translates.
    func trigger() {
        let result = SelectionBridge.read()
        model.cancel()
        expanded = false
        switch result {
        case .success(let selection):
            self.selection = selection
            model.input = selection.text
            translate()
        case .failure(.permission):
            notice = .permission
        case .failure(.unreadable), .failure(.secure):
            notice = .unreadable
        }
        show()
    }

    func translate() {
        let language =
            UserDefaults.standard.string(forKey: SettingsStore.targetLanguageKey)
            ?? SettingsStore.defaultTargetLanguage
        let task = model.translate(to: language)
        guard !expanded else { return }
        switch model.state {
        case .missingConfig: notice = .missingConfig
        case .idle: notice = .unreadable
        default: notice = .translating
        }
        guard let task else { return }
        Task {
            await task.value
            guard !expanded, notice == .translating else { return }
            switch model.state {
            case .success: expanded = true
            case .failure(let message): notice = .failure(message)
            default: break
            }
        }
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
            self?.model.cancel()
            self?.notice = nil
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
            TranslationView(model: controller.model, openSettings: controller.openSettings)
        } else {
            compact.padding().frame(minWidth: 260)
        }
    }

    @ViewBuilder private var compact: some View {
        HStack {
            switch controller.notice {
            case .translating, nil:
                ProgressView().controlSize(.small)
                Text("翻译中…")
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
