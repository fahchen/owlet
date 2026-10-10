import SwiftUI

extension View {
    /// The panel's one glass surface: a fixed-radius rounded rectangle, with the content clipped to
    /// it so nothing shows past its corners. A nil height hugs the content.
    func panelSurface(_ glass: Glass, height: CGFloat? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius)
        return frame(width: PanelMetrics.width, height: height, alignment: .top)
            .clipShape(shape)
            .glassEffect(glass, in: shape)
    }
}

enum PanelMetrics {
    static let width: CGFloat = 773
    static let contentInset: CGFloat = 24
    /// Result text; the source sits one size below it so the translation reads first.
    static let textSize: CGFloat = 16
    static let sourceTextSize: CGFloat = 15
    static let textWeight: Font.Weight = .medium
    /// Transparent window margin around the glass, so its shadow fades out instead of being cut
    /// at the window edge.
    static let shadowMargin: CGFloat = 24
    /// The source bar; the expanded glass grows down from this height.
    static let sourceBarHeight: CGFloat = 62
    /// The expanded glass corner radius, from the design's large surface.
    static let cornerRadius: CGFloat = 34
    /// Extra scroll room past the content, so the floating action row (36pt buttons, 12pt above them)
    /// can sit over the text at rest and the text still scrolls out from under it.
    static let actionRoom: CGFloat = 36 + 12
}

struct CompactProcessingView: View {
    @AppStorage(SettingsStore.panelGlassEffectKey) private var glassEffect = PanelGlassEffect.contrast
    let summary: String
    let status: String
    let stop: () -> Void
    var close: (() -> Void)? = nil
    /// False when the panel root draws the source bar on its own growing surface.
    var showsBar = true

    var body: some View {
        VStack(spacing: 12) {
            if showsBar {
                PanelSourceBar(summary: summary, close: close ?? stop)
            }
            PanelSegmentedControl(items: [
                .init(title: status, symbol: "translate", action: {}),
                .init(title: "", symbol: "xmark", action: stop, accessibilityLabel: "取消处理"),
            ])
            .fixedSize()
            .frame(height: 36)
            .padding(.horizontal, 4)
            .glassEffect(glassEffect.compactGlass)

        }
        .frame(width: PanelMetrics.width)
    }
}

struct PanelSourceBar: View {
    @AppStorage(SettingsStore.panelGlassEffectKey) private var glassEffect = PanelGlassEffect.contrast
    let summary: String
    var retry: (() -> Void)? = nil
    let close: () -> Void
    /// False on the panel root's surface, which supplies the glass so it can grow into the panel.
    var drawsGlass = true

    var body: some View {
        HStack(spacing: 8) {
            Text(summary.replacing(/\s+/, with: " "))
                .font(.system(size: PanelMetrics.sourceTextSize, weight: PanelMetrics.textWeight))
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
        .frame(width: PanelMetrics.width, height: PanelMetrics.sourceBarHeight)
        .glassEffect(drawsGlass ? glassEffect.compactGlass : .identity)
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
    var isError = true
    /// False when the panel root draws the source bar on its own growing surface.
    var showsBar = true

    var body: some View {
        VStack(spacing: 12) {
            if showsBar && !summary.isEmpty {
                PanelSourceBar(summary: summary, retry: retry, close: close)
            }
            PanelSegmentedControl(
                items: [
                    .init(title: message, symbol: symbol, action: recover, tint: isError ? .systemRed : nil),
                    .init(title: "", symbol: actionSymbol, action: action ?? recover, accessibilityLabel: actionTitle),
                ]
                    + (summary.isEmpty
                        ? [.init(title: "", symbol: "xmark", action: close, accessibilityLabel: "关闭浮窗")] : [])
            )
            .fixedSize()
            .frame(height: 36)
            .padding(.horizontal, 4)
            .glassEffect(glassEffect.compactGlass)

        }
        .frame(width: PanelMetrics.width)
        .accessibilityElement(children: .contain)
    }
}
