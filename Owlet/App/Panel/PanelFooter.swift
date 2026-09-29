import SwiftUI

/// Fixed footer: the actions only, with copy and the single prominent action at the trailing end.
struct PanelFooter: View {
    let state: TextProcessingModel.State
    let operation: Operation
    /// Idle because the user stopped processing; the main button then reads "重新处理".
    let cancelled: Bool
    let replace: ((String) -> Void)?
    let copy: (String) -> Void
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
