import AppKit
import SwiftUI

/// Expanded floating panel: header, scrollable source/result body, fixed action footer.
struct ExpandedPanel: View {
    @Bindable var model: TranslationModel
    /// Writes the result back to the original selection; nil when there is no source.
    let replace: ((String) -> Void)?
    let notice: PanelController.Notice?
    let recover: (PanelController.Notice) -> Void
    let retry: () -> Void
    let cancel: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                operation: $model.operation,
                retry: canRetry ? retry : nil,
                openSettings: openSettings)
            RoseGlass.hairline.frame(height: 1)
            ScrollView {
                PanelBody(model: model, notice: notice, recover: recover)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 440)
            RoseGlass.hairline.frame(height: 1)
            PanelFooter(
                state: model.state,
                operation: model.operation,
                cancelled: notice == .cancelled,
                replace: replace,
                retry: canRetry ? retry : nil,
                cancel: cancel)
        }
        .frame(width: 560)
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
                    .foregroundStyle(RoseGlass.muted)
                    .accessibilityLabel("Owlet")
                Picker("快捷操作", selection: $operation) {
                    ForEach(Operation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .fixedSize()
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RoseGlass.ink)
            }
            Spacer(minLength: 0)
            HStack(spacing: 1) {
                if let retry {
                    ToolButton(title: "重新处理", systemImage: "arrow.clockwise", action: retry)
                }
                ToolButton(title: "打开设置", systemImage: "slider.horizontal.3", action: openSettings)
            }
        }
        .padding(.horizontal, 13)
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
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(RoseGlass.muted)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .help(title)
    }
}

/// Source and result sections; the source stays editable so a retry can use revised text.
private struct PanelBody: View {
    @Bindable var model: TranslationModel
    let notice: PanelController.Notice?
    let recover: (PanelController.Notice) -> Void
    @AppStorage(SettingsStore.targetLanguageKey) private var targetLanguage =
        SettingsStore.defaultTargetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    .foregroundStyle(RoseGlass.ink)
                    .lineLimit(1...5)
            }
            .padding(.bottom, 12)
            if hasResultSection {
                RoseGlass.line.frame(height: 1)
                resultSection.padding(.top, 12)
            }
            status
        }
        .padding(.horizontal, 17)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        Circle().fill(RoseGlass.accent).frame(width: 5, height: 5)
                        Text("\(model.operation.title)中")
                    }
                } else {
                    Text(model.operation == .polish ? "润色结果" : "译文")
                }
            } trailing: {
                if model.operation == .polish { Text("保留原意") } else { languagePicker }
            }
            if case .success(let text) = model.state {
                Text(text)
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .foregroundStyle(RoseGlass.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    RoundedRectangle(cornerRadius: 4).fill(RoseGlass.skeleton).frame(height: 9)
                    RoundedRectangle(cornerRadius: 4).fill(RoseGlass.skeleton).frame(width: 300, height: 9)
                }
                .padding(.vertical, 6)
                .accessibilityLabel("正在生成结果")
            }
        }
    }

    @ViewBuilder private var status: some View {
        if let notice {
            StatusNote(neutral: notice == .cancelled) {
                Text(notice.message)
                    .font(.system(size: 12))
                    .foregroundStyle(RoseGlass.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                InlineAction(notice.actionTitle) { recover(notice) }
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
        .foregroundStyle(RoseGlass.muted)
        .frame(minHeight: 16)
    }
}

/// In-content status: message left, recovery entry right; warm red for errors, neutral when cancelled.
private struct StatusNote<Content: View>: View {
    var neutral = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(
                neutral ? RoseGlass.neutralFill : RoseGlass.errorFill,
                in: .rect(cornerRadius: 8, style: .continuous)
            )
            .padding(.top, 10)
            .accessibilityElement(children: .contain)
    }
}

/// Fixed footer: shortcut hint left, copy and prominent replace (or retry/cancel) right.
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
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(RoseGlass.muted)
            Spacer(minLength: 0)
            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 45)
        .background(RoseGlass.footer)
    }

    private var hint: String {
        if state == .loading { return "Esc 取消" }
        let action: ShortcutAction = operation == .polish ? .polish : .translate
        guard let shortcut = SettingsStore.shortcut(forKey: action.defaultsKey, in: .standard) else {
            return "快捷键未设置"
        }
        return "\(shortcut.displayString) 唤起"
    }

    private var retryTitle: String {
        guard state == .idle else { return "重试" }
        return cancelled ? "重新处理" : operation.title
    }

    @ViewBuilder private var actions: some View {
        switch state {
        case .loading:
            Button("取消", action: cancel).buttonStyle(FooterButtonStyle())
        case .success(let text):
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(FooterButtonStyle())
            if let replace {
                Button {
                    replace(text)
                } label: {
                    Text("替换")
                    KeyCap("⌘ ↩")
                }
                .buttonStyle(FooterButtonStyle(prominent: true))
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("替换")
            }
        default:
            if let retry {
                Button(action: retry) {
                    Text(retryTitle)
                    KeyCap("⌘ ↩")
                }
                .buttonStyle(FooterButtonStyle(prominent: true))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

/// Footer glass button: 8pt-radius near-white glass, or rose-tinted glass when prominent.
private struct FooterButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.label }
            .labelStyle(FooterLabelStyle())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(prominent ? RoseGlass.paper : RoseGlass.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .glassEffect(
                prominent ? .regular.tint(RoseGlass.accent).interactive() : .regular.interactive(),
                in: .rect(cornerRadius: 8, style: .continuous)
            )
            .contentShape(.rect(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.85 : isEnabled ? 1 : 0.5)
    }
}

private struct FooterLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 12))
            configuration.title
        }
    }
}

/// Key hint inside the prominent button: translucent white chip.
private struct KeyCap: View {
    let keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.white.opacity(0.22), in: .rect(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.6), lineWidth: 1))
            .accessibilityHidden(true)
    }
}
