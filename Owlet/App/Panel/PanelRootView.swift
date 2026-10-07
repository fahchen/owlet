import AppKit
import SwiftUI

struct PanelRootView: View {
    let controller: PanelController
    @Namespace private var panelTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if controller.expanded {
                expandedView
                    .matchedGeometryEffect(id: "panel", in: panelTransition, anchor: .top)
                    .transition(.opacity)
            } else {
                compact
                    .matchedGeometryEffect(id: "panel", in: panelTransition, anchor: .top)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.36, bounce: 0.12), value: controller.expanded)
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
            openSettings: settings,
            close: controller.close)
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
                stop: controller.stop, close: controller.close)
        case let notice?:
            CompactNoticeView(
                message: notice.message, summary: controller.model.input,
                retry: compactRetry, close: controller.close,
                symbol: notice == .missingConfig
                    ? "lock.trianglebadge.exclamationmark"
                    : statusRetries(notice) ? "network.slash" : "exclamationmark.triangle",
                actionTitle: statusRetries(notice) ? "重试" : notice.actionTitle,
                actionSymbol: statusRetries(notice) ? "arrow.clockwise" : "gearshape",
                recover: { recover(notice) },
                action: statusRetries(notice) ? compactRetry : nil)
        }
    }

    private func statusRetries(_ notice: PanelController.Notice) -> Bool {
        guard case .failure(let message) = notice else { return false }
        return !ModelError.isContractFailure(message)
    }

    private var compactRetry: (() -> Void)? {
        guard !controller.model.input.isEmpty else { return nil }
        return { controller.processCurrentText() }
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
