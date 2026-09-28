import SwiftUI

/// Hidden diagnostics page, shown only while 调试 is on in settings: it lists the last model
/// exchanges with the raw request and response, so a contract failure can be read and copied out.
/// Nothing here is persisted, and the API key is not part of it.
struct DebugView: View {
    @State private var log = DebugLog.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                legend
                if log.exchanges.isEmpty {
                    Text("还没有记录。打开「调试」后发一次翻译或润色，这里就会显示这次请求与返回。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(log.exchanges) { exchange in
                        card(exchange)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .navigationTitle("调试")
        .safeAreaBar(edge: .bottom) {
            PageFooter {
                Text("只保留最近 \(DebugLog.limit) 次，重启即清空；内容不含 API Key。")
            } trailing: {
                Button("复制全部") { Clipboard.copy(allReports) }
                    .buttonStyle(.glass)
                    .disabled(log.exchanges.isEmpty)
                Button("清空") { log.clear() }
                    .buttonStyle(.glass)
                    .disabled(log.exchanges.isEmpty)
            }
        }
    }

    /// The failures the contract can produce, so the raw data below has something to be read against.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("可能的失败原因").font(.system(size: 12, weight: .semibold))
            Text(
                """
                · 返回的结构不符合约定：字段缺失、类型不对、内容为空，或 JSON 外还有文字
                · 返回的目标语言与请求不一致（例如请求 zh-Hant，返回 zh-Hans）
                · 返回的原文与提交的内容不一致（拼接后不等）
                · 结果过长被截断、服务拒绝处理、网络、认证、HTTP、空内容
                """
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ exchange: DebugExchange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(exchange.title).font(.system(size: 13, weight: .semibold))
                Text(exchange.date.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("复制") { Clipboard.copy(exchange.report) }
                    .buttonStyle(.glass)
            }
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
            block("请求体", exchange.request)
            if let response = exchange.response { block("模型原始返回", response) }
            block("提交原文", exchange.submitted)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var allReports: String {
        log.exchanges.map(\.report).joined(separator: "\n\n---\n\n")
    }
}
