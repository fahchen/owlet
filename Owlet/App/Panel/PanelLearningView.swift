import SwiftUI
import SwiftData

struct PanelLearningView: View {
    @Bindable var learning: LearningModel
    let request: LearningRequest
    let collection: CollectionAction
    let openNotebook: (() -> Void)?
    var showsDisclosure = true
    @Query private var entries: [VocabularyEntry]
    @State private var attempted = false

    var body: some View {
        Group {
            if learning.isExpanded || learning.state != .idle {
                content
            } else if showsDisclosure {
                DisclosureGroup("学习表达", isExpanded: $learning.isExpanded) {
                    content
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { requestLearning() }
        .onChange(of: learning.isExpanded) { _, expanded in
            if expanded { learning.generate(for: request) }
        }
        .onChange(of: request) { _, _ in
            attempted = false
            requestLearning()
        }
    }

    private func requestLearning() {
        if learning.isExpanded { learning.generate(for: request) }
        learning.generateIfAutoRequested(for: request)
    }

    @ViewBuilder private var content: some View {
        switch learning.state {
        case .idle, .loading:
            ProgressView("正在整理值得学习的表达…")
                .controlSize(.small)
        case .failure(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                Button("重试", systemImage: "arrow.clockwise") {
                    learning.retry(for: request)
                }
                .buttonStyle(.glass)
            }
        case .success(let items) where items.isEmpty:
            Text("这次没有额外推荐。")
                .foregroundStyle(.secondary)
        case .success(let items):
            VStack(alignment: .leading, spacing: 8) {
                List {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Button {
                            toggleCollection(item)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: isCollected(item) ? "bookmark.fill" : "bookmark")
                                    .foregroundStyle(.primary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.text).font(.body)
                                    Text(item.meaning).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityValue(isCollected(item) ? "已收藏" : "未收藏")
                        .help(isCollected(item) ? "取消收藏" : "加入生词本")
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .safeAreaPadding(.bottom, 36)
                if attempted {
                    NotebookSaveFeedback(collection: collection, openNotebook: openNotebook)
                }
            }
        }
    }

    private func isCollected(_ item: LearningResult.Item) -> Bool {
        entries.contains {
            $0.language == item.language
                && $0.expression == item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func toggleCollection(_ item: LearningResult.Item) {
        attempted = true
        let polish = request.operation == .polish
        collection.setCollected(
            !isCollected(item),
            draft: VocabularyDraft(
                expression: item.text, language: item.language, context: item.context,
                polishBefore: polish ? request.text : nil,
                polishAfter: polish ? request.result : nil),
            meaning: item.meaning)
    }
}
