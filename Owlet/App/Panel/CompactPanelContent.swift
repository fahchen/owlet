import SwiftUI

/// The panel's one width: the compact strip and the expanded panel share it, so expanding never
/// changes the panel's width — only its height grows.
enum PanelMetrics {
    static let width: CGFloat = 560
}

/// Compact processing bar: one-line summary of the selected text, spinner, status, stop.
struct CompactProcessingView: View {
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
        .frame(width: PanelMetrics.width)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(status) \(summary)")
    }
}

/// Compact notice bar used before the first result: message left, glass recovery buttons right.
struct CompactNoticeView<Actions: View>: View {
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
        .frame(width: PanelMetrics.width)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .accessibilityElement(children: .contain)
    }
}
