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
    /// True inside a page's own scroll view: the items lie in its flow, with no scroll view or edge
    /// bands of their own, and the waiting states take a fixed height instead of the whole column.
    var inline = false
    @Query private var entries: [VocabularyEntry]
    @State private var attempted = false
    @State private var hovered: Int?
    /// Measured item heights, so the column fits three items at least and five at most.
    @State private var rowHeights: [Int: CGFloat] = [:]
    /// Item height before one is measured: a one-line expression over a one-line meaning.
    private static let estimatedRowHeight: CGFloat = 50
    private static let rowSpacing: CGFloat = 4
    /// The inline loading and failure states: room for the message, centered, before items arrive.
    private static let inlineStateHeight: CGFloat = 160

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
                .frame(height: inline ? Self.inlineStateHeight : nil)
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
            .frame(height: inline ? Self.inlineStateHeight : nil)
            .padding(.horizontal, PanelMetrics.contentInset)
        case .success(let items) where items.isEmpty:
            Text("这次没有额外推荐。")
                .foregroundStyle(.secondary)
                .padding(PanelMetrics.contentInset)
        case .success(let items) where inline:
            rows(items)
        case .success(let items):
            ScrollView {
                rows(items)
                    // Inside the scroll view, so the edge bands span the whole column.
                    .padding(.horizontal, PanelMetrics.contentInset)
                    .panelBottomPadding()
            }
            .scrollBounceBehavior(.basedOnSize)
            .panelEdgeBands()
        }
    }

    private func rows(_ items: [LearningResult.Item]) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                // Not one Button: a button would take every click and drag on the expression, so it
                // could neither be selected nor looked up. The row still collects on a click.
                HStack(alignment: .center, spacing: 12) {
                    Button {
                        toggleCollection(item)
                    } label: {
                        Image(systemName: isCollected(item) ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isCollected(item) ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.text)
                    .accessibilityValue(isCollected(item) ? "已收藏" : "未收藏")
                    .accessibilityHint(isCollected(item) ? "取消收藏" : "加入生词本")
                    VStack(alignment: .leading, spacing: 4) {
                        LookupText(
                            text: item.text, size: NSFont.systemFontSize, lineSpacing: 0, label: "学习表达",
                            origin: lookupOrigin(item), sentence: item.context,
                            onPlainClick: { toggleCollection(item) })
                        Text(item.meaning).font(.caption).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                // The row's only feedback is its background, as before.
                .background(.quaternary.opacity(hovered == index ? 1 : 0), in: RoundedRectangle(cornerRadius: 8))
                .onTapGesture { toggleCollection(item) }
                .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                .hoverTip(isCollected(item) ? "取消收藏" : "加入生词本")
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { rowHeights[index] = $0 }
            }
            // Only a failed save is reported: a success already shows as the filled bookmark.
            if attempted, case .saveFailed(let message) = collection.status {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
        }
    }

    private func isCollected(_ item: LearningResult.Item) -> Bool {
        entries.contains {
            $0.language == item.language
                && $0.expression == item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// BDR-0005 for a recommendation: a translation's is explained in this result's target, a
    /// polish's in the mapped target of the expression's language.
    private func lookupOrigin(_ item: LearningResult.Item) -> LookupOrigin {
        LookupOrigin(
            language: item.language,
            definitionLanguage: request.operation == .translate
                ? request.targetLanguage
                : SettingsStore.targetMapping().target(forSource: LanguageTag.key(item.language)))
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
