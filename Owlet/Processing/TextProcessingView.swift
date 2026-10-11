import SwiftUI

/// The 翻译 and 润色 pages: one glass card with the source on the left and the result on the right,
/// switched by the toolbar's operation control. 学习 shows the result beside its learning items.
struct TextProcessingView: View {
    @Bindable var model: TextProcessingModel
    let openSettings: () -> Void
    let collection: CollectionAction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Injectable, so a preview can show fixture items instead of requesting a model.
    @State var learning = LearningModel()
    /// Set by 返回: keeps an auto-requested result from reopening the learning column.
    @State private var learningDismissed = false
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
            // A reset starts a new result, whose learning may open on its own again.
            .onChange(of: learning.state) { _, state in
                if state == .idle { learningDismissed = false }
            }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Operation", selection: $model.operation) {
                ForEach(Operation.allCases, id: \.self) { operation in
                    Image(nsImage: segmentSymbol(operation)).tag(operation)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(isBusy)
            .hoverTip(
                "\(KeyHint.translateMode.title) \(KeyHint.translateMode.keys)　\(KeyHint.polishMode.title)",
                keys: KeyHint.polishMode.keys)
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
                accessibilityLabel: String(localized: "\(operation.title)"),
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
            .accessibilityLabel("Source")
            .overlay(alignment: .topLeading) {
                if model.input.isEmpty {
                    // The page has no submit button; the placeholder names the shortcut instead.
                    Text(model.operation.placeholder)
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
            Text(model.operation.progress)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let message, let kind):
            failure(message, action: kind == .contract ? "Prompt Settings" : "Service Settings")
        case .missingConfig:
            failure(
                String(localized: "The model service is not configured"),
                action: String(localized: "Configure Service"))
        case .idle, .success:
            resultScroll
        }
    }

    private func failure(_ message: String, action: String) -> some View {
        VStack(spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            Button(action, systemImage: "gearshape", action: openSettings).buttonStyle(.plain)
        }
        .padding(.horizontal, PanelMetrics.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        if case .success(let text) = model.state {
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
            // Runs the current text again: after an edit it is a new request, the old result's cache gone.
            if !isBusy, !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // ⌘↩ belongs to the File menu's command, which runs the same request.
                CardButton(
                    title: String(localized: model.operation.retry), symbol: "arrow.clockwise",
                    key: .process, bindsKey: false
                ) {
                    model.process(to: resolvedTarget)
                }
            }
            if isBusy {
                CardButton(title: "Cancel", symbol: "xmark", key: .cancel, action: model.cancel)
            }
            if showsLearning {
                CardButton(title: "Back", symbol: "chevron.left", key: .learn) {
                    learning.isExpanded = false
                    learningDismissed = true
                }
            } else if LearningRequest.from(model) != nil {
                CardButton(title: "Study", symbol: "lamp.desk", key: .learn) {
                    learning.isExpanded = true
                }
            }
            if case .success(let text) = model.state {
                CardButton(title: "Copy Result", symbol: "document.on.document", key: .copy, bindsKey: false) {
                    Clipboard.copy(text)
                }
            }
        }
    }

    private var showsLearning: Bool {
        LearningRequest.from(model) != nil
            && (learning.isExpanded || (learning.state != .idle && !learningDismissed))
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
