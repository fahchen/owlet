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
    /// The pinned target language; an empty value means Automatic.
    @AppStorage(SettingsStore.displayModeKey) private var displayMode =
        TranslationDisplayMode.sectioned
    @State private var confirmation = CopyConfirmation()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsSource, let screenshot = model.sourceThumbnail {
                Image(nsImage: screenshot)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160, alignment: .leading)
                    .accessibilityLabel(L10n.shared.string("Screenshot"))
                    .padding(.bottom, 12)
            }
            if showsSource && !showsAlignedPairs {
                sourceEditor.padding(.bottom, 12)
            }
            if hasResultSection {
                // The rule separates the editable source from the result, so it belongs with the source
                // field: once Sentence by Sentence folds that field away it has nothing above it to separate, and
                // it was left stranded above the pairs.
                if showsSource && !showsAlignedPairs { Divider() }
                resultSection.padding(.top, showsSource ? 12 : 0)
            }
            status
        }
        .padding(.horizontal, PanelMetrics.contentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fontWeight(PanelMetrics.textWeight)
        // A learning result describes one specific result, so changing the operation discards it,
        // and a finished result collapses the source field back into the pairs.
        .onChange(of: model.operation) { _, _ in learning.reset() }
        .onChange(of: model.input) { _, _ in learning.reset() }
    }

    private var sourceEditor: some View {
        // A vertical TextField hugs its text, so the gap above the divider matches the one below it.
        TextField(L10n.shared.string("Source"), text: $model.input, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: PanelMetrics.sourceTextSize))
            .fontWeight(PanelMetrics.sourceWeight)
            .lineSpacing(2)
    }

    /// A grouped display folds the source field away, because the pairs carry the source themselves;
    /// that holds while the reply is arriving too, so Sentence by Sentence shows the source once and the
    /// pairs are not pushed below a source field the finished result would not have.
    private var showsAlignedPairs: Bool {
        showsSource && displayMode == .aligned && !model.displayPairs.isEmpty
    }

    private var hasResultSection: Bool {
        switch model.state {
        case .loading, .success: true
        default: false
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            if case .success(let text) = model.state, model.revealed.isEmpty {
                if showsAlignedPairs {
                    AlignedSegments(
                        segments: model.segments, sourceSize: PanelMetrics.sourceTextSize,
                        targetSize: PanelMetrics.textSize,
                        lineSpacing: 4, pairSpacing: 12,
                        sourceOrigin: lookupOrigin.map {
                            LookupOrigin(language: model.languages?.source, definitionLanguage: $0.definitionLanguage)
                        },
                        targetOrigin: lookupOrigin)
                } else {
                    // Beside learning the result is justified, as the main window's result is.
                    LookupText(
                        text: text, size: PanelMetrics.textSize, weight: .medium,
                        justified: !showsSource, origin: lookupOrigin
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if !model.revealed.isEmpty {
                // The arrival grows in the layout the display setting gives the finished result, and
                // word by word within a pair, so what the user reads is the shape they will keep and
                // the pace shows that more is coming (BDR-0017). A validated reply keeps showing the
                // last of its words here until the display has caught up, and then the finished
                // result above takes over — with its lookups, which arriving text never offers.
                ReceivingResult(
                    segments: model.revealed, mode: displayMode, justified: !showsSource)
            } else {
                Text(model.input)
                    .font(.system(size: PanelMetrics.textSize))
                    .lineSpacing(2)
                    .lineLimit(2)
                    .redacted(reason: .placeholder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(L10n.shared.string("Generating the result"))
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
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The words of a failure are quoted back rather than spoken over: the same inset a
                    // captured body gets on the Debug page, without its guide — this is a message, not
                    // someone else's text — and the symbol above carries the red.
                    .failureBlock()
                GlassEffectContainer {
                    // A copy names itself after the press, so the button never looks like it did nothing.
                    // A notice that offers no entry (receiving) shows as words alone.
                    if !notice.actionTitle.isEmpty {
                        Button(confirmation.isCopied ? L10n.shared.string("Copied") : notice.actionTitle) {
                            recover(notice)
                            if notice.copiesOnPress { confirmation.confirm() }
                        }
                        .buttonStyle(.glass)
                    }
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
        // The same shape as the system's "nothing here" pages: symbol, words, action, centered — a
        // failure should read as a state of the panel, not as a line of text beside an icon.
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            content
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(PanelMetrics.contentInset)
        .accessibilityElement(children: .contain)
    }
}
