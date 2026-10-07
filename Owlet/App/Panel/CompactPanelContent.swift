import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 773
    static let contentInset: CGFloat = 24
}

struct CompactProcessingView: View {
    @AppStorage(SettingsStore.panelGlassEffectKey) private var glassEffect = PanelGlassEffect.contrast
    let summary: String
    let status: String
    let stop: () -> Void
    var close: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            PanelSourceBar(summary: summary, close: close ?? stop)
            PanelSegmentedControl(items: [
                .init(title: status, symbol: "translate", action: {}),
                .init(title: "", symbol: "xmark", action: stop, accessibilityLabel: "取消处理"),
            ])
            .fixedSize()
            .frame(height: 36)
            .padding(.horizontal, 4)
            .glassEffect(glassEffect.glass)

        }
        .frame(width: PanelMetrics.width)
    }
}

struct PanelSourceBar: View {
    @AppStorage(SettingsStore.panelGlassEffectKey) private var glassEffect = PanelGlassEffect.contrast
    let summary: String
    var retry: (() -> Void)? = nil
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(summary.replacing(/\s+/, with: " "))
                .font(.system(size: 17, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(summary)
            if let retry {
                PanelSegmentedControl(items: [
                    .init(title: "Retry", symbol: "arrow.clockwise", action: retry),
                    .init(title: "", symbol: "xmark", action: close, accessibilityLabel: "关闭浮窗"),
                ])
                .fixedSize()
                .frame(height: 36)
                .padding(.horizontal, 4)
                .glassEffect(glassEffect.glass)

            } else {
                Button(action: close) { Label("关闭", systemImage: "xmark").foregroundStyle(.primary) }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13, weight: .medium))
                    .buttonStyle(.glass(glassEffect.glass))
                    .buttonBorderShape(.circle)
                    .controlSize(.extraLarge)
                    .buttonSizing(.flexible)
                    .frame(width: 36, height: 36)
                    .help("关闭浮窗")
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 12)
        .frame(width: PanelMetrics.width, height: 62)
        .glassEffect(glassEffect.glass)
        .gesture(WindowDragGesture())
    }
}

struct CompactNoticeView: View {
    @AppStorage(SettingsStore.panelGlassEffectKey) private var glassEffect = PanelGlassEffect.contrast
    let message: String
    var summary = ""
    var retry: (() -> Void)? = nil
    var close: () -> Void = {}
    var symbol = "exclamationmark.triangle"
    var actionTitle = "设置"
    var actionSymbol = "gearshape"
    var recover: () -> Void = {}
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            if !summary.isEmpty {
                PanelSourceBar(summary: summary, retry: retry, close: close)
            }
            PanelSegmentedControl(
                items: [
                    .init(title: message, symbol: symbol, action: recover),
                    .init(title: "", symbol: actionSymbol, action: action ?? recover, accessibilityLabel: actionTitle),
                ]
                    + (summary.isEmpty
                        ? [.init(title: "", symbol: "xmark", action: close, accessibilityLabel: "关闭浮窗")] : [])
            )
            .fixedSize()
            .frame(height: 36)
            .padding(.horizontal, 4)
            .glassEffect(glassEffect.glass)

        }
        .frame(width: PanelMetrics.width)
        .accessibilityElement(children: .contain)
    }
}
