import SwiftUI
import SwiftData

struct ExpandedPanel: View {
    @AppStorage(SettingsStore.panelGlassEffectKey) private var glassEffect = PanelGlassEffect.contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: TextProcessingModel
    let replace: ((String) -> Void)?
    let copy: (String) -> Void
    let collection: CollectionAction?
    let openNotebook: (() -> Void)?
    let notice: PanelController.Notice?
    let recover: (PanelController.Notice) -> Void
    let retry: () -> Void
    let cancel: () -> Void
    let openSettings: () -> Void
    let close: () -> Void
    let lookupOrigin: LookupOrigin?
    var screenshotSpace: Namespace.ID?
    var screenshotZoomed = false
    var toggleScreenshotZoom: () -> Void = {}
    @State var learning = LearningModel()
    /// Natural height of the text column; the panel hugs it up to `maxHeight`, then scrolls.
    @State private var contentHeight: CGFloat = 0
    /// Height the learning column asks for; until it is measured, the former fixed height.
    @State private var learningHeight: CGFloat = 295
    /// The translation's height when learning opened, which the learning column tries to keep.
    @State private var learningEntryHeight: CGFloat = 0
    private static let maxHeight: CGFloat = 480
    @AppStorage(SettingsStore.pinnedTargetKey) private var pinnedTarget = ""

    private var fullHeight: CGFloat { showsLearning ? learningHeight : translationHeight }

    private var translationHeight: CGFloat {
        min(
            max(contentHeight + PanelMetrics.contentInset * 2, PanelMetrics.sourceBarHeight),
            Self.maxHeight)
    }

    /// One state decides the column, so Back always closes it: the items are kept, and Study shows
    /// them again without a second request.
    private var showsLearning: Bool {
        LearningRequest.from(model) != nil && learning.isExpanded
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    ExpandedPanelContent(
                        model: model, notice: notice, recover: recover,
                        collection: collection, openNotebook: openNotebook, learning: learning,
                        lookupOrigin: lookupOrigin, showsSource: !showsLearning,
                        screenshotSpace: screenshotSpace, screenshotZoomed: screenshotZoomed,
                        toggleScreenshotZoom: toggleScreenshotZoom
                    )
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
                    // Beside the learning column the buttons sit on the right, so this side needs no room.
                    .panelBottomPadding(besideActions: !showsLearning)
                }
                .scrollBounceBehavior(.basedOnSize)
                .panelEdgeBands()
                .frame(maxWidth: .infinity)
                if showsLearning, let collection, let request = LearningRequest.from(model) {
                    Divider()
                        .padding(.vertical, PanelMetrics.contentInset)
                    PanelLearningView(
                        learning: learning, request: request, collection: collection,
                        preferredHeight: learningEntryHeight
                    )
                    .modelContainer(collection.store.container)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { learningHeight = $0 }
                    .frame(width: PanelMetrics.width / 2)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(height: fullHeight)
            // Hugs the buttons: a full-width row would take every click beside them, over the
            // text and the learning items it floats on. The ZStack puts it bottom-trailing.
            HStack(spacing: 8) {
                if model.state == .loading {
                    Button(action: cancel) {
                        Label(L10n.shared.string("Cancel"), systemImage: "xmark").foregroundStyle(.primary)
                    }
                    .labelStyle(.iconOnly).buttonStyle(.glass(glassEffect.glass))
                    .hoverTip(KeyHint.panelCancel, title: "Cancel")
                }
                if showsLearning {
                    Button {
                        learning.isExpanded = false
                    } label: {
                        Label(L10n.shared.string("Back"), systemImage: "chevron.left").foregroundStyle(.primary)
                    }
                    .labelStyle(.iconOnly).font(.system(size: 13, weight: .medium))
                    .buttonStyle(.glass(glassEffect.glass)).buttonBorderShape(.circle).controlSize(.extraLarge)
                    .buttonSizing(.flexible).frame(width: 36, height: 36)
                    .keyboardShortcut(KeyHint.panelLearn.shortcut)
                    .hoverTip(KeyHint.panelLearn, title: "Back to Result")
                } else if LearningRequest.from(model) == nil || collection == nil {
                    Button(action: close) {
                        Label(L10n.shared.string("Off"), systemImage: "xmark").foregroundStyle(.primary)
                    }
                    .labelStyle(.iconOnly).font(.system(size: 13, weight: .medium))
                    .buttonStyle(.glass(glassEffect.glass)).buttonBorderShape(.circle).controlSize(.extraLarge)
                    .buttonSizing(.flexible).frame(width: 36, height: 36)
                    .hoverTip(KeyHint.panelCancel, title: "Close Panel")
                } else {
                    Button {
                        learning.isExpanded = true
                    } label: {
                        Label(L10n.shared.string("Study"), systemImage: "lamp.desk").foregroundStyle(.primary)
                    }
                    .labelStyle(.iconOnly).font(.system(size: 13, weight: .medium))
                    .buttonStyle(.glass(glassEffect.glass)).buttonBorderShape(.circle).controlSize(.extraLarge)
                    .buttonSizing(.flexible).frame(width: 36, height: 36)
                    .keyboardShortcut(KeyHint.panelLearn.shortcut)
                    .hoverTip(KeyHint.panelLearn, title: "Study Expressions")
                }
                if case .success(let text) = model.state {
                    Button {
                        copy(text)
                    } label: {
                        Label(L10n.shared.string("Copy"), systemImage: "document.on.document").foregroundStyle(.primary)
                    }
                    .labelStyle(.iconOnly).font(.system(size: 13, weight: .medium))
                    .buttonStyle(.glass(glassEffect.glass)).buttonBorderShape(.circle).controlSize(.extraLarge)
                    .buttonSizing(.flexible).frame(width: 36, height: 36)
                    // ⌘C reaches the panel's key monitor, which leaves selected text to the system copy.
                    .hoverTip(KeyHint.panelCopy)
                }
            }
            .padding(.trailing, PanelMetrics.contentInset)
            .padding(.bottom, PanelMetrics.contentInset)
        }
        .contextMenu {
            Picker(L10n.shared.string("Shortcuts"), selection: $model.operation) {
                ForEach(Operation.allCases, id: \.self) { Text(verbatim: L10n.shared.string($0.title.key)).tag($0) }
            }
            .onChange(of: model.operation) { _, _ in if canRetry { retry() } }
            .disabled(!canRetry)
            if model.operation == .translate {
                TargetLanguagePicker(text: model.input, pinnedTarget: $pinnedTarget)
                    .disabled(model.state == .loading)
            }
            Button(L10n.shared.string("Try Again"), systemImage: "arrow.clockwise", action: retry)
                .keyboardShortcut(KeyHint.panelRetry.shortcut)
                .disabled(!canRetry)
            if case .success(let text) = model.state, let replace {
                Button(L10n.shared.string("Replace Selection")) { replace(text) }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            Button(action: close) { Label(L10n.shared.string("Off"), systemImage: "xmark").foregroundStyle(.primary) }
            Button(L10n.shared.string("Settings"), systemImage: "gearshape", action: openSettings)
        }
        // No glass of its own: the panel root's surface draws it, the same surface the source bar
        // sat on, so expanding grows that surface instead of replacing it.
        .frame(width: PanelMetrics.width, height: fullHeight, alignment: .top)
        .animation(reduceMotion ? nil : .spring(duration: 0.36, bounce: 0.12), value: showsLearning)
        .animation(reduceMotion ? nil : .spring(duration: 0.36, bounce: 0.12), value: contentHeight)
        .animation(reduceMotion ? nil : .spring(duration: 0.36, bounce: 0.12), value: learningHeight)
        // The text keeps its own clicks; any other press on the glass moves the panel.
        .gesture(WindowDragGesture())
        // Read before the left column relays out for learning, so it is still the translation's height.
        .onChange(of: showsLearning) { _, shows in
            guard shows else { return }
            learningEntryHeight = translationHeight
            learningHeight = translationHeight
        }
        // The auto-request switch is checked by the panel itself, both when a result arrives and when the
        // panel opens on one: a hidden learning view meant to do it was never laid out, so it never ran.
        .onAppear { requestLearningIfAutomatic() }
        .onChange(of: model.state) { _, state in
            if state == .loading { learning.reset() } else { requestLearningIfAutomatic() }
        }
        .onChange(of: pinnedTarget) { _, _ in
            learning.reset()
            if canRetry { retry() }
        }
    }

    /// Opens Study on a finished result when its switch is on; the model hands out that decision once.
    private func requestLearningIfAutomatic() {
        guard collection != nil, let request = LearningRequest.from(model) else { return }
        learning.generateIfAutoRequested(for: request)
    }

    private var canRetry: Bool {
        model.state != .loading && !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension View {
    /// The panel's top padding as a band on a scroll view: content rests clear of it, scrolls under
    /// it, and fades out at both edges with no material, so the glass stays bright; the band stays
    /// free to drag the panel by. The bottom padding is the content's own (`panelBottomPadding`): a
    /// scroll view does not deliver clicks to content lying in its bottom inset or content margin,
    /// which is exactly where the last item and the end of the text sit beside the buttons.
    func panelEdgeBands() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { PanelDragBand(height: PanelMetrics.contentInset) }
            // Outside the insets, so the fade spans the panel's edges rather than the safe area,
            // which would fade the first and last lines at rest.
            .panelEdgeFade()
    }

    /// Fades scrolling content out over the top and bottom inset, with no material, so the glass
    /// stays bright where the text passes under the padding.
    func panelEdgeFade() -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: PanelMetrics.contentInset)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: PanelMetrics.contentInset)
            }
        }
        .scrollEdgeEffectHidden(true, for: .vertical)
    }

    /// Bottom padding inside scroll content: the inset, plus, beside the floating buttons, room to
    /// scroll the content out from under them. The panel adds no blank space for the buttons at rest.
    func panelBottomPadding(besideActions: Bool = true) -> some View {
        padding(.bottom, PanelMetrics.contentInset + (besideActions ? PanelMetrics.actionRoom : 0))
    }
}

/// Empty, but hit-testable, so a press on it moves the panel instead of reaching the content.
private struct PanelDragBand: View {
    let height: CGFloat

    var body: some View {
        Color.clear
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
    }
}
