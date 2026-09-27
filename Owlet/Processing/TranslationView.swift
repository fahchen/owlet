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

/// Main-window 文本处理 page (design/screenshots/workspace.png): target language and
/// operation in the window toolbar, editable source, result, and a fixed action footer.
struct TranslationView: View {
    @Bindable var model: TranslationModel
    /// Shows the 设置 page for service errors.
    let openSettings: () -> Void
    let collection: CollectionAction
    let openNotebook: () -> Void
    /// One learning section per page session, so 收起／展开 reuses what was already generated.
    @State private var learning = LearningModel()
    /// Measured content width, which decides side by side versus stacked.
    @State private var contentWidth: CGFloat = 0
    @AppStorage(SettingsStore.targetLanguageKey) private var targetLanguage =
        SettingsStore.defaultTargetLanguage
    @AppStorage(SettingsStore.displayModeKey) private var displayMode =
        TranslationDisplayMode.sectioned

    static let languages = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "English"), ("ja", "日本語"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
                if showsResult, result != nil { learningSection }
                status
            }
            // Measured before the page padding, so 720pt is the content area, not the whole window.
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                contentWidth = $0
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) { footer }
        .navigationTitle("文本处理")
        // Switching the operation runs the same text again at once, so the two results can be
        // compared without pressing the button a second time. Switching back is served from cache.
        .onChange(of: model.operation) { _, _ in
            learning.reset()
            if model.hasBeenSent { model.translate(to: targetLanguage) }
        }
        // A new target language runs the same text again, served from cache when already produced.
        .onChange(of: targetLanguage) { _, _ in
            learning.reset()
            if model.hasBeenSent { model.translate(to: targetLanguage) }
        }
        // The source text changed, so the old result and its learning items no longer apply.
        .onChange(of: model.input) { _, _ in learning.reset() }
        .toolbar {
            if model.operation == .translate {
                ToolbarItem(placement: .primaryAction) { languagePicker.disabled(isBusy) }
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("处理方式", selection: $model.operation) {
                    ForEach(Operation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(isBusy)
            }
        }
    }

    private var isBusy: Bool { model.state == .loading }

    private var result: String? {
        if case .success(let text) = model.state { return text }
        return nil
    }

    /// Mirrors the prototype: before the first result the page is a plain input.
    private var showsResult: Bool { isBusy || result != nil }

    /// Source and result side by side once the content area is wide enough, stacked otherwise.
    @ViewBuilder private var content: some View {
        if showsResult {
            switch ProcessingLayout.choose(width: contentWidth) {
            case .sideBySide: sideBySide
            case .stacked: stacked
            }
        } else {
            sourceColumn
        }
    }

    private var sideBySide: some View {
        HStack(alignment: .top, spacing: 0) {
            sourceColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 28)
            Divider()
            resultColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.leading, 28)
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            sourceColumn.padding(.bottom, 21)
            Divider().padding(.bottom, 13)
            resultColumn
        }
    }

    private var sourceColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabelRow {
                Text(showsResult ? "自动识别" : "输入文本")
            } trailing: {
                Text(showsResult ? "原文" : "⌘ V 粘贴")
            }
            TextEditor(text: $model.input)
                .textEditorStyle(.plain)
                .font(.system(size: 16))
                .lineSpacing(7)
                .frame(height: 110)
                // Cancels NSTextView's line fragment padding so text aligns with the labels.
                .padding(.horizontal, -5)
                .overlay(alignment: .topLeading) {
                    if model.input.isEmpty {
                        Text("输入或粘贴要处理的文本…")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("原文")
        }
    }

    private var resultColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabelRow {
                if isBusy {
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
                if model.operation == .translate {
                    Text(Self.languages.first { $0.0 == targetLanguage }?.1 ?? targetLanguage)
                } else {
                    Text("保留原意")
                }
            }
            resultBody
        }
    }

    @ViewBuilder private var resultBody: some View {
        Group {
            if let result {
                if displayMode == .aligned, !model.segments.isEmpty {
                    AlignedSegments(
                        segments: model.segments, sourceSize: 16, targetSize: 17,
                        lineSpacing: 7, pairSpacing: 14)
                } else {
                    Text(result)
                        .font(.system(size: 17))
                        .lineSpacing(8)
                        .textSelection(.enabled)
                }
            } else {
                Text(model.input)
                    .font(.system(size: 17))
                    .lineSpacing(8)
                    .lineLimit(2)
                    .redacted(reason: .placeholder)
                    .accessibilityLabel("正在生成结果")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder private var learningSection: some View {
        if let request = LearningRequest.from(model) {
            LearningView(
                learning: learning, request: request, collection: collection,
                openNotebook: openNotebook)
        }
    }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .failure(let message): StatusNote(message: message, action: "服务设置", perform: openSettings)
        case .missingConfig: StatusNote(message: "模型服务未配置", action: "配置服务", perform: openSettings)
        default: EmptyView()
        }
    }

    private var footer: some View {
        PageFooter {
            if isBusy { Text("处理中") }
        } trailing: {
            if isBusy {
                Button("取消", action: model.cancel).buttonStyle(.glass)
            } else {
                Button {
                    guard let result else { return }
                    Clipboard.copy(result)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)
                .disabled(result == nil)
                Button("\(model.operation.title)文本") {
                    model.translate(to: targetLanguage)
                }
                .buttonStyle(.glassProminent)
                // The ⌘↩ key equivalent belongs to the 文本处理 menu's submit item, so one place owns
                // it; the tooltip still tells the user it exists.
                .help("\(model.operation.title)文本 ⌘↩")
                .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var languagePicker: some View {
        Picker("目标语言", selection: $targetLanguage) {
            ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

/// Section caption: secondary label left, meta right.
private struct LabelRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            leading
            Spacer()
            trailing
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

/// Error or missing-config note with its recovery entry.
private struct StatusNote: View {
    let message: String
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle")
            Spacer(minLength: 0)
            GlassEffectContainer {
                Button(action, action: perform).buttonStyle(.glass)
            }
        }
        .font(.system(size: 12))
        .padding(.top, 16)
        .accessibilityElement(children: .contain)
    }
}
