import SwiftUI

extension View {
    /// The panel's one glass surface: a fixed-radius rounded rectangle, with the content clipped to
    /// it so nothing shows past its corners. A nil height hugs the content.
    func panelSurface(_ glass: Glass, height: CGFloat? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius)
        return frame(width: PanelMetrics.width, height: height, alignment: .top)
            .clipShape(shape)
            .glassEffect(glass, in: shape)
    }
}

enum PanelMetrics {
    static let width: CGFloat = 773
    static let contentInset: CGFloat = 24
    /// Result text; the source sits one size below it so the translation reads first.
    static let textSize: CGFloat = 16
    static let sourceTextSize: CGFloat = 15
    static let textWeight: Font.Weight = .medium
    /// The source stays lighter than the result it was turned into.
    static let sourceWeight: Font.Weight = .regular
    /// Transparent window margin around the glass, so its shadow fades out instead of being cut
    /// at the window edge.
    static let shadowMargin: CGFloat = 24
    /// The source bar; the expanded glass grows down from this height.
    static let sourceBarHeight: CGFloat = 62
    /// The expanded glass corner radius, from the design's large surface.
    static let cornerRadius: CGFloat = 34
    /// Extra scroll room past the content, so the floating action row (36pt buttons, 12pt above them)
    /// can sit over the text at rest and the text still scrolls out from under it.
    static let actionRoom: CGFloat = 36 + 12
}

struct CompactProcessingView: View {
    @AppStorage(SettingsStore.panelGlassEffectKey) private var glassEffect = PanelGlassEffect.contrast
    let summary: String
    let status: String
    /// The running operation's symbol, the same one its toolbar segment and history rows show.
    var symbol = Operation.translate.symbol
    let stop: () -> Void
    var close: (() -> Void)? = nil
    /// False when the panel root draws the source bar on its own growing surface.
    var showsBar = true

    var body: some View {
        VStack(spacing: 12) {
            if showsBar {
                PanelSourceBar(summary: summary, close: close ?? stop)
            }
            PanelSegmentedControl(items: [
                .init(title: status, symbol: symbol, action: {}),
                .init(
                    title: "", symbol: "xmark", action: stop, accessibilityLabel: L10n.shared.string("Cancel"),
                    key: .panelCancel),
            ])
            .fixedSize()
            .frame(height: 36)
            .padding(.horizontal, 4)
            .glassEffect(glassEffect.compactGlass)

        }
        .frame(width: PanelMetrics.width)
    }
}

struct PanelSourceBar: View {
    @AppStorage(SettingsStore.panelGlassEffectKey) private var glassEffect = PanelGlassEffect.contrast
    let summary: String
    /// The source itself, editable in place (BDR-0018); nil shows `summary` as read-only text.
    var text: Binding<String>? = nil
    /// Why the field is empty, when it is.
    var placeholder = ""
    /// Bumped when the field should take the keyboard.
    var focusRequest = 0
    /// What ⌘↩ runs, shown beside the field while it is being edited.
    var submitTitle = ""
    /// A screen region's screenshot, leading the bar until the panel opens (BDR-0019).
    var screenshot: NSImage? = nil
    var screenshotSpace: Namespace.ID? = nil
    var toggleScreenshotZoom: () -> Void = {}
    var retry: (() -> Void)? = nil
    let close: () -> Void
    /// False on the panel root's surface, which supplies the glass so it can grow into the panel.
    var drawsGlass = true
    @FocusState private var focused: Bool
    @State private var showsEditHint = false
    /// The "Click to Edit" hint teaches the field; after a few showings it is known and stays away.
    @AppStorage(SettingsStore.panelEditHintsKey) private var editHints = 0

    var body: some View {
        HStack(spacing: 8) {
            if let screenshot {
                ScreenshotThumbnail(image: screenshot, namespace: screenshotSpace, toggle: toggleScreenshotZoom)
                    .padding(.trailing, 4)
            }
            if let text {
                TextField(placeholder, text: text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: PanelMetrics.sourceTextSize, weight: PanelMetrics.sourceWeight))
                    // One line at rest, like the summary; a paste grows the bar while editing.
                    .lineLimit(focused ? 1...5 : 1...1)
                    .focused($focused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .task(id: focusRequest) {
                        guard focusRequest > 0 else { return }
                        // The panel clears its first responder as it shows; focus once it is up.
                        try? await Task.sleep(for: .milliseconds(100))
                        focused = true
                    }
                    .onHover { inside in
                        showsEditHint = inside && !focused && !text.wrappedValue.isEmpty && editHints < 3
                        if showsEditHint { editHints += 1 }
                    }
                if focused, !text.wrappedValue.isEmpty, !submitTitle.isEmpty {
                    Text(verbatim: KeyHint.panelReplace.keys + " " + submitTitle)
                        .font(.caption).foregroundStyle(.secondary)
                } else if showsEditHint && !focused {
                    Text(L10n.shared.string("Click to Edit")).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(summary.replacing(/\s+/, with: " "))
                    .font(.system(size: PanelMetrics.sourceTextSize, weight: PanelMetrics.sourceWeight))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hoverTip(verbatim: summary)
            }
            if let retry {
                PanelSegmentedControl(items: [
                    .init(
                        title: "Retry", symbol: "arrow.clockwise", action: retry,
                        accessibilityLabel: L10n.shared.string("Try Again"),
                        key: .panelRetry),
                    .init(
                        title: "", symbol: "xmark", action: close,
                        accessibilityLabel: L10n.shared.string("Close Panel"),
                        key: .panelCancel),
                ])
                .fixedSize()
                .frame(height: 36)
                .padding(.horizontal, 4)
                .glassEffect(glassEffect.glass)

            } else {
                Button(action: close) {
                    Label(L10n.shared.string("Off"), systemImage: "xmark").foregroundStyle(.primary)
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .medium))
                .buttonStyle(.glass(glassEffect.glass))
                .buttonBorderShape(.circle)
                .controlSize(.extraLarge)
                .buttonSizing(.flexible)
                .frame(width: 36, height: 36)
                .hoverTip(KeyHint.panelCancel, title: "Close Panel")
            }
        }
        // Inset like the buttons on the right, so the thumbnail's corners follow the bar's.
        .padding(.leading, screenshot == nil ? 24 : 12)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .frame(width: PanelMetrics.width)
        .frame(minHeight: PanelMetrics.sourceBarHeight)
        .glassEffect(drawsGlass ? glassEffect.compactGlass : .identity)
        .gesture(WindowDragGesture())
    }
}

struct CompactNoticeView: View {
    @AppStorage(SettingsStore.panelGlassEffectKey) private var glassEffect = PanelGlassEffect.contrast
    let message: String
    var summary = ""
    var retry: (() -> Void)? = nil
    var close: () -> Void = {}
    var symbol = "exclamationmark.triangle"
    var actionTitle = L10n.shared.string("Settings")
    var actionSymbol = "gearshape"
    var recover: () -> Void = {}
    var action: (() -> Void)? = nil
    var isError = true
    /// True when the recovery entry copies, so the press shows itself for a moment.
    var copiesOnPress = false
    /// False when the panel root draws the source bar on its own growing surface.
    var showsBar = true
    @State private var confirmation = CopyConfirmation()

    var body: some View {
        VStack(spacing: 12) {
            if showsBar && !summary.isEmpty {
                PanelSourceBar(summary: summary, retry: retry, close: close)
            }
            PanelSegmentedControl(
                items: [
                    .init(title: message, symbol: symbol, action: recover, tint: isError ? .systemRed : nil),
                    .init(
                        title: "", symbol: recoverySymbol, action: runRecovery,
                        accessibilityLabel: recoveryLabel),
                ]
                    + (summary.isEmpty
                        ? [
                            .init(
                                title: "", symbol: "xmark", action: close,
                                accessibilityLabel: L10n.shared.string("Close Panel"),
                                key: .panelCancel)
                        ] : [])
            )
            .fixedSize()
            .frame(height: 36)
            .padding(.horizontal, 4)
            .glassEffect(glassEffect.compactGlass)

        }
        .frame(width: PanelMetrics.width)
        .accessibilityElement(children: .contain)
    }

    /// The recovery entry's glyph: a copy shows the copy glyph, then a checkmark for a moment, so the
    /// press is visible in a bar that is only glyphs.
    private var recoverySymbol: String {
        guard copiesOnPress else { return actionSymbol }
        return confirmation.isCopied ? "checkmark" : "document.on.document"
    }

    /// Its label, which is also what the glyph is called out as.
    private var recoveryLabel: String {
        confirmation.isCopied ? L10n.shared.string("Copied") : actionTitle
    }

    private func runRecovery() {
        (action ?? recover)()
        if copiesOnPress { confirmation.confirm() }
    }
}
