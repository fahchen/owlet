import SwiftData
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore
    let collection: CollectionAction
    let openProcessing: () -> Void
    @Query(sort: \HistoryRecord.createdAt, order: .reverse) private var records: [HistoryRecord]
    @State private var search = ""
    @State private var operationFilter: Operation?
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var actionError: String?
    @State private var confirmingDelete = false
    /// Injectable, so a preview can show fixture items instead of requesting a model.
    @State var learning = LearningModel()

    private var filtered: [HistoryRecord] {
        HistoryFilter.apply(records, search: search, operation: operationFilter)
    }

    private var selectedRecords: [HistoryRecord] {
        filtered.filter { selection.contains($0.persistentModelID) }
    }

    private var selectedRecord: HistoryRecord? {
        selectedRecords.count == 1 ? selectedRecords.first : nil
    }

    var body: some View {
        page
            .navigationTitle(L10n.shared.string("History"))
            .focusedSceneValue(\.copyText, selectedRecord?.result)
            // The count lives under the title, so the list starts with its first row.
            .navigationSubtitle(L10n.shared.string("%@ records", filtered.count))
            .searchable(text: $search, placement: .toolbar, prompt: L10n.shared.string("Search source or result"))
            .toolbar { toolbar }
            .safeAreaInset(edge: .top) {
                if let message = store.lastError {
                    HStack {
                        Label(
                            L10n.shared.string("Could not save history: %@", message),
                            systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button(L10n.shared.string("Off"), systemImage: "xmark") { store.dismissError() }
                            .labelStyle(.iconOnly).hoverTip("Dismiss")
                    }.padding()
                }
            }
            .onChange(of: filtered.map(\.persistentModelID), initial: true) { _, ids in
                selection.formIntersection(ids)
                if selection.isEmpty, let first = ids.first { selection = [first] }
            }
            .onChange(of: selection) { _, _ in learning.reset() }
            .onDisappear { learning.reset() }
            .confirmationDialog(
                "Delete the \(selection.count) selected records?", isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button(L10n.shared.string("Delete"), role: .destructive) { deleteSelected() }
                Button(L10n.shared.string("Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.shared.string("Expressions in the notebook are not affected."))
            }
            .alert(
                "Operation failed",
                isPresented: Binding(
                    get: { actionError != nil }, set: { if !$0 { actionError = nil } })
            ) {
                Button(L10n.shared.string("OK"), role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
    }

    /// The list beside the selected record, or a single empty state when nothing matches.
    @ViewBuilder private var page: some View {
        if filtered.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WorkspaceSplit {
                List(selection: $selection) {
                    ForEach(filtered) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: record.operationKind.symbol)
                                    .foregroundStyle(Color(nsColor: record.operationKind.tint))
                                Text(
                                    L10n.shared.string(
                                        "%@ · %@", record.operationKind.name,
                                        HistoryTime.display(record.createdAt))
                                )
                                .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            // The result reads first, as in the panel; its source stays lighter below it.
                            Text(record.result)
                                .font(.system(size: PanelMetrics.sourceTextSize, weight: PanelMetrics.textWeight))
                                .lineLimit(2)
                            Text(record.source).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.vertical, 6)
                        .tag(record.persistentModelID)
                    }
                }
                .workspaceList()
            } detail: { _ in
                if let record = selectedRecord {
                    HistoryDetail(record: record, learning: learning, collection: collection)
                        .id(record.persistentModelID)
                } else if selection.count > 1 {
                    ContentUnavailableView(
                        "\(selection.count) records selected", systemImage: "checkmark.circle",
                        description: Text(L10n.shared.string("Use the toolbar to delete the selection.")))
                } else {
                    ContentUnavailableView(
                        "Select a record", systemImage: "sidebar.left",
                        description: Text(L10n.shared.string("Select something in the list to see its details.")))
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                Picker(L10n.shared.string("Filter by Type"), selection: $operationFilter) {
                    Text(L10n.shared.string("All Types")).tag(Operation?.none)
                    ForEach(Operation.allCases, id: \.self) { operation in
                        Text(verbatim: operation.name).tag(Operation?.some(operation))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(L10n.shared.string("Filter by Type"), systemImage: "line.3.horizontal.decrease")
            }
            .labelStyle(.iconOnly).hoverTip("Filter by Type")
        }
        ToolbarItemGroup(placement: .principal) {
            Button(L10n.shared.string("Previous"), systemImage: "chevron.up") {
                if let previous { selection = [previous] }
            }
            .labelStyle(.iconOnly).keyboardShortcut(KeyHint.previous.shortcut).hoverTip(KeyHint.previous)
            .disabled(previous == nil)
            Button(L10n.shared.string("Next"), systemImage: "chevron.down") { if let next { selection = [next] } }
                .labelStyle(.iconOnly).keyboardShortcut(KeyHint.next.shortcut).hoverTip(KeyHint.next)
                .disabled(next == nil)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                confirmingDelete = true
            } label: {
                Label(L10n.shared.string("Delete"), systemImage: "trash")
            }
            .labelStyle(.iconOnly).disabled(selection.isEmpty)
            .keyboardShortcut(KeyHint.delete.shortcut).hoverTip(KeyHint.delete, title: "Delete Selected")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        DefaultToolbarItem(kind: .search, placement: .primaryAction)
    }

    private var previous: PersistentIdentifier? {
        adjacentSelection(in: filtered.map(\.persistentModelID), to: selectedRecord?.persistentModelID, offset: -1)
    }

    private var next: PersistentIdentifier? {
        adjacentSelection(in: filtered.map(\.persistentModelID), to: selectedRecord?.persistentModelID, offset: 1)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(records.isEmpty ? "No History Yet" : "No Matches", systemImage: "clock")
        } description: {
            Text(
                records.isEmpty
                    ? "Translations and polishes you run are recorded here automatically."
                    : "Try another search or filter.")
        } actions: {
            if records.isEmpty {
                Button(L10n.shared.string("Go to Translate"), action: openProcessing).buttonStyle(.glass)
            } else {
                Button(L10n.shared.string("Clear Filters")) {
                    search = ""; operationFilter = nil
                }.buttonStyle(.glass)
            }
        }
    }

    private func deleteSelected() {
        guard !selectedRecords.isEmpty else { return }
        do {
            try store.delete(selectedRecords)
            selection = []
            actionError = nil
        } catch { actionError = error.localizedDescription }
    }
}

/// One record: the source, then the result that reads heavier, in one scrolling column. 学习 keeps
/// the learned sentence in view: the source and its divider collapse, the result rides up, and a
/// second divider and the learning items grow in below it. 返回 reverses it.
private struct HistoryDetail: View {
    let record: HistoryRecord
    @Bindable var learning: LearningModel
    let collection: CollectionAction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Negative until measured, so the first frame shows the source at its own height.
    @State private var sourceHeight: CGFloat = -1
    @State private var learningHeight: CGFloat = -1

    var body: some View {
        let spring: Animation? = reduceMotion ? nil : .spring(duration: 0.36, bounce: 0.12)
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(
                        L10n.shared.string(
                            "%@ · %@ · %@", record.operationKind.name,
                            LanguageCatalog.name(for: record.language),
                            HistoryTime.display(record.createdAt))
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                    VStack(alignment: .leading, spacing: 12) {
                        LookupText(
                            text: record.source, size: PanelMetrics.textSize, label: "Source",
                            origin: record.lookupOrigins(mapping: SettingsStore.targetMapping()).source
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                    .padding(.bottom, 12)
                    .collapsing(shown: !learning.isExpanded, height: $sourceHeight)
                    LookupText(
                        text: record.result, size: PanelMetrics.textSize, weight: .medium, justified: true,
                        origin: record.lookupOrigins(mapping: SettingsStore.targetMapping()).result)
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        // Only once opened: a closed list would show its disclosure row.
                        PanelLearningView(
                            learning: learning, request: request, collection: collection, showsDisclosure: false,
                            fitsRows: false, inline: true)
                    }
                    .padding(.top, 12)
                    .collapsing(shown: learning.isExpanded, height: $learningHeight)
                }
                // A reading column: long lines stop at 640pt instead of running across a wide window.
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, PanelMetrics.contentInset)
                .padding(.horizontal, 32)
                .panelBottomPadding()
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 8) {
                if learning.isExpanded {
                    CardButton(title: "Back", symbol: "chevron.left", key: .learn) { learning.isExpanded = false }
                } else {
                    CardButton(title: "Study", symbol: "lamp.desk", key: .learn) { learning.isExpanded = true }
                }
                CardButton(title: "Copy Result", symbol: "document.on.document", key: .copy, bindsKey: false) {
                    Clipboard.copy(record.result)
                }
            }
            .padding([.trailing, .bottom], PanelMetrics.contentInset)
        }
        .animation(spring, value: learning.isExpanded)
        // The items arrive after the list opens, so its height keeps growing with them.
        .animation(spring, value: learningHeight)
        .onDisappear { learning.reset() }
    }

    private var request: LearningRequest {
        LearningRequest(
            text: record.source, operation: record.operationKind, targetLanguage: record.language,
            result: record.result, claimAutoRequest: { false })
    }
}

extension View {
    /// Opens and closes to the content's own measured height. A number, never nil, so the change
    /// interpolates instead of jumping; the content keeps its height and the clip reveals it.
    fileprivate func collapsing(shown: Bool, height: Binding<CGFloat>) -> some View {
        fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height.wrappedValue = $0 }
            .frame(height: shown ? (height.wrappedValue < 0 ? nil : height.wrappedValue) : 0, alignment: .top)
            .clipped()
            // Selectable text draws past a clip, so it fades out quickly as it goes.
            .opacity(shown ? 1 : 0)
    }
}

/// Short, human dates for the detail header, matching the 今天 HH:mm style of the design.
enum HistoryTime {
    static func display(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
