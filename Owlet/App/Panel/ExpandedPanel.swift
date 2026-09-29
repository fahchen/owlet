import AppKit
import SwiftUI

/// Expanded floating panel: header, scrollable source/result body, fixed action footer.
struct ExpandedPanel: View {
    @Bindable var model: TextProcessingModel
    /// Writes the result back to the original selection; nil when there is no source.
    let replace: ((String) -> Void)?
    /// Copies the result; the panel closes afterwards, so a copy is one finished interaction.
    let copy: (String) -> Void
    /// Nil when the panel was built without the notebook, which the tests do.
    let collection: CollectionAction?
    let openNotebook: (() -> Void)?
    let notice: PanelController.Notice?
    let recover: (PanelController.Notice) -> Void
    let retry: () -> Void
    let cancel: () -> Void
    let openSettings: () -> Void
    /// One learning section per panel session, so 收起／展开 reuses what was already generated.
    @State private var learning = LearningModel()
    /// The pinned target language; an empty value means 自动.
    @AppStorage(SettingsStore.pinnedTargetKey) private var pinnedTarget = ""

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                operation: $model.operation,
                retry: canRetry ? retry : nil,
                openSettings: openSettings)
            Divider()
            ScrollView {
                ExpandedPanelContent(
                    model: model, notice: notice, recover: recover,
                    collection: collection, openNotebook: openNotebook, learning: learning)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 440)
            .layoutPriority(-1)
            Divider()
            PanelFooter(
                state: model.state,
                operation: model.operation,
                cancelled: notice == .cancelled,
                replace: replace,
                copy: copy,
                retry: canRetry ? retry : nil,
                cancel: cancel)
        }
        .frame(width: PanelMetrics.width)
        // A pinned target runs the same text again at once, like switching the operation; a language
        // already produced for this text comes from the model's cache.
        .onChange(of: pinnedTarget) { _, _ in
            learning.reset()
            if canRetry { retry() }
        }
    }

    private var canRetry: Bool {
        model.state != .loading && !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
