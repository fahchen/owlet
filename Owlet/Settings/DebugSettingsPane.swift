import SwiftUI

/// 调试 pane, shown only while the switch in 通用 is on: the last model exchanges with the raw request
/// and response, so a contract failure can be read and copied out. Nothing here is persisted, and the
/// API key is not part of it.
struct DebugSettingsPane: View {
    @State private var log = DebugLog.shared

    var body: some View {
        Form {
            Section {
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
            } header: {
                Text("可能的失败原因")
            } footer: {
                Text("只保留最近 \(DebugLog.limit) 次，重启即清空；内容不含 API Key。")
            }

            if log.exchanges.isEmpty {
                Section {
                    Text("还没有记录。发一次翻译或润色，这里就会显示这次请求与返回。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    GlassEffectContainer {
                        Button("复制全部") { Clipboard.copy(allReports) }
                            .buttonStyle(.glass)
                        Button("清空", action: log.clear)
                            .buttonStyle(.glass)
                    }
                }
                ForEach(log.exchanges) { exchange in
                    exchangeSection(exchange)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func exchangeSection(_ exchange: DebugExchange) -> some View {
        Section {
            if let failure = exchange.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if let divergence = exchange.sourceDivergence {
                Text(divergence)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
            block("请求体", exchange.request)
            if let response = exchange.response {
                block("模型原始返回", response)
            }
            block("提交原文", exchange.submitted)
            Button("复制这条记录") { Clipboard.copy(exchange.report) }
        } header: {
            HStack {
                Text(exchange.title)
                Spacer(minLength: 0)
                Text(exchange.date.formatted(date: .omitted, time: .standard))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Long text stays folded behind a disclosure, so the pane opens on the failure, not on a wall of
    /// JSON.
    private func block(_ title: String, _ text: String) -> some View {
        DisclosureGroup(title) {
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
