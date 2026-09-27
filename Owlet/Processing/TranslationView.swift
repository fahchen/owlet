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
            }
        }
    }
    var operation: Operation = .translate
    private(set) var state: State = .idle
    /// Languages of the latest successful result, so a collected expression keeps its own language.
    private(set) var languages: (source: String, target: String)?
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
            }
            self.state = outcome
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
    @AppStorage(SettingsStore.targetLanguageKey) private var targetLanguage =
        SettingsStore.defaultTargetLanguage

    static let languages = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "English"), ("ja", "日本語"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sourceSection
                if showsResult { resultSection }
                status
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
            if model.hasBeenSent { model.translate(to: targetLanguage) }
        }
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

    private var sourceSection: some View {
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
        .padding(.bottom, 21)
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().padding(.bottom, 13)
            LabelRow {
                if isBusy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("\(model.operation.title)中")
                    }
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
            Group {
                if let result {
                    Text(result)
                        .font(.system(size: 17))
                        .lineSpacing(8)
                        .textSelection(.enabled)
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
            if result != nil { collectRow }
            // Reserved for the unbuilt 学习表达 disclosure (25pt gap, hairline, 14pt inset, row).
            if result != nil { Color.clear.frame(height: 61) }
        }
    }

    private func collect(_ region: CollectedRegion) {
        guard
            let draft = VocabularyDraft.from(
                region: region, model: model, selection: TextSelection.current())
        else { return }
        collection.collect(draft)
    }

    private var collectRow: some View {
        HStack(spacing: 12) {
            Menu {
                Button("收藏原文") { collect(.source) }
                Button(model.operation == .polish ? "收藏润色结果" : "收藏译文") { collect(.result) }
            } label: {
                Label("收藏选中内容", systemImage: "book")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            CollectionFeedback(collection: collection, openNotebook: openNotebook)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .frame(minHeight: 30)
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
                .keyboardShortcut(.return, modifiers: .command)
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
