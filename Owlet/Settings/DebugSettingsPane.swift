import SwiftUI

/// Debug pane, shown only while the switch in General is on: the captured model exchanges in one grouped
/// `Form` section, like every other settings pane. A collapsed row says what was asked for, whether
/// it failed and when; it opens with the system `DisclosureGroup`, so the indicator, the animation
/// and the accessibility state all come from the system.
struct DebugSettingsPane: View {
    @State private var log = DebugLog.shared
    /// Which rows are open, kept outside the rows so a new capture cannot leave one half expanded.
    @State private var expanded: Set<UUID>

    /// `expanded` lets the preview open a row; the app always starts with every row closed.
    init(expanded: Set<UUID> = []) {
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        Group {
            if log.exchanges.isEmpty {
                ContentUnavailableView(
                    "Nothing recorded yet", systemImage: "ladybug",
                    description: Text(L10n.shared.string("Run a translation or a polish and it appears here.")))
            } else {
                Form {
                    Section {
                        ForEach(log.exchanges) { exchange in
                            DisclosureGroup(isExpanded: isExpanded(exchange)) {
                                detail(exchange)
                            } label: {
                                summary(exchange)
                            }
                        }
                    } header: {
                        Text(L10n.shared.string("Recent Requests"))
                    } footer: {
                        Text(
                            L10n.shared.string(
                                "Kept in memory only, the latest %lld; turning the Debug page off clears them.",
                                DebugLog.limit)
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    /// Scannable at a glance, like a history row: what was asked for and when, then the text that
    /// was sent, then the failure in red when there was one. Each line is cut to one line; the
    /// disclosure opens the rest.
    private func summary(_ exchange: DebugExchange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.statusSpacing) {
            status(exchange)
                .frame(width: Self.statusWidth)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: exchange.title)
                        .fontWeight(.medium)
                    Spacer(minLength: 8)
                    Text(exchange.date.formatted(date: .omitted, time: .standard))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(exchange.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                // The failure is said once, here; an open row shows all of it instead of repeating it.
                if let failure = exchange.failure {
                    Text(failure)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .lineLimit(expanded.contains(exchange.id) ? nil : 1)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The status column; the detail is indented by it so it starts under the title.
    private static let statusWidth: CGFloat = 18
    private static let statusSpacing: CGFloat = 8

    /// Failure in system red, success in the secondary colour, so the eye lands on what went wrong.
    @ViewBuilder private func status(_ exchange: DebugExchange) -> some View {
        if exchange.failure != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel(L10n.shared.string("Failed"))
        } else {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.shared.string("Succeeded"))
        }
    }

    /// The captured content itself. The reply is what a diagnosis needs first, so it starts open;
    /// the submitted text and the request body can be long and start folded. No nested scroll view:
    /// the form already scrolls, and nesting a second one on the same axis fights it.
    @ViewBuilder private func detail(_ exchange: DebugExchange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let divergence = exchange.sourceDivergence {
                Text(divergence)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            DebugBlock(title: "Model Raw Reply", text: exchange.response ?? "—", isOpen: true)
            DebugBlock(title: "Submitted Text", text: exchange.submitted, isOpen: false)
            DebugBlock(title: "Request Body", text: exchange.request, isOpen: false)
            HStack {
                Spacer()
                Button(L10n.shared.string("Copy This Record"), systemImage: "document.on.document") {
                    Clipboard.copy(exchange.report)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, Self.statusWidth + Self.statusSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Animated: a disclosure change should read as the row growing, not as the list jumping.
    private func isExpanded(_ exchange: DebugExchange) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(exchange.id) },
            set: { open in
                withAnimation(.spring(duration: 0.36, bounce: 0.12)) {
                    if open {
                        expanded.insert(exchange.id)
                    } else {
                        expanded.remove(exchange.id)
                    }
                }
            })
    }
}

/// One captured text, folded with the system `DisclosureGroup` as the design asks for long text.
private struct DebugBlock: View {
    let title: String
    let text: String
    @State private var isOpen: Bool

    init(title: String, text: String, isOpen: Bool) {
        self.title = title
        self.text = text
        _isOpen = State(initialValue: isOpen)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen.animation(.spring(duration: 0.36, bounce: 0.12))) {
            Text(text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        } label: {
            Text(L10n.shared.string(title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
