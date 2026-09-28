import SwiftUI

/// 调试 pane, shown only while the switch in 通用 is on: the captured model exchanges, one list row
/// each. A collapsed row says what was asked for and shows the text that was sent, truncated; the
/// disclosure control on its trailing edge opens the raw request and reply.
struct DebugSettingsPane: View {
    @State private var log = DebugLog.shared
    /// Which rows are open, kept outside the rows so a new capture cannot leave one half expanded.
    @State private var expanded: Set<UUID> = []

    var body: some View {
        Group {
            if log.exchanges.isEmpty {
                ContentUnavailableView(
                    "还没有记录", systemImage: "ladybug",
                    description: Text("发一次翻译或润色后会出现在这里。"))
            } else {
                // `List(_:)` over the identified collection: no explicit `ForEach` needed.
                List(log.exchanges) { exchange in
                    VStack(alignment: .leading, spacing: 0) {
                        // The whole row is the control, and the chevron at its trailing edge shows which
                        // way it goes. `DisclosureGroup` would put its triangle on the leading edge,
                        // where the row's own content starts.
                        Button {
                            toggle(exchange)
                        } label: {
                            summary(exchange)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(exchange.title)
                        .accessibilityValue(isExpandedNow(exchange) ? "已展开" : "已收起")
                        if isExpandedNow(exchange) {
                            detail(exchange).padding(.bottom, 10)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    /// What was asked for, the text that was sent, and when. The text is cut to one line: the whole
    /// point of the row is to be scannable, and the chevron opens the rest.
    private func summary(_ exchange: DebugExchange) -> some View {
        HStack(spacing: 10) {
            Text(exchange.title)
                .font(.system(size: 12, weight: .medium))
            Text(exchange.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(exchange.date.formatted(date: .omitted, time: .standard))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpandedNow(exchange) ? 90 : 0))
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    /// The captured content itself. No nested scroll view: the list already scrolls, and nesting a
    /// second one on the same axis fights it.
    @ViewBuilder private func detail(_ exchange: DebugExchange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let failure = exchange.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if let divergence = exchange.sourceDivergence {
                Text(divergence)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
            block("提交原文", exchange.submitted)
            block("模型原始返回", exchange.response ?? "—")
            block("请求体", exchange.request)
            Button("复制这条记录") { Clipboard.copy(exchange.report) }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Animated, as a disclosure change is expected to be.
    private func toggle(_ exchange: DebugExchange) {
        withAnimation {
            if expanded.contains(exchange.id) {
                expanded.remove(exchange.id)
            } else {
                expanded.insert(exchange.id)
            }
        }
    }

    private func isExpandedNow(_ exchange: DebugExchange) -> Bool {
        expanded.contains(exchange.id)
    }
}
