import AppKit
import SwiftUI

struct PanelRootView: View {
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
            copy: { _ in controller.copyResult() },
            collection: controller.collection,
            openNotebook: controller.openNotebook,
            notice: controller.inlineNotice,
            recover: recover,
            retry: controller.processCurrentText,
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
            CompactProcessingView(
                summary: controller.model.input,
                status: controller.replacing ? "翻译并替换…" : "\(controller.model.operation.title)中…",
                stop: controller.stop)
        case let notice?:
            CompactNoticeView(message: notice.message) {
                Button(notice.actionTitle) { recover(notice) }
                if case .failure = notice {
                    Button("重试", systemImage: "arrow.clockwise") { controller.processCurrentText() }
                        .labelStyle(.iconOnly)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("重试")
                }
            }
        }
    }

    /// Runs the recovery entry of a compact or in-content notice.
    private func recover(_ notice: PanelController.Notice) {
        if let operation = controller.promptSettingsOperation(for: notice) {
            promptSettings(operation)
            return
        }
        switch notice {
        case .permission:
            if let url = SelectionBridge.permissionSettingsURL { NSWorkspace.shared.open(url) }
        case .unreadable: manualInput()
        case .missingConfig, .failure: settings()
        case .unwritten, .unwritable:
            controller.copyResult()
        case .cancelled: controller.processCurrentText()
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

    private func promptSettings(_ operation: Operation) {
        controller.close()
        controller.openPromptSettings(operation)
    }
}
