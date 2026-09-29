import SwiftUI

struct TextProcessingView: View {
    @Bindable var model: TextProcessingModel
    let openSettings: () -> Void
    let collection: CollectionAction
    let openNotebook: () -> Void
    @State private var learning = LearningModel()
    @State private var contentWidth: CGFloat = 0
    @AppStorage(SettingsStore.pinnedTargetKey) private var pinnedTarget = ""
    @AppStorage(SettingsStore.pinnedSourceKey) private var pinnedSource = ""
    @AppStorage(SettingsStore.displayModeKey) private var displayMode = TranslationDisplayMode.sectioned

    var body: some View {
        pageContent
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                contentWidth = $0
            }
            .padding(24)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("处理方式", selection: $model.operation) {
                        ForEach(Operation.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(isBusy)
                }
                ToolbarItem(placement: .primaryAction) {
                    if isBusy {
                        Button("取消", systemImage: "stop.fill", action: model.cancel)
                            .labelStyle(.iconOnly)
                            .help("停止处理")
                    } else {
                        Button(model.operation.title, systemImage: model.operation.symbol) {
                            model.process(to: resolvedTarget)
                        }
                        .buttonStyle(.glassProminent)
                        .labelStyle(.iconOnly)
                        .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("\(model.operation.title)文本 ⌘↩")
                    }
                }
            }
            .onChange(of: model.operation) { _, _ in reprocessForCurrentOptions() }
            .onChange(of: pinnedTarget) { _, _ in reprocessForCurrentOptions() }
            .onChange(of: pinnedSource) { _, _ in reprocessForCurrentOptions() }
            .onChange(of: model.input) { _, _ in learning.reset() }
            .onChange(of: model.state) { _, state in
                if state == .loading { learning.reset() }
                if let request = LearningRequest.from(model) {
                    learning.generateIfAutoRequested(for: request)
                }
            }
    }

    @ViewBuilder private var pageContent: some View {
        if ProcessingLayout.choose(width: contentWidth) == .sideBySide {
            workspace
        } else {
            // Both editors and learning must remain reachable at the window's minimum height.
            ScrollView { workspace }
        }
    }

    private var workspace: some View {
        VStack(spacing: 16) {
            layout
            GroupBox {
                if let request = LearningRequest.from(model) {
                    LearningView(
                        learning: learning, request: request, collection: collection,
                        openNotebook: openNotebook)
                } else {
                    DisclosureGroup {
                        Text("完成翻译或润色后，即可学习词汇与表达。")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("学习", systemImage: "lightbulb.fill")
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    }
                    .disabled(true)
                    .help("完成翻译或润色后可用")
                }
            }
            .glassEffect(.regular, in: ContainerRelativeShape())
            .padding(.top, 8)
        }
    }

    private var isBusy: Bool { model.state == .loading }
    private var resolvedTarget: String { SettingsStore.resolvedTarget(for: model.input) }
    private var result: String? {
        if case .success(let text) = model.state { return text }
        return nil
    }

    private func reprocessForCurrentOptions() {
        learning.reset()
        if model.shouldReprocessOnOptionChange { model.process(to: resolvedTarget) }
    }

    @ViewBuilder private var layout: some View {
        if ProcessingLayout.choose(width: contentWidth) == .sideBySide {
            HSplitView {
                sourcePane.frame(minWidth: 280)
                resultPane.frame(minWidth: 280)
            }
            .padding(.top, 1)
        } else {
            VStack(spacing: 16) {
                sourcePane; resultPane
            }
        }
    }

    private var sourcePane: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("原文").font(.headline)
                    Spacer(minLength: 8)
                    SourceLanguagePicker(text: model.input, pinnedSource: $pinnedSource)
                        .opacity(model.operation == .translate ? 1 : 0)
                        .allowsHitTesting(model.operation == .translate)
                        .disabled(model.operation != .translate)
                        .accessibilityHidden(model.operation != .translate)
                }
                TextEditor(text: $model.input)
                    .textEditorStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 17))
                    .accessibilityLabel("原文")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Text("\(model.input.count) 字符").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("清空原文", systemImage: "trash") {
                        model.cancel()
                        model.input = ""
                        model.process(to: resolvedTarget)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .help("清空原文")
                    .disabled(model.input.isEmpty)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 260)
        .glassEffect(.regular, in: ContainerRelativeShape())
    }

    private var resultPane: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text(model.operation == .translate ? "译文" : "结果").font(.headline)
                    Spacer(minLength: 8)
                    TargetLanguagePicker(text: model.input, pinnedTarget: $pinnedTarget)
                        .opacity(model.operation == .translate ? 1 : 0)
                        .allowsHitTesting(model.operation == .translate)
                        .disabled(model.operation != .translate)
                        .accessibilityHidden(model.operation != .translate)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if isBusy {
                            ProgressView("\(model.operation.title)中…")
                        } else if let result {
                            if displayMode == .aligned, !model.segments.isEmpty {
                                AlignedSegments(
                                    segments: model.segments, sourceSize: 16, targetSize: 17,
                                    lineSpacing: 7, pairSpacing: 14)
                            } else {
                                Text(result).font(.system(size: 18)).lineSpacing(8).textSelection(.enabled)
                            }
                        }
                        status
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Spacer()
                    Button("复制结果", systemImage: "doc.on.doc") {
                        if let result { Clipboard.copy(result) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .help("复制结果 ⌘⇧C")
                    .disabled(result == nil || isBusy)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 260)
        .glassEffect(.regular, in: ContainerRelativeShape())
    }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .failure(let message): StatusNote(message: message, action: "服务设置", perform: openSettings)
        case .missingConfig: StatusNote(message: "模型服务未配置", action: "配置服务", perform: openSettings)
        default: EmptyView()
        }
    }
}

private struct StatusNote: View {
    let message: String
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle")
            Spacer(minLength: 0)
            Button(action, action: perform).buttonStyle(.glass)
        }
    }
}
