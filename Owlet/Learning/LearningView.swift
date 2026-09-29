import SwiftUI

struct LearningView: View {
    enum Reveal {
        case disclosure
        case immediate
    }

    @Bindable var learning: LearningModel
    var reveal: Reveal = .disclosure
    let request: LearningRequest
    let collection: CollectionAction
    let openNotebook: (() -> Void)?
    @State private var attempted = false

    var body: some View {
        Group {
            if reveal == .disclosure {
                DisclosureGroup(isExpanded: $learning.isExpanded) {
                    content
                } label: {
                    heading
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    heading
                    content
                }
            }
        }
        .onAppear { askIfRevealed() }
        .onChange(of: learning.isExpanded) { _, expanded in
            if expanded { learning.generate(for: request) }
        }
        .onChange(of: request) { _, _ in
            attempted = false
            askIfRevealed()
        }
    }

    private var heading: some View {
        HStack {
            Label("学习", systemImage: "lightbulb.fill")
            Spacer(minLength: 8)
            if learning.isExpanded || reveal == .immediate {
                if !learning.selected.isEmpty {
                    Text("已选 \(learning.selected.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("加入生词本", systemImage: "text.badge.plus") {
                    attempted = true
                    learning.collectSelected(into: collection, for: request)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .help("加入生词本")
                .disabled(learning.selected.isEmpty)
            }
        }
        .frame(minHeight: 36)
    }

    private func askIfRevealed() {
        if reveal == .immediate || learning.isExpanded { learning.generate(for: request) }
        learning.generateIfAutoRequested(for: request)
    }

    @ViewBuilder private var content: some View {
        switch learning.state {
        case .idle, .loading:
            ProgressView("正在整理值得学习的表达…")
                .controlSize(.small)
                .padding(.vertical, 8)
        case .failure(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("重试", systemImage: "arrow.clockwise") {
                    learning.retry(for: request)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .help("重试生成学习内容")
            }
        case .success(let items) where items.isEmpty:
            Text("这次没有额外推荐。")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        case .success(let items):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        Toggle(
                            isOn: Binding(
                                get: { learning.selected.contains(index) },
                                set: { checked in
                                    if checked {
                                        learning.selected.insert(index)
                                    } else {
                                        learning.selected.remove(index)
                                    }
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.text).font(.headline)
                                Text(item.meaning).foregroundStyle(.secondary)
                                Text(item.context).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(.checkbox)
                        if index < items.count - 1 { Divider() }
                    }
                    if attempted {
                        CollectionFeedback(collection: collection, openNotebook: openNotebook)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 220)
        }
    }
}
