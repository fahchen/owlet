import SwiftUI

/// The 学习表达 disclosure: silent until the user expands it, then it renders exactly one of
/// 整理中, 生成失败, 无推荐 or the checkable recommendations.
struct LearningView: View {
    @Bindable var learning: LearningModel
    let request: LearningRequest
    let collection: CollectionAction
    /// Nil when the panel was built without the notebook, which the tests do.
    let openNotebook: (() -> Void)?
    /// Tracks whether this section itself collected, so a status left by an earlier result cannot
    /// make a fresh recommendation list look already saved.
    @State private var attempted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            disclosure
            if learning.isExpanded { content }
        }
        .padding(.top, 12)
    }

    private var disclosure: some View {
        Button {
            learning.isExpanded.toggle()
            if learning.isExpanded { learning.generate(for: request) }
        } label: {
            HStack(spacing: 10) {
                Label("学习表达", systemImage: "sparkles")
                Spacer(minLength: 0)
                Text(learning.isExpanded ? "收起" : "展开")
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(learning.isExpanded ? 90 : 0))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .frame(minHeight: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("学习表达")
        .accessibilityValue(learning.isExpanded ? "已展开" : "已收起")
    }

    @ViewBuilder private var content: some View {
        switch learning.state {
        case .idle, .loading:
            loading
        case .failure:
            failure
        case .success(let items) where items.isEmpty:
            message("这次没有额外推荐，仍可手动选中内容收藏。")
        case .success(let items):
            recommendations(items)
        }
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("正在整理值得学习的表达…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 9)
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(maxWidth: .infinity)
                .frame(height: 9)
        }
        .padding(.top, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在整理值得学习的表达")
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 8) {
            message("学习内容暂时无法生成，译文仍可使用。")
            GlassEffectContainer {
                Button("重试", systemImage: "arrow.clockwise") { learning.retry(for: request) }
                    .buttonStyle(.glass)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recommendations(_ items: [LearningResult.Item]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                row(item, index: index)
                if index < items.count - 1 { Divider() }
            }
            if attempted {
                CollectionFeedback(collection: collection, openNotebook: openNotebook)
                    .font(.system(size: 11))
                    .padding(.top, 8)
            } else {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Button("收藏所选 \(learning.selected.count)") {
                        attempted = true
                        learning.collectSelected(into: collection, for: request)
                    }
                    .buttonStyle(.glass)
                    .disabled(learning.selected.isEmpty)
                }
                .padding(.top, 8)
            }
        }
    }

    private func row(_ item: LearningResult.Item, index: Int) -> some View {
        let checked = learning.selected.contains(index)
        return Button {
            if checked {
                learning.selected.remove(index)
            } else {
                learning.selected.insert(index)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(item.meaning)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(item.context)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.text)：\(item.meaning)")
        .accessibilityAddTraits(checked ? [.isSelected] : [])
    }
}
