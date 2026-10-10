import SwiftUI
import SwiftData

struct PanelLearningView: View {
    @Bindable var learning: LearningModel
    let request: LearningRequest
    let collection: CollectionAction
    var showsDisclosure = true
    /// The panel's height when learning opened; the column keeps it within its own range and only
    /// shrinks below it when the items need less, so the switch never dips and grows back.
    var preferredHeight: CGFloat = 0
    /// False in the main window, where the column fills the card instead of fitting three to five items.
    var fitsRows = true
    @Query private var entries: [VocabularyEntry]
    @State private var attempted = false
    @State private var hovered: Int?
    /// Measured item heights, so the column fits three items at least and five at most.
    @State private var rowHeights: [Int: CGFloat] = [:]
    /// Item height before one is measured: a one-line expression over a one-line meaning.
    private static let estimatedRowHeight: CGFloat = 50
    private static let rowSpacing: CGFloat = 4

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
        .frame(height: fitsRows ? columnHeight : nil)
        .onAppear { requestLearning() }
        .onChange(of: learning.isExpanded) { _, expanded in
            if expanded { learning.generate(for: request) }
        }
        .onChange(of: request) { _, _ in
            attempted = false
            requestLearning()
        }
    }

    /// The list viewport stays three to five items tall, between the edge bands; any number of items
    /// fits, and more than fit scroll. Within that range it keeps the preferred height, and shrinks
    /// below it only to what the items need. Until they arrive, nothing is known to need less.
    private var columnHeight: CGFloat {
        let items = if case .success(let items) = learning.state { items } else { [LearningResult.Item]() }
        let heights = items.indices.map { rowHeights[$0] ?? Self.estimatedRowHeight }
        let average = heights.isEmpty ? Self.estimatedRowHeight : heights.reduce(0, +) / CGFloat(heights.count)
        func rows(_ count: Int) -> CGFloat {
            (0..<count).reduce(0) { $0 + (heights.indices.contains($1) ? heights[$1] : average) }
                + Self.rowSpacing * CGFloat(max(count - 1, 0))
        }
        let bands = PanelMetrics.contentInset * 2
        let needed = heights.isEmpty ? .infinity : rows(heights.count)
        return min(max(min(preferredHeight - bands, needed), rows(3)), rows(5)) + bands
    }

    private func requestLearning() {
        if learning.isExpanded { learning.generate(for: request) }
        learning.generateIfAutoRequested(for: request)
    }

    @ViewBuilder private var content: some View {
        switch learning.state {
        case .idle, .loading:
            Text("正在整理值得学习的表达…")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, PanelMetrics.contentInset)
        case .failure(let message):
            VStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("重试", systemImage: "arrow.clockwise") {
                    learning.retry(for: request)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, PanelMetrics.contentInset)
        case .success(let items) where items.isEmpty:
            Text("这次没有额外推荐。")
                .foregroundStyle(.secondary)
                .padding(PanelMetrics.contentInset)
        case .success(let items):
            ScrollView {
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        Button {
                            toggleCollection(item)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: isCollected(item) ? "bookmark.fill" : "bookmark")
                                    .foregroundStyle(isCollected(item) ? Color.accentColor : Color.primary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.text).font(.body).foregroundStyle(.primary)
                                    Text(item.meaning).font(.caption).foregroundStyle(.secondary)
                                }
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(LearningRowStyle(hovered: hovered == index))
                        .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                        .accessibilityValue(isCollected(item) ? "已收藏" : "未收藏")
                        .help(isCollected(item) ? "取消收藏" : "加入生词本")
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { rowHeights[index] = $0 }
                    }
                    // Only a failed save is reported: a success already shows as the filled bookmark.
                    if attempted, case .saveFailed(let message) = collection.status {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
                // Inside the scroll view, so the edge bands span the whole column.
                .padding(.horizontal, PanelMetrics.contentInset)
                .panelBottomPadding()
            }
            .scrollBounceBehavior(.basedOnSize)
            .panelEdgeBands()
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

/// The learning row's only feedback is its background: hover shows it and a press keeps it.
/// Not borderless, which dims the label in the never-active panel, and not plain, whose press
/// fades the whole row, background included, so a click reads as a flash.
private struct LearningRowStyle: ButtonStyle {
    let hovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                .quaternary.opacity(hovered || configuration.isPressed ? 1 : 0),
                in: RoundedRectangle(cornerRadius: 8))
    }
}
