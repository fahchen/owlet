import SwiftData
import SwiftUI

struct VocabularyView: View {
    let collection: CollectionAction
    let openProcessing: () -> Void
    @Query(sort: \VocabularyEntry.createdAt, order: .reverse) private var entries: [VocabularyEntry]
    @State private var search = ""
    @State private var language = ""
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    private var filtered: [VocabularyEntry] {
        VocabularyFilter.apply(entries, search: search, language: language.isEmpty ? nil : language)
    }

    private var selectedEntries: [VocabularyEntry] {
        filtered.filter { selection.contains($0.persistentModelID) }
    }

    private var selectedEntry: VocabularyEntry? {
        selectedEntries.count == 1 ? selectedEntries.first : nil
    }

    var body: some View {
        page
            .navigationTitle(L10n.shared.string("Notebook"))
            .focusedSceneValue(\.copyText, selectedEntry?.expression)
            // The count lives under the title, so the list starts with its first row.
            .navigationSubtitle("\(filtered.count) expressions")
            .searchable(text: $search, placement: .toolbar, prompt: "Search expressions or meanings")
            .toolbar { toolbar }
            .onChange(of: filtered.map(\.persistentModelID), initial: true) { _, ids in
                selection.formIntersection(ids)
                if selection.isEmpty, let first = ids.first { selection = [first] }
            }
            .confirmationDialog(
                "Delete the \(selection.count) selected expressions?", isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteSelected() }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Operation failed",
                isPresented: Binding(
                    get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    /// The list beside the selected expression, or a single empty state when nothing matches.
    @ViewBuilder private var page: some View {
        if filtered.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WorkspaceSplit {
                List(selection: $selection) {
                    ForEach(filtered) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.expression)
                                .font(.system(size: PanelMetrics.sourceTextSize, weight: PanelMetrics.textWeight))
                                .lineLimit(1)
                            Text(entry.meaning.isEmpty ? "No meaning yet" : entry.meaning)
                                .foregroundStyle(.secondary).lineLimit(1)
                            Text(
                                L10n.shared.string(
                                    "\(LanguageCatalog.name(for: entry.language)) · \(entry.contexts.count) contexts")
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .tag(entry.persistentModelID)
                    }
                }
                .workspaceList()
            } detail: { _ in
                if let entry = selectedEntry {
                    VocabularyDetail(entry: entry, collection: collection)
                } else if selection.count > 1 {
                    ContentUnavailableView(
                        "\(selection.count) expressions selected", systemImage: "checkmark.circle",
                        description: Text(L10n.shared.string("Use the toolbar to delete the selection.")))
                } else {
                    ContentUnavailableView(
                        "Select an expression", systemImage: "sidebar.left",
                        description: Text(L10n.shared.string("Select something in the list to see its details.")))
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                Picker("Filter by Language", selection: $language) {
                    Text(L10n.shared.string("All Languages")).tag("")
                    ForEach(VocabularyFilter.languages(in: entries), id: \.self) { tag in
                        Text(LanguageCatalog.name(for: tag)).tag(tag)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Filter by Language", systemImage: "line.3.horizontal.decrease")
            }
            .labelStyle(.iconOnly).hoverTip("Filter by Language")
        }
        ToolbarItemGroup(placement: .principal) {
            Button("Previous", systemImage: "chevron.up") { if let previous { selection = [previous] } }
                .labelStyle(.iconOnly).keyboardShortcut(KeyHint.previous.shortcut).hoverTip(KeyHint.previous)
                .disabled(previous == nil)
            Button("Next", systemImage: "chevron.down") { if let next { selection = [next] } }
                .labelStyle(.iconOnly).keyboardShortcut(KeyHint.next.shortcut).hoverTip(KeyHint.next)
                .disabled(next == nil)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .labelStyle(.iconOnly).disabled(selection.isEmpty)
            .keyboardShortcut(KeyHint.delete.shortcut).hoverTip(KeyHint.delete, title: "Delete Selected")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        DefaultToolbarItem(kind: .search, placement: .primaryAction)
    }

    private var previous: PersistentIdentifier? {
        adjacentSelection(in: filtered.map(\.persistentModelID), to: selectedEntry?.persistentModelID, offset: -1)
    }

    private var next: PersistentIdentifier? {
        adjacentSelection(in: filtered.map(\.persistentModelID), to: selectedEntry?.persistentModelID, offset: 1)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(entries.isEmpty ? "The notebook is empty" : "No Matches", systemImage: "books.vertical")
        } description: {
            Text(
                entries.isEmpty
                    ? "Pick an expression in the study list to add it to the notebook."
                    : "Try another search or filter.")
        } actions: {
            if entries.isEmpty {
                Button("Go to Translate", action: openProcessing).buttonStyle(.glass)
            } else {
                Button(L10n.shared.string("Clear Filters")) {
                    search = ""; language = ""
                }.buttonStyle(.glass)
            }
        }
    }

    private func deleteSelected() {
        guard !selectedEntries.isEmpty else { return }
        do {
            try collection.store.delete(selectedEntries)
            selection = []
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

/// One expression: the expression itself, its meaning reading heavier than the
/// sentences it was collected from, and each sentence below a quiet heading.
private struct VocabularyDetail: View {
    let entry: VocabularyEntry
    let collection: CollectionAction

    /// The meaning is text in the language the entry recorded (BDR-0005), so a word in it is explained
    /// the way a source in that language is: through the mapping.
    private var meaningOrigin: LookupOrigin {
        let language = entry.lookupOrigin.definitionLanguage
        return LookupOrigin(
            language: language,
            definitionLanguage: SettingsStore.targetMapping().target(forSource: LanguageTag.key(language)))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "\(LanguageCatalog.name(for: entry.language)) · \(entry.contexts.count) contexts · saved \(HistoryTime.display(entry.createdAt))"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    // The entry's own form has no source sentence, so a lookup in it asks for the
                    // general meaning instead of passing the form off as its own context.
                    LookupText(
                        text: entry.expression, size: 22, weight: .semibold, lineSpacing: 0, label: "Expression",
                        origin: entry.lookupOrigin, hasSentence: false)
                    // The dictionary form the recommendation supplied, secondary to the collected form
                    // and only when it says something new (BDR-0009).
                    if !entry.lemma.isEmpty,
                        TranslationResult.normalized(entry.lemma)
                            != TranslationResult.normalized(entry.expression)
                    {
                        Text(entry.lemma).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if entry.meaning.isEmpty {
                        MissingMeaningView(entry: entry, collection: collection)
                    } else {
                        LookupText(
                            text: entry.meaning, size: PanelMetrics.textSize, weight: .medium, label: "Meaning",
                            origin: meaningOrigin)
                    }
                    Divider().padding(.vertical, 4)
                    Text(L10n.shared.string("Source Sentence")).font(.caption).foregroundStyle(.secondary)
                    ForEach(entry.contexts) { context in
                        VocabularyContextView(
                            context: context,
                            language: context.language.isEmpty
                                ? entry.language : context.language,
                            definitionLanguage: entry.lookupOrigin.definitionLanguage
                        )
                        .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // A reading column: long lines stop at 640pt instead of running across a wide window.
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, PanelMetrics.contentInset)
                .padding(.horizontal, 32)
                .panelBottomPadding()
            }
            .scrollBounceBehavior(.basedOnSize)
            CardButton(title: "Copy Expression", symbol: "document.on.document", key: .copy, bindsKey: false) {
                Clipboard.copy(entry.expression)
            }
            .padding([.trailing, .bottom], PanelMetrics.contentInset)
        }
    }
}
