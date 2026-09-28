import AppKit
import SwiftUI

/// Expanded floating panel: header, scrollable source/result body, fixed action footer.
struct ExpandedPanel: View {
    @Bindable var model: TranslationModel
    /// Writes the result back to the original selection; nil when there is no source.
    let replace: ((String) -> Void)?
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
    @AppStorage(SettingsStore.targetLanguageKey) private var targetLanguage =
        SettingsStore.defaultTargetLanguage

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                operation: $model.operation,
                retry: canRetry ? retry : nil,
                openSettings: openSettings)
            Divider()
            ScrollView {
                PanelBody(
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
                retry: canRetry ? retry : nil,
                cancel: cancel)
        }
        .frame(width: PanelMetrics.width)
        // A new target language runs the same text again at once, like switching the operation;
        // a language already produced for this text comes from the model's cache.
        .onChange(of: targetLanguage) { _, _ in
            learning.reset()
            if canRetry { retry() }
        }
    }

    private var canRetry: Bool {
        model.state != .loading && !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Replaces the title bar the frameless panel lacks: logo, operation menu, retry, settings.
struct PanelHeader: View {
    @Binding var operation: Operation
    let retry: (() -> Void)?
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image("OwletMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Owlet")
                Picker("快捷操作", selection: $operation) {
                    ForEach(Operation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .fixedSize()
                .font(.system(size: 12, weight: .semibold))
                // Switching runs the same text again at once, so the two results can be compared
                // without pressing 重新处理. `retry` is nil while a request is running or the source
                // is blank, which is exactly when switching should do nothing — and it keeps the old
                // result from being labelled with the operation that did not produce it.
                .onChange(of: operation) { _, _ in retry?() }
                .disabled(retry == nil)
            }
            Spacer(minLength: 0)
            GlassEffectContainer {
                HStack(spacing: 6) {
                    if let retry {
                        ToolButton(title: "重新处理", systemImage: "arrow.clockwise", action: retry)
                    }
                    ToolButton(title: "打开设置", systemImage: "slider.horizontal.3", action: openSettings)
                }
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 8)
        .frame(height: 42)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}

private struct ToolButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .help(title)
    }
}

/// Source and result sections; the source stays editable so a retry can use revised text.
private struct PanelBody: View {
    @Bindable var model: TranslationModel
    let notice: PanelController.Notice?
    let recover: (PanelController.Notice) -> Void
    let collection: CollectionAction?
    let openNotebook: (() -> Void)?
    let learning: LearningModel
    @AppStorage(SettingsStore.targetLanguageKey) private var targetLanguage =
        SettingsStore.defaultTargetLanguage
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
        Picker("目标语言", selection: $targetLanguage) {
            ForEach(TranslationView.languages, id: \.0) { Text($0.1).tag($0.0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .fixedSize()
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

/// Fixed footer: the actions only, with copy and the single prominent action at the trailing end.
private struct PanelFooter: View {
    let state: TranslationModel.State
    let operation: Operation
    /// Idle because the user stopped processing; the main button then reads "重新处理".
    let cancelled: Bool
    let replace: ((String) -> Void)?
    let retry: (() -> Void)?
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            GlassEffectContainer {
                HStack(spacing: 6) { actions }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 45)
    }

    private func copy(_ text: String) {
        Clipboard.copy(text)
    }

    private var retryTitle: String {
        guard state == .idle else { return "重试" }
        return cancelled ? "重新处理" : operation.title
    }

    @ViewBuilder private var actions: some View {
        switch state {
        case .loading:
            Button("取消", action: cancel).buttonStyle(.glass)
        case .success(let text):
            Button {
                copy(text)
            } label: {
                Label("复制 ⌘⇧C", systemImage: "doc.on.doc")
            }
            .buttonStyle(.glass)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("复制结果 ⌘⇧C")
            if let replace {
                Button("替换 ⌘↩") { replace(text) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("替换原选区 ⌘↩")
            }
        default:
            if let retry {
                Button(retryTitle, action: retry)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel(retryTitle)
                    .help("\(retryTitle) ⌘↩")
            }
        }
    }
}
