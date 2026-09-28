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

/// Main-window 翻译与润色 page: the source and the result side by side, the operation in the window
/// toolbar as a segmented control, and the actions floating over the content's trailing corner.
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
    /// Which of the result box's panes is showing; a new result starts on the result itself.
    @State private var section: ResultSection = .result
    /// The pinned target language; an empty value means 自动.
    @AppStorage(SettingsStore.pinnedTargetKey) private var pinnedTarget = ""
    /// The pinned source language; an empty value means 自动.
    @AppStorage(SettingsStore.pinnedSourceKey) private var pinnedSource = ""
    @AppStorage(SettingsStore.displayModeKey) private var displayMode =
        TranslationDisplayMode.sectioned

    var body: some View {
        layout
            // Measured before the padding, so 720pt is the content area, not the whole window.
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                contentWidth = $0
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .navigationTitle("翻译与润色")
            // Switching the operation runs the same text again at once, so the two results can be
            // compared without pressing the button a second time; switching back is served from cache.
            .onChange(of: model.operation) { _, _ in
                section = .result
                if model.hasBeenSent {
                    model.translate(to: SettingsStore.resolvedTarget(for: model.input))
                }
            }
            // Pinning a target or a source runs the same text again, served from cache when already
            // produced for that language.
            .onChange(of: pinnedTarget) { _, _ in
                if model.hasBeenSent {
                    model.translate(to: SettingsStore.resolvedTarget(for: model.input))
                }
            }
            .onChange(of: pinnedSource) { _, _ in
                if model.hasBeenSent {
                    model.translate(to: SettingsStore.resolvedTarget(for: model.input))
                }
            }
            // The operation is a toolbar control: it decides what this page does, next to the title.
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("处理方式", selection: $model.operation) {
                        ForEach(Operation.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(isBusy)
                }
            }
            // The source text changed, so the old result and its learning items no longer apply, and
            // the box goes back to showing the result.
            .onChange(of: model.input) { _, _ in
                learning.reset()
                section = .result
            }
            // 自动请求学习表达 still means "as soon as the result lands", whether or not this pane is
            // the one on screen; the claim inside keeps it to one request per result.
            .onChange(of: model.state) { _, _ in
                if let request = LearningRequest.from(model) {
                    learning.generateIfAutoRequested(for: request)
                }
            }
            // A bottom *toolbar* does not exist on macOS (SwiftUI's `bottomBar` is iOS and Catalyst
            // only), so the two actions float over the content's trailing corner, the way Freeform
            // places its controls. Two separate glass icon buttons, not one merged cluster: each is its
            // own control. The words live in the tooltips and the accessibility labels.
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 8) {
                    if isBusy {
                        Button(action: model.cancel) {
                            Label("取消", systemImage: "xmark")
                        }
                        .buttonStyle(.glass)
                        .help("取消")
                    } else {
                        Button(action: copyResult) {
                            Label("复制结果", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.glass)
                        .help("复制结果 ⌘⇧C")
                        .disabled(result == nil)
                        Button {
                            model.translate(to: resolvedTarget)
                        } label: {
                            Label(model.operation.title, systemImage: model.operation.symbol)
                        }
                        .buttonStyle(.glassProminent)
                        .help("\(model.operation.title)文本 ⌘↩")
                        .disabled(
                            model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .labelStyle(.iconOnly)
                .padding(20)
            }
    }

    private var isBusy: Bool { model.state == .loading }

    /// What this text resolves to right now: an explicit choice, else the mapping, else the fallback.
    private var resolvedTarget: String { SettingsStore.resolvedTarget(for: model.input) }

    private var result: String? {
        if case .success(let text) = model.state { return text }
        return nil
    }

    private func copyResult() {
        guard let result else { return }
        Clipboard.copy(result)
    }

    /// Mirrors the prototype: before the first result the page is a plain input.
    private var showsResult: Bool { isBusy || result != nil }

    /// Source and result side by side once the content area is wide enough, stacked otherwise.
    /// The page keeps both sides in view whatever the window is: side by side they share the width,
    /// stacked they share the height, and either way each side scrolls on its own rather than pushing
    /// the other out of the window.
    /// Both sides are always present — the window shows where text goes in and where the result will
    /// appear, before there is one — and each side is a `GroupBox`, so the two read as two areas of
    /// the same page rather than as one column split by a rule.
    @ViewBuilder private var layout: some View {
        if ProcessingLayout.choose(width: contentWidth) == .sideBySide {
            HStack(alignment: .top, spacing: 18) {
                sourcePane; resultPane
            }
        } else {
            VStack(spacing: 18) {
                sourcePane; resultPane
            }
        }
    }

    /// The source side: the editor fills the box, so the whole column is usable input rather than a
    /// fixed strip with empty space under it. The title is just 原文 — the tab above already says which
    /// operation this is.
    private var sourcePane: some View {
        GroupBox {
            TextEditor(text: $model.input)
                .textEditorStyle(.plain)
                // The editor brings its own background; hiding it lets the box's border and fill show,
                // which is what makes this side read as a box.
                .scrollContentBackground(.hidden)
                .font(.system(size: 16))
                .lineSpacing(7)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    if model.input.isEmpty {
                        Text("输入或粘贴要处理的文本…")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                }
                .accessibilityLabel("原文")
        } label: {
            // The group's title slot holds the control that configures it, so nothing is named twice.
            SourceLanguagePicker(text: model.input, pinnedSource: $pinnedSource)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minHeight: 180)
    }

    /// The result side. Its switch is a segmented control — the HIG's own example is a segmented
    /// control that shows and hides panes of the same window — so 译文／润色 and 学习 share one box
    /// instead of stacking, and the target language sits in the box with them.
    private var resultPane: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if isBusy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("\(model.operation.title)中")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    } else if model.operation == .translate {
                        languagePicker
                    } else {
                        Text("保留原意")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if section == .learning {
                            learningSection
                        } else {
                            resultBody
                            status
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    // Room for the floating buttons, so the last line can still be read.
                    .padding(.bottom, 40)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } label: {
            Picker("结果", selection: $section) {
                Text(resultTitle).tag(ResultSection.result)
                Text("学习").tag(ResultSection.learning)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minHeight: 180)
    }

    /// Which of the result box's two panes is showing.
    private enum ResultSection: Hashable {
        case result
        case learning
    }

    private var resultTitle: String {
        if displayMode == .aligned && section == .result { return "逐句对照" }
        return model.operation == .polish ? "润色结果" : "译文"
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
                learning: learning, reveal: .immediate, request: request, collection: collection,
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

    private var languagePicker: some View {
        TargetLanguagePicker(text: model.input, pinnedTarget: $pinnedTarget)
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
