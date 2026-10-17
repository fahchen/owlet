import SwiftUI

/// The Translate and Polish pages: one glass card with the source on the left and the result on the right,
/// switched by the toolbar's operation control. Study shows the result beside its learning items.
struct TextProcessingView: View {
    @Bindable var model: TextProcessingModel
    let openSettings: () -> Void
    let collection: CollectionAction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Injectable, so a preview can show fixture items instead of requesting a model.
    @State var learning = LearningModel()
    @AppStorage(SettingsStore.pinnedTargetKey) private var pinnedTarget = ""
    @AppStorage(SettingsStore.pinnedSourceKey) private var pinnedSource = ""
    @AppStorage(SettingsStore.displayModeKey) private var displayMode = TranslationDisplayMode.sectioned

    var body: some View {
        // The space offered, not the card's own size: the columns are sized from it, so measuring the
        // card would feed their widths back into it and keep it from ever shrinking with the window.
        GeometryReader { card(in: $0.size) }
            .padding(PanelMetrics.contentInset)
            .navigationTitle(model.operation.title)
            .focusedSceneValue(\.copyText, resultText)
            .toolbar { toolbar }
            .onChange(of: model.operation) { _, _ in reprocessForCurrentOptions() }
            .onChange(of: pinnedTarget) { _, _ in reprocessForCurrentOptions() }
            // The source only picks the target, so it moves the target, and that change reprocesses.
            .onChange(of: pinnedSource) { _, source in
                pinnedTarget = SettingsStore.target(followingSource: source)
            }
            .onChange(of: model.input) { _, _ in learning.reset() }
            .onChange(of: model.state) { _, state in
                if state == .loading { learning.reset() }
                if let request = LearningRequest.from(model) {
                    learning.generateIfAutoRequested(for: request)
                }
            }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker(L10n.shared.string("Operation"), selection: $model.operation) {
                ForEach(Operation.allCases, id: \.self) { operation in
                    Image(nsImage: segmentSymbol(operation)).tag(operation)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(isBusy)
            .hoverTip(
                verbatim: KeyHint.translateMode.tooltip + "　" + KeyHint.polishMode.tooltip)
        }
        // Polish keeps the source language, so it only offers that one.
        ToolbarItem(placement: .primaryAction) {
            let picker = SourceLanguagePicker(text: model.input, pinnedSource: $pinnedSource)
            languageMenu(picker.title, picker)
        }
        if model.operation == .translate {
            ToolbarItem(placement: .primaryAction) {
                Image(systemName: "chevron.forward.2")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                let picker = TargetLanguagePicker(text: model.input, pinnedTarget: $pinnedTarget)
                languageMenu(picker.title, picker)
            }
        }
    }

    /// The selected operation's symbol in its own color, the others in the label color, as designed.
    /// A segmented picker draws every symbol as a template, so each is a pre-colored image.
    private func segmentSymbol(_ operation: Operation) -> NSImage {
        PanelSegmentedControl.content(
            of: .init(
                title: "", symbol: operation.symbol, action: {},
                accessibilityLabel: operation.name,
                tint: model.operation == operation ? operation.tint : nil),
            font: nil)
    }

    /// A pull-down that is as wide as the current choice; a pop-up button is as wide as its longest.
    private func languageMenu(_ title: String, _ picker: some View) -> some View {
        Menu {
            picker.pickerStyle(.inline)
        } label: {
            // The design's pop-up indicator, on a pull-down that hugs its label.
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
            .pullDownLabelInset()
        }
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func card(in size: CGSize) -> some View {
        let sideBySide = ProcessingLayout.choose(width: size.width) == .sideBySide
        let axis: Axis = sideBySide ? .horizontal : .vertical
        let column = max(((sideBySide ? size.width : size.height) - 1) / 2, 0)
        let columns = sideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        return ZStack(alignment: .bottomTrailing) {
            // Three slots on one axis, as learning opens: the source shrinks to nothing, the result
            // moves into its place, and the learning column grows in behind it.
            columns {
                // The source squeezes its text as it goes; the learning column keeps its own width.
                slot(
                    columns {
                        sourceColumn; divider(axis)
                    }, length: column + 1, shown: !showsLearning, axis: axis, squeezes: true)
                resultColumn.frame(width: sideBySide ? column : nil, height: sideBySide ? nil : column)
                if let request = LearningRequest.from(model) {
                    slot(
                        columns {
                            divider(axis)
                            PanelLearningView(
                                learning: learning, request: request, collection: collection, fitsRows: false)
                        }, length: column + 1, shown: showsLearning, axis: axis)
                }
            }
            actions
                .padding(.trailing, PanelMetrics.contentInset)
                .padding(.bottom, PanelMetrics.contentInset)
        }
        .overlay(alignment: .bottomLeading) {
            learningAction
                .padding(.leading, PanelMetrics.contentInset)
                .padding(.bottom, PanelMetrics.contentInset)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(reduceMotion ? nil : .spring(duration: 0.36, bounce: 0.12), value: showsLearning)
        .workspaceCard()
    }

    /// A column that opens and closes along the axis. A squeezing column rewraps its text as it
    /// narrows; otherwise the content keeps the full length and the slot clips it.
    private func slot(
        _ content: some View, length: CGFloat, shown: Bool, axis: Axis, squeezes: Bool = false
    ) -> some View {
        let horizontal = axis == .horizontal
        let full: CGFloat? = squeezes ? nil : length
        return
            content
            .frame(width: horizontal ? full : nil, height: horizontal ? nil : full)
            .frame(
                width: horizontal ? (shown ? length : 0) : nil, height: horizontal ? nil : (shown ? length : 0),
                alignment: .topLeading
            )
            .clipped()
            .opacity(shown ? 1 : 0)
    }

    /// Inset along its length only; each column keeps its own inset from it.
    private func divider(_ axis: Axis) -> some View {
        Divider().padding(axis == .horizontal ? .vertical : .horizontal, PanelMetrics.contentInset)
    }

    private var sourceColumn: some View {
        TextEditor(text: $model.input)
            .textEditorStyle(.plain)
            .scrollContentBackground(.hidden)
            .font(.system(size: PanelMetrics.textSize, weight: PanelMetrics.sourceWeight))
            .lineSpacing(2)
            .accessibilityLabel(L10n.shared.string("Source"))
            .overlay(alignment: .topLeading) {
                if model.input.isEmpty {
                    // The page has no submit button; the placeholder names the shortcut instead.
                    Text(L10n.shared.string(model.operation.placeholder.key))
                        .font(.system(size: PanelMetrics.textSize, weight: PanelMetrics.sourceWeight))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            // As on the panel: the text rests clear of the edges and scrolls under them, fading out.
            .safeAreaPadding(.vertical, PanelMetrics.contentInset)
            .panelEdgeFade()
            // The editor insets its text by 5pt itself, so the text lines up with the result's.
            .padding(.horizontal, PanelMetrics.contentInset - 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var resultColumn: some View {
        // Loading and errors sit centered in the column, as the learning column's own states do.
        switch model.state {
        case .loading:
            // A run in progress shows its arriving text here, laid out as the setting lays the
            // finished result out (BDR-0017); before anything displayable it is the progress words.
            if model.isReceiving {
                resultScroll
            } else {
                Text(L10n.shared.string(model.operation.progress.key))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .failure(let message, let kind):
            failure(
                message, action: kind == .contract ? "Prompt Settings" : "Service Settings",
                beside: model.lastResultText)
        case .missingConfig:
            failure(
                L10n.shared.string("The model service is not configured"),
                action: L10n.shared.string("Configure Service"), beside: model.lastResultText)
        case .idle, .success:
            resultScroll
        }
    }

    /// A failure reads as a state of the page rather than as a line of red text: the symbol, then the
    /// words quoted in a block, then the one way out — the same shape the panel's notices use. When a
    /// result from before the failure is still around, it stays on the page and the failure sits under
    /// it: the error is about the retry, not about what was already produced.
    @ViewBuilder private func failure(_ message: String, action: String, beside kept: String?)
        -> some View
    {
        if kept != nil {
            VStack(spacing: 0) {
                resultScroll
                failureNote(message, action: action)
            }
        } else {
            failureNote(message, action: action)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func failureNote(_ message: String, action: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .failureBlock()
            Button(action, systemImage: "gearshape", action: openSettings)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, PanelMetrics.contentInset)
        .padding(.bottom, PanelMetrics.contentInset)
    }

    private var resultScroll: some View {
        ScrollView {
            result
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PanelMetrics.contentInset)
                // Beside the learning column the buttons sit on the right, so this side needs no room.
                .panelBottomPadding(besideActions: !showsLearning)
        }
        .scrollBounceBehavior(.basedOnSize)
        .panelEdgeBands()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var result: some View {
        // While a reply is arriving, the layout follows the display setting, as the panel's does;
        // the last finished result stands only once nothing is in flight.
        if model.isReceiving {
            VStack(alignment: .leading, spacing: 7) {
                ProgressView(L10n.shared.string(model.operation.progress.key)).controlSize(.small)
                ReceivingResult(
                    segments: model.receiving ?? [], mode: displayMode, justified: true)
            }
        } else if let text = model.lastResultText {
            // The last finished result, which a failure no longer takes off the page.
            let origin = model.languages.map {
                LookupOrigin.result(of: model.operation, languages: $0, mapping: SettingsStore.targetMapping())
            }
            if displayMode == .aligned, !model.segments.isEmpty {
                AlignedSegments(
                    segments: model.segments, sourceSize: PanelMetrics.sourceTextSize,
                    targetSize: PanelMetrics.textSize, lineSpacing: 4, pairSpacing: 12,
                    sourceOrigin: origin.map {
                        LookupOrigin(language: model.languages?.source, definitionLanguage: $0.definitionLanguage)
                    },
                    targetOrigin: origin)
            } else {
                LookupText(
                    text: text, size: PanelMetrics.textSize, weight: .medium, justified: true, origin: origin)
            }
        }
    }

    /// Hugs the buttons, so the text beside them keeps its own clicks.
    private var actions: some View {
        HStack(spacing: 8) {
            // The operation's own button, on its own symbol: a generic refresh glyph said nothing about
            // which of the two operations it would run. Re-running the edited text is a new request, so
            // the old result's cache is gone either way.
            if !isBusy, !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // ⌘↩ belongs to the File menu's command, which runs the same request.
                CardButton(
                    title: model.operation.name, symbol: model.operation.symbol,
                    key: .process, bindsKey: false
                ) {
                    model.process(to: resolvedTarget)
                }
            }
            if isBusy {
                CardButton(title: "Cancel", symbol: "xmark", key: .cancel, action: model.cancel)
            }
            if case .success(let text) = model.state {
                CopyCardButton(title: "Copy Result", key: .copy) { text }
            }
        }
    }

    /// The learning column's toggle, at the leading edge. It opens and closes that column instead of
    /// acting on the result, so it is not part of the run-and-copy group at the trailing edge.
    private var learningAction: some View {
        HStack(spacing: 8) {
            if showsLearning {
                CardButton(title: "Back", symbol: "chevron.left", key: .learn) {
                    learning.isExpanded = false
                }
            } else if LearningRequest.from(model) != nil {
                CardButton(title: "Study", symbol: "lamp.desk", key: .learn) {
                    learning.isExpanded = true
                }
            }
        }
    }

    /// One state decides the column, so Back always closes it: the auto-request opens it by setting
    /// this, and nothing else can open it behind the user's back.
    private var showsLearning: Bool {
        LearningRequest.from(model) != nil && learning.isExpanded
    }

    private var resultText: String? {
        guard case .success(let text) = model.state else { return nil }
        return text
    }

    private var isBusy: Bool { model.state == .loading }
    private var resolvedTarget: String { SettingsStore.resolvedTarget(for: model.input) }

    private func reprocessForCurrentOptions() {
        learning.reset()
        if model.shouldReprocessOnOptionChange { model.process(to: resolvedTarget) }
    }
}
