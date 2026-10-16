import SwiftUI

/// Debug pane, shown only while the switch in General is on: one grouped-`Form` section per captured
/// model exchange, so the page reads as a set of records and each card is the system's own — the
/// heading names the record above it, as every other settings card does, and the captured text sits in
/// rows inside.
struct DebugSettingsPane: View {
    @State private var log = DebugLog.shared
    /// Which records are open, by id. A record starts closed: the page is a list of what was asked for
    /// and how it went, and one click opens the capture behind it.
    @State private var expanded: Set<UUID> = []

    /// `expanded` and `opensBlocks` let the preview show an open record with its text showing; the app
    /// always starts with every record and every block closed.
    init(expanded: Set<UUID> = [], opensBlocks: Bool = false) {
        _expanded = State(initialValue: expanded)
        self.opensBlocks = opensBlocks
    }

    private var opensBlocks = false

    var body: some View {
        Group {
            if log.exchanges.isEmpty {
                ContentUnavailableView(
                    "Nothing recorded yet", systemImage: "ladybug",
                    description: Text(L10n.shared.string("Run a translation or a polish and it appears here.")))
            } else {
                Form {
                    ForEach(log.exchanges) { exchange in
                        record(exchange)
                    }
                    Section {
                        Button(L10n.shared.string("Clear")) { log.clear() }
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

    /// One record. Closed it reads as its own summary — what was sent and, in red, what went wrong;
    /// open it adds the capture: the two bodies, and the copy for reading them elsewhere.
    @ViewBuilder private func record(_ exchange: DebugExchange) -> some View {
        Section {
            Button {
                toggle(exchange)
            } label: {
                HStack(spacing: 8) {
                    Text(exchange.summary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded(exchange) ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(L10n.shared.string(isExpanded(exchange) ? "Expanded" : "Collapsed"))
            // Said once, here: the blocks below hold the raw material, not the diagnosis.
            if let failure = exchange.failure {
                Text(failure)
                    .foregroundStyle(.red)
                    .lineLimit(isExpanded(exchange) ? nil : 1)
                    .textSelection(.enabled)
            }
            if isExpanded(exchange) {
                if let divergence = exchange.sourceDivergence {
                    Text(divergence)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                DebugBlock(
                    title: "Response", symbol: "text.bubble",
                    text: exchange.response ?? "—", isOpen: opensBlocks)
                DebugBlock(
                    title: "Request", symbol: "curlybraces",
                    text: exchange.request, isOpen: opensBlocks)
                HStack {
                    Spacer()
                    CopyButton { exchange.report }
                }
            }
        } header: {
            heading(exchange)
        }
    }

    private func isExpanded(_ exchange: DebugExchange) -> Bool { expanded.contains(exchange.id) }

    private func toggle(_ exchange: DebugExchange) {
        withAnimation(.spring(duration: 0.36, bounce: 0.12)) {
            if expanded.contains(exchange.id) {
                expanded.remove(exchange.id)
            } else {
                expanded.insert(exchange.id)
            }
        }
    }

    /// What was asked for and when. The glyph names the request — the operation's own — and its colour
    /// carries the outcome, so a page of records is read by colour before any text.
    private func heading(_ exchange: DebugExchange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: exchange.symbol)
                .foregroundStyle(outcomeColor(exchange))
                .accessibilityLabel(
                    L10n.shared.string(exchange.failure == nil ? "Succeeded" : "Failed"))
            Text(verbatim: exchange.title)
                .fontWeight(.semibold)
            Spacer(minLength: 8)
            Text(exchange.date.formatted(date: .omitted, time: .standard))
                .monospacedDigit()
        }
    }

    private func outcomeColor(_ exchange: DebugExchange) -> Color {
        exchange.failure == nil ? .green : .red
    }
}

/// One captured text, folded: the header reads as one line — a glyph, the name, a trailing chevron, the
/// way a command and its output read in the tools this page diagnoses — and the text opens in an inset
/// block under it. A plain button rather than a `DisclosureGroup`: the system one puts its indicator at
/// the leading edge and answers only to that indicator.
private struct DebugBlock: View {
    let title: String
    let symbol: String
    let text: String
    /// The block's ceiling: past it the text scrolls, so one long reply cannot push every other record
    /// off the page.
    private static let maxHeight: CGFloat = 260
    @State private var isOpen: Bool
    /// Measured so a short reply still hugs its words rather than sitting in a fixed tall box.
    @State private var textHeight: CGFloat = 0

    init(title: String, symbol: String, text: String, isOpen: Bool) {
        self.title = title
        self.symbol = symbol
        self.text = text
        _isOpen = State(initialValue: isOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .foregroundStyle(.secondary)
                    Text(L10n.shared.string(title))
                        .font(.callout)
                    Spacer(minLength: 8)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(L10n.shared.string(isOpen ? "Expanded" : "Collapsed"))
            if isOpen {
                ScrollView(.vertical) {
                    Text(displayText)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { textHeight = $0 }
                }
                .frame(height: min(textHeight, Self.maxHeight))
                .insetBlock()
            }
        }
    }

    private func toggle() {
        withAnimation(.spring(duration: 0.36, bounce: 0.12)) { isOpen.toggle() }
    }

    /// The text as shown: JSON is pretty printed, so a reply or a request body reads as structure
    /// rather than as one long line. A fragment (`"lush"`, `42`) is not JSON here and stays as it is,
    /// and the copied record keeps the exact text that was recorded.
    private var displayText: String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: pretty, encoding: .utf8)
        else { return text }
        return string
    }
}
