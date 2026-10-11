import SwiftUI

/// Source and result sections; the source stays editable so a retry can use revised text.
struct ExpandedPanelContent: View {
    @Bindable var model: TextProcessingModel
    let notice: PanelController.Notice?
    let recover: (PanelController.Notice) -> Void
    let collection: CollectionAction?
    let openNotebook: (() -> Void)?
    let learning: LearningModel
    let lookupOrigin: LookupOrigin?
    var showsSource = true
    /// The pinned target language; an empty value means 自动.
    @AppStorage(SettingsStore.displayModeKey) private var displayMode =
        TranslationDisplayMode.sectioned
    /// While 逐句对照 shows the response pairs, the source field is folded into them and only
    /// 编辑原文 brings it back for a retry.
    @State private var editingSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsSource && (!showsAlignedPairs || editingSource) {
                sourceEditor.padding(.bottom, 12)
            }
            if hasResultSection {
                if showsSource { Divider() }
                resultSection.padding(.top, showsSource ? 12 : 0)
            }
            status
        }
        .padding(.horizontal, PanelMetrics.contentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fontWeight(PanelMetrics.textWeight)
        // A learning result describes one specific result, so changing the operation discards it,
        // and a finished result collapses the source field back into the pairs.
        .onChange(of: model.operation) { _, _ in
            learning.reset()
            editingSource = false
        }
        .onChange(of: model.input) { _, _ in learning.reset() }
        .onChange(of: showsAlignedPairs) { _, _ in editingSource = false }
    }

    private var sourceEditor: some View {
        // A vertical TextField hugs its text, so the gap above the divider matches the one below it.
        TextField("Source", text: $model.input, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: PanelMetrics.sourceTextSize))
            .fontWeight(PanelMetrics.sourceWeight)
            .lineSpacing(2)
    }

    /// Only a finished result has pairs to group; a run in progress still shows the source field.
    private var showsAlignedPairs: Bool {
        guard showsSource && displayMode == .aligned, case .success = model.state else { return false }
        return !model.segments.isEmpty
    }

    private var hasResultSection: Bool {
        switch model.state {
        case .loading, .success: true
        default: false
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            if model.state == .loading {
                ProgressView(model.operation.progress).controlSize(.small)
            }
            if case .success(let text) = model.state {
                if showsAlignedPairs {
                    AlignedSegments(
                        segments: model.segments, sourceSize: PanelMetrics.sourceTextSize,
                        targetSize: PanelMetrics.textSize,
                        lineSpacing: 4, pairSpacing: 12,
                        sourceOrigin: lookupOrigin.map {
                            LookupOrigin(language: model.languages?.source, definitionLanguage: $0.definitionLanguage)
                        },
                        targetOrigin: lookupOrigin)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Button(editingSource ? "Hide Source" : "Edit Source") { editingSource.toggle() }
                            .buttonStyle(.glass)
                    }
                } else {
                    // Beside learning the result is justified, as the main window's result is.
                    LookupText(
                        text: text, size: PanelMetrics.textSize, weight: .medium,
                        justified: !showsSource, origin: lookupOrigin
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

            } else {
                Text(model.input)
                    .font(.system(size: PanelMetrics.textSize))
                    .lineSpacing(2)
                    .lineLimit(2)
                    .redacted(reason: .placeholder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Generating the result")
            }
        }
    }

    @ViewBuilder private var status: some View {
        if let notice {
            StatusNote(
                symbol: notice != .cancelled ? "exclamationmark.triangle" : "info.circle",
                tint: notice == .cancelled ? .secondary : .red
            ) {
                Text(notice.message)
                    .font(.system(size: PanelMetrics.textSize))
                    .foregroundStyle(notice == .cancelled ? Color.primary : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                GlassEffectContainer {
                    Button(notice.actionTitle) { recover(notice) }.buttonStyle(.glass)
                }
            }
        }
    }

}

/// In-content status: symbol and message left, recovery entry right.
private struct StatusNote<Content: View>: View {
    var symbol = "exclamationmark.triangle"
    var tint: Color = .secondary
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.top, 10)
        .accessibilityElement(children: .contain)
    }
}
