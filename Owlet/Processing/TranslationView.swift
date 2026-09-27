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

    var input = ""
    var operation: Operation = .translate
    private(set) var state: State = .idle
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

    /// Starts the current operation; any in-flight one is cancelled and its result ignored.
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
        state = .loading
        let client = client
        let task = Task {
            let result: State
            do {
                result = .success(
                    try await client.process(
                        text, operation: operation, to: targetLanguage, config: config))
            } catch let error as ModelError {
                result = .failure(error.message)
            } catch is CancellationError {
                return
            } catch {
                result = .failure(error.localizedDescription)
            }
            guard id == self.operationID else { return }
            self.state = result
        }
        self.task = task
        return task
    }
}

/// Main-window 文本处理 page (design/screenshots/workspace.png): title bar with target
/// language and operation menus, editable source, result, and a fixed action footer.
struct TranslationView: View {
    @Bindable var model: TranslationModel
    @AppStorage(SettingsStore.targetLanguageKey) private var targetLanguage =
        SettingsStore.defaultTargetLanguage

    static let accent = RoseGlass.accent

    static let languages = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "English"), ("ja", "日本語"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "文本处理") {
                HStack(spacing: 8) {
                    if model.operation == .translate { languagePicker }
                    Picker("处理方式", selection: $model.operation) {
                        ForEach(Operation.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .font(.system(size: 12))
                .disabled(isBusy)
            }
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
            footer
        }
        .foregroundStyle(RoseGlass.ink)
        .tint(Self.accent)
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
            MainLabelRow {
                Text(showsResult ? "自动识别" : "输入文本")
            } trailing: {
                Text(showsResult ? "原文" : "⌘ V 粘贴")
            }
            TextEditor(text: $model.input)
                .textEditorStyle(.plain)
                .font(.system(size: 16))
                .lineSpacing(7)
                .scrollContentBackground(.hidden)
                .frame(height: 110)
                // Cancels NSTextView's line fragment padding so text aligns with the labels.
                .padding(.horizontal, -5)
                .overlay(alignment: .topLeading) {
                    if model.input.isEmpty {
                        Text("输入或粘贴要处理的文本…")
                            .font(.system(size: 16))
                            .foregroundStyle(RoseGlass.muted.opacity(0.8))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("原文")
        }
        .padding(.bottom, 21)
        .overlay(alignment: .bottom) { RoseGlass.line.frame(height: 1) }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MainLabelRow {
                if isBusy {
                    HStack(spacing: 6) {
                        Circle().fill(Self.accent).frame(width: 5, height: 5)
                        Text("\(model.operation.title)中")
                    }
                } else {
                    Text(model.operation == .polish ? "润色结果" : "译文")
                }
            } trailing: {
                if model.operation == .translate {
                    languagePicker.buttonStyle(.borderless).tint(RoseGlass.muted).disabled(isBusy)
                } else {
                    Text("保留原意")
                }
            }
            Group {
                if let result {
                    Text(result)
                        .font(.system(size: 17))
                        .tracking(model.operation == .translate ? 0.3 : 0)
                        .lineSpacing(8)
                        .textSelection(.enabled)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 4).fill(RoseGlass.skeleton).frame(height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(RoseGlass.skeleton)
                            .frame(width: 320, height: 12)
                    }
                    .padding(.vertical, 6)
                    .accessibilityLabel("正在生成结果")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .accessibilityAddTraits(.updatesFrequently)
            // Reserved for the unbuilt 收藏选中内容 row so the layout stays stable.
            Color.clear.frame(height: 30)
        }
        .padding(.top, 25)
    }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .failure(let message):
            StatusBlock(message: message) { settingsLink("服务设置") }
        case .missingConfig:
            StatusBlock(message: "模型服务未配置") { settingsLink("配置服务") }
        default:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(isBusy ? "处理中" : "")
                .font(.system(size: 11))
                .foregroundStyle(RoseGlass.muted)
            Spacer()
            if isBusy {
                Button("取消", action: model.cancel)
                    .buttonStyle(MainButtonStyle())
            } else {
                Button {
                    guard let result else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(MainButtonStyle())
                .disabled(result == nil)
                Button {
                    model.translate(to: targetLanguage)
                } label: {
                    Text("\(model.operation.title)文本")
                    Text("⌘ ↩")
                        .font(.system(size: 11))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.3))
                        )
                        .accessibilityHidden(true)
                }
                .buttonStyle(MainButtonStyle(prominent: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("\(model.operation.title)文本")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .background(RoseGlass.footerFill)
        .overlay(alignment: .top) { RoseGlass.line.frame(height: 1) }
    }

    private var languagePicker: some View {
        Picker("目标语言", selection: $targetLanguage) {
            ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func settingsLink(_ title: String) -> some View {
        SettingsLink {
            Text(title).underline().font(.system(size: 12)).foregroundStyle(Self.accent)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// Main-window page title bar: 64pt, title left, page controls right, hairline below.
struct PageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
        .padding(.horizontal, 30)
        .frame(height: 64)
        .overlay(alignment: .bottom) { RoseGlass.line.frame(height: 1) }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

private struct MainLabelRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            leading.tracking(0.8)
            Spacer()
            trailing
        }
        .font(.system(size: 11))
        .foregroundStyle(RoseGlass.muted)
    }
}

private struct StatusBlock<Action: View>: View {
    let message: String
    @ViewBuilder let action: Action

    var body: some View {
        HStack(spacing: 12) {
            Text(message).foregroundStyle(RoseGlass.errorText)
            Spacer(minLength: 0)
            action
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoseGlass.errorFill, in: .rect(cornerRadius: 8, style: .continuous))
        .padding(.top, 16)
        .accessibilityElement(children: .contain)
    }
}

/// Footer button: near-white bordered secondary, or solid rose primary.
private struct MainButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.label }
            .labelStyle(MainLabelStyle())
            .font(.system(size: 14, weight: prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? RoseGlass.paper : RoseGlass.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(
                prominent ? RoseGlass.accent : RoseGlass.paper,
                in: .rect(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(RoseGlass.line)
                }
            }
            .shadow(color: prominent ? RoseGlass.accent.opacity(0.13) : .clear, radius: 1.5, y: 2)
            .contentShape(.rect(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.85 : isEnabled ? 1 : 0.45)
    }
}

private struct MainLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 13))
            configuration.title
        }
    }
}

/// Main-window tokens (design/index.html), OKLCH converted to sRGB.
extension RoseGlass {
    /// oklch(98% .005 350)
    static let window = Color(red: 0.985, green: 0.969, blue: 0.976)
    /// oklch(93% .012 350 / .48)
    static let sidebar = Color(red: 0.936, green: 0.897, blue: 0.913).opacity(0.48)
    /// oklch(100% .006 350 / .8)
    static let selectedNav = Color(red: 1, green: 0.994, blue: 1).opacity(0.8)
    /// oklch(98% .006 350 / .8)
    static let footerFill = Color(red: 0.988, green: 0.968, blue: 0.976).opacity(0.8)
    /// oklch(43% .1 40)
    static let errorText = Color(red: 0.487, green: 0.226, blue: 0.131)
    /// oklch(43% .09 158)
    static let green = Color(red: 0.086, green: 0.37, blue: 0.236)
}
