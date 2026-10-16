import Observation
import SwiftUI

/// The state behind every copy confirmation: true for a moment after a press, then back. One
/// implementation, so a copy answers the same way wherever it is pressed.
@MainActor @Observable final class CopyConfirmation {
    private(set) var isCopied = false
    private var revert: Task<Void, Never>?

    /// Copies and reports it; a second press restarts the moment rather than stacking another one.
    func confirm() {
        isCopied = true
        revert?.cancel()
        revert = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.isCopied = false
        }
    }
}

/// A settings row's copy action: a plain text button that reads "Copy" and, right after a press,
/// "Copied".
struct CopyButton: View {
    /// Built when the press happens: a record's report is assembled on demand.
    let text: () -> String
    @State private var confirmation = CopyConfirmation()

    var body: some View {
        Button {
            Clipboard.copy(text())
            confirmation.confirm()
        } label: {
            // Both states are laid out at once, so the wider word decides the width once and the card
            // does not move when the label changes.
            ZStack {
                Label(copyTitle(false), systemImage: copySymbol(false)).opacity(confirmation.isCopied ? 0 : 1)
                Label(copyTitle(true), systemImage: copySymbol(true)).opacity(confirmation.isCopied ? 1 : 0)
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}

/// A card's copy action: the same confirmation on the round glass glyph, which becomes a checkmark.
struct CopyCardButton: View {
    /// The command's own name for the glyph: "Copy Result", "Copy Expression".
    let title: String
    var key: KeyHint? = nil
    let text: () -> String
    @State private var confirmation = CopyConfirmation()

    var body: some View {
        CardButton(
            title: copyTitle(confirmation.isCopied), symbol: copySymbol(confirmation.isCopied),
            key: key, bindsKey: false, alternateSymbol: copySymbol(false)
        ) {
            Clipboard.copy(text())
            confirmation.confirm()
        }
    }
}

/// "Copy" or, while the confirmation lasts, "Copied".
private func copyTitle(_ copied: Bool) -> String {
    L10n.shared.string(copied ? "Copied" : "Copy")
}

private func copySymbol(_ copied: Bool) -> String {
    copied ? "checkmark" : "document.on.document"
}
