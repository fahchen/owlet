import AppKit
import SwiftUI

struct PanelRootView: View {
    let controller: PanelController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsStore.panelGlassEffectKey) private var glassEffect = PanelGlassEffect.contrast

    /// The expanded panel's own height, which the surface grows to. The surface needs it as an
    /// explicit, animated height: a surface that only hugged the panel would snap to its full size.
    @State private var expandedHeight: CGFloat = 0
    /// The compact bar's height: one line at rest, taller while a pasted text is being edited.
    @State private var barHeight = PanelMetrics.sourceBarHeight
    @Namespace private var screenshotSpace

    /// One glass surface carries the source bar and then the expanded panel, so expanding grows
    /// it in place; nil while only a notice capsule shows.
    private var surfaceHeight: CGFloat? {
        if controller.expanded { return max(expandedHeight, PanelMetrics.sourceBarHeight) }
        return showsBar ? barHeight : nil
    }

    /// The bar is the source, so it stays even when emptied; only a missing permission has no
    /// source to show.
    private var showsBar: Bool {
        switch controller.notice {
        case .permission, .screenPermission: !controller.model.input.isEmpty
        default: true
        }
    }

    var body: some View {
        let spring: Animation? = reduceMotion ? nil : .spring(duration: 0.36, bounce: 0.12)
        VStack(spacing: 12) {
            if let surfaceHeight {
                // Top-aligned: the surface keeps its top edge and grows down; only its content
                // cross-fades from the bar to the panel.
                ZStack(alignment: .top) {
                    if controller.expanded {
                        expandedView
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { expandedHeight = $0 }
                            .transition(.opacity)
                    } else {
                        sourceBar.background(PanelGlassEffect.compactTint)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { barHeight = $0 }
                            .transition(.opacity)
                    }
                }
                .panelSurface(
                    glassEffect.glass,
                    height: surfaceHeight)
            }
            if !controller.expanded {
                compact.transition(.opacity)
            }
        }
        .frame(width: PanelMetrics.width)
        .animation(spring, value: controller.expanded)
        .animation(spring, value: surfaceHeight)
        .padding(PanelMetrics.shadowMargin)
        // Pinned to the window's top. Without a zero minimum the frame never gets shorter than its
        // content, so for the frame before the window grows the taller content is centered in the
        // old window and the panel drops, then springs back up.
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
    }

    /// The source bar for the current compact state, drawn on the shared surface.
    private var sourceBar: some View {
        let notice = controller.notice
        let processing = notice == nil || notice == .translating || notice == .unreadable
        let screenshot = controller.model.sourceThumbnail
        let controller = controller
        var recapture: (() -> Void)?
        if notice == .unreadable, screenshot != nil { recapture = { controller.processRegion() } }
        return PanelSourceBar(
            summary: controller.model.input, text: Bindable(controller.model).input,
            placeholder: placeholder, focusRequest: controller.focusRequest,
            submitTitle: controller.model.operation.name,
            screenshot: screenshot, screenshotSpace: screenshotSpace,
            toggleScreenshotZoom: controller.toggleScreenshotZoom,
            recapture: recapture,
            retry: processing ? nil : compactRetry, close: controller.close, drawsGlass: false)
    }

    /// Why the bar is empty, when nothing could be read.
    private var placeholder: String {
        guard controller.notice == .unreadable else { return "" }
        return controller.model.sourceImage == nil
            ? L10n.shared.string("No selected text was read. Type or paste it, then press ⌘↩")
            : L10n.shared.string("No text was found in the screenshot. Type what it says, then press ⌘↩")
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
            close: controller.close,
            lookupOrigin: controller.lookupOrigin,
            screenshotSpace: screenshotSpace,
            screenshotZoomed: controller.screenshotZoomed,
            toggleScreenshotZoom: controller.toggleScreenshotZoom
        )
        .environment(\.lookups, controller.lookups)
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
                status: controller.replacing
                    ? L10n.shared.string("Translating and replacing…")
                    : L10n.shared.string(controller.model.operation.progress.key),
                symbol: controller.model.operation.symbol, stop: controller.stop, close: controller.close,
                showsBar: false)
        case .unreadable:
            // The bar's placeholder says why it is empty; a second line would only repeat it.
            EmptyView()
        case .receiving:
            // A press asked why replace waits. The explanation runs in the compact bar, and the
            // one entry it offers stops the arrival.
            CompactNoticeView(
                message: controller.notice?.message ?? "", summary: controller.model.input,
                retry: compactRetry, close: controller.close,
                symbol: "arrow.down", actionTitle: L10n.shared.string("Cancel"),
                actionSymbol: "xmark", recover: {}, action: controller.stop,
                isError: false, showsBar: false)
        case let notice?:
            CompactNoticeView(
                message: notice.message, summary: controller.model.input,
                retry: compactRetry, close: controller.close,
                symbol: notice == .missingConfig
                    ? "lock.trianglebadge.exclamationmark"
                    : statusRetries(notice) ? "network.slash" : "exclamationmark.triangle",
                actionTitle: statusRetries(notice) ? "Retry" : notice.actionTitle,
                actionSymbol: statusRetries(notice) ? "arrow.clockwise" : "gearshape",
                recover: { recover(notice) },
                action: statusRetries(notice) ? compactRetry : nil,
                isError: notice != .cancelled, copiesOnPress: notice.copiesOnPress, showsBar: false)
        }
    }

    private func statusRetries(_ notice: PanelController.Notice) -> Bool {
        guard case .failure(_, let kind) = notice else { return false }
        return kind != .contract
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
        case .screenPermission:
            if let url = ScreenRegion.permissionSettingsURL { NSWorkspace.shared.open(url) }
        case .missingConfig, .failure: settings()
        case .unwritten, .unwritable:
            controller.copyResult()
        case .cancelled: controller.processCurrentText()
        case .translating, .receiving, .unreadable: break
        }
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
