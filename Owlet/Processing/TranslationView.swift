import AppKit
import SwiftUI

@MainActor @Observable
final class TranslationModel {
    enum State: Equatable {
        case idle
        case loading
        case success(String)
        case failure(String)
        case missingConfig
    }

    var input = "" {
        didSet {
            // A result belongs to the text it was computed from, so it is dropped the moment that
            // text changes: there is no cache across texts.
            if input != oldValue {
                results.removeAll()
                languages = nil
                segments = []
            }
        }
    }
    var operation: Operation = .translate
    private(set) var state: State = .idle
    /// Languages of the latest successful result, so a collected expression keeps its own language.
    private(set) var languages: (source: String, target: String)?
    /// Source/target pairs of the latest successful result, so 逐句对照 groups by the response's own
    /// pairing instead of guessing from punctuation or display lines.
    private(set) var segments: [TranslationResult.Segment] = []
    /// Results already computed for the current text, so switching the operation back and forth does
    /// not pay for the same request twice.
    private var results: [ResultKey: TranslationResult] = [:]

    private struct ResultKey: Hashable {
        let operation: Operation
        let language: String
    }
    private let client: ModelClient
    private let config: () -> ServiceConfig?
    private var operationID = 0
    private var task: Task<Void, Never>?
    /// True once a produced result still owes its one automatic learning decision; the claim below
    /// clears it, so a result the user has already seen is never retroactively requested.
    private var autoLearningPending = false

    /// Consumes the pending automatic learning decision for the newest result, returning true only
    /// for the first caller; the model keeps it so rebuilding a view cannot re-run an old request.
    func claimAutoLearningRequest() -> Bool {
        defer { autoLearningPending = false }
        return autoLearningPending
    }

    init(client: ModelClient, config: @escaping () -> ServiceConfig?) {
        self.client = client
        self.config = config
    }

    /// Cancels any in-flight translation and ignores its late result.
    func cancel() {
        task?.cancel()
        operationID += 1
        if state == .loading { state = .idle }
    }

    /// Shows an error that happened outside a translation request.
    func fail(_ message: String) {
        cancel()
        state = .failure(message)
    }

    /// Whether this text has already been sent to the model, which is when switching the operation
    /// should run it again rather than wait to be asked.
    var hasBeenSent: Bool {
        switch state {
        case .success, .failure, .missingConfig: true
        case .idle, .loading: false
        }
    }

    /// Starts the current operation; any in-flight one is cancelled and its result ignored. A result
    /// already computed for this text and this pair of settings is served from the cache instead.
    @discardableResult
    func translate(to targetLanguage: String) -> Task<Void, Never>? {
        task?.cancel()
        operationID += 1
        autoLearningPending = false
        let id = operationID
        let text = input
        let operation = operation
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            return nil
        }
        guard let config = config() else {
            state = .missingConfig
            return nil
        }
        let key = ResultKey(operation: operation, language: targetLanguage)
        if let ready = results[key] {
            // A finished task, so a caller that awaits the request behaves the same either way — the
            // panel's one-shot write-back has to reach the result whether it was computed or cached.
            state = .success(ready.text)
            languages = (ready.sourceLanguage, ready.targetLanguage)
            segments = ready.segments
            return Task {}
        }
        state = .loading
        let client = client
        let task = Task {
            let outcome: State
            var full: TranslationResult?
            do {
                let result = try await client.processResult(
                    text, operation: operation, to: targetLanguage, config: config)
                full = result
                outcome = .success(result.text)
            } catch let error as ModelError {
                outcome = .failure(error.message)
            } catch is CancellationError {
                return
            } catch {
                outcome = .failure(error.localizedDescription)
            }
            guard id == self.operationID else { return }
            if let full {
                self.results[key] = full
                self.languages = (full.sourceLanguage, full.targetLanguage)
                self.segments = full.segments
            }
            self.state = outcome
            if case .success = outcome { self.autoLearningPending = true }
        }
        self.task = task
        return task
    }
}

struct TranslationView: View {
    @Bindable var model: TranslationModel
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
                            model.translate(to: resolvedTarget)
                        }
                        .buttonStyle(.glassProminent)
                        .labelStyle(.iconOnly)
                        .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("\(model.operation.title)文本 ⌘↩")
                    }
                }
            }
            .onChange(of: model.operation) { _, _ in refreshResult() }
            .onChange(of: pinnedTarget) { _, _ in refreshResult() }
            .onChange(of: pinnedSource) { _, _ in refreshResult() }
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

    private func refreshResult() {
        learning.reset()
        if model.hasBeenSent { model.translate(to: resolvedTarget) }
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
                        model.translate(to: resolvedTarget)
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
