import SwiftUI

/// Source and result sections; the source stays editable so a retry can use revised text.
struct ExpandedPanelContent: View {
    @Bindable var model: TextProcessingModel
    let notice: PanelController.Notice?
    let recover: (PanelController.Notice) -> Void
    let collection: CollectionAction?
    let openNotebook: (() -> Void)?
    let learning: LearningModel
    /// The pinned target language; an empty value means 自动.
    @AppStorage(SettingsStore.pinnedTargetKey) private var pinnedTarget = ""
    @AppStorage(SettingsStore.displayModeKey) private var displayMode =
        TranslationDisplayMode.sectioned
    /// While 逐句对照 shows the response pairs, the source field is folded into them and only
    /// 编辑原文 brings it back for a retry.
    @State private var editingSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !showsAlignedPairs || editingSource {
                sourceEditor.padding(.bottom, 12)
            }
            if hasResultSection {
                Divider()
                resultSection.padding(.top, 12)
            }
            status
        }
        .padding(.horizontal, 17)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 7) {
            LabelRow {
                Text("自动识别")
            } trailing: {
                Text("原文")
            }
            TextField("原文", text: $model.input, axis: .vertical)
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineSpacing(4)
                .lineLimit(1...5)
        }
    }

    /// Only a finished result has pairs to group; a run in progress still shows the source field.
    private var showsAlignedPairs: Bool {
        guard displayMode == .aligned, case .success = model.state else { return false }
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
            LabelRow {
                if model.state == .loading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("\(model.operation.title)中")
                    }
                } else if displayMode == .aligned {
                    Text("逐句对照")
                } else {
                    Text(model.operation == .polish ? "润色结果" : "译文")
                }
            } trailing: {
                if model.operation == .polish { Text("保留原意") } else { languagePicker }
            }
            if case .success(let text) = model.state {
                if showsAlignedPairs {
                    AlignedSegments(
                        segments: model.segments, sourceSize: 12, targetSize: 13,
                        lineSpacing: 4, pairSpacing: 12)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Button(editingSource ? "收起原文" : "编辑原文") { editingSource.toggle() }
                            .buttonStyle(.glass)
                    }
                } else {
                    Text(text)
                        .font(.system(size: 13))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let collection, let request = LearningRequest.from(model) {
                    LearningView(
                        learning: learning, request: request, collection: collection,
                        openNotebook: openNotebook)
                }
            } else {
                Text(model.input)
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .lineLimit(2)
                    .redacted(reason: .placeholder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("正在生成结果")
            }
        }
    }

    @ViewBuilder private var status: some View {
        if let notice {
            StatusNote(symbol: notice != .cancelled ? "exclamationmark.triangle" : "info.circle") {
                Text(notice.message)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                GlassEffectContainer {
                    Button(notice.actionTitle) { recover(notice) }.buttonStyle(.glass)
                }
            }
        }
    }

    private var languagePicker: some View {
        TargetLanguagePicker(text: model.input, pinnedTarget: $pinnedTarget)
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            // Changing it mid-request would label the running result with a language it was not made for.
            .disabled(model.state == .loading)
    }
}

/// Section caption: muted label left, secondary meta right.
private struct LabelRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(minHeight: 16)
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
