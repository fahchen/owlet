import AppKit
import SwiftUI

/// The app's own tooltip: a small glass capsule with what a button does and its key. AppKit only
/// shows tooltips for the active app, and the floating panel never activates Owlet, so the system's
/// `.help` never appears there; this one lives in its own window, so it shows anywhere, past the edge
/// of the view that asked for it too.
@MainActor final class HoverTip {
    static let shared = HoverTip()

    private let window: NSPanel = {
        let window = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.level = .popUpMenu
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        return window
    }()
    /// The label's hosting view inside a plain container, both sized by hand. A hosting view that is
    /// the window's content view, or that reports an intrinsic size, joins the window's constraint
    /// passes, and the glass inside it keeps requesting more until AppKit raises an exception.
    private let host: NSHostingView<HoverTipLabel> = {
        let host = NSHostingView(rootView: HoverTipLabel(label: { Text(verbatim: "") }, keys: nil))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        return host
    }()
    private var pending: Task<Void, Never>?
    private var owner: AnyHashable?
    private var clicks: Any?

    /// Shows the tip after the system's hover delay, under the pointer, unless the pointer leaves first.
    func schedule(_ label: @escaping () -> Text, keys: String?, owner: AnyHashable) {
        pending?.cancel()
        self.owner = owner
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.show(label, keys: keys)
        }
    }

    /// Hides the tip, but only for the view that asked: moving straight onto another button must not
    /// let the old one's exit hide the new one's tip.
    func cancel(owner: AnyHashable) {
        guard self.owner == owner else { return }
        hide()
    }

    /// For a caller holding a title that is already resolved — an AppKit view with a `String` — so it
    /// is shown as it stands rather than looked up a second time.
    func schedule(_ title: String, keys: String?, owner: AnyHashable) {
        schedule({ Text(verbatim: title) }, keys: keys, owner: owner)
    }

    private func show(_ label: @escaping () -> Text, keys: String?) {
        let content = HoverTipLabel(label: label, keys: keys)
        host.rootView = content
        // Measured off-screen, so the shown view never has to report a size of its own.
        let size = NSHostingController(rootView: content).sizeThatFits(
            in: CGSize(width: 600, height: 200))
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 22)
        // Above the pointer when there is no room below it, as at the bottom of the screen.
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let visible = screen.visibleFrame
            if origin.y < visible.minY { origin.y = mouse.y + 16 }
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        if host.superview == nil {
            let container = NSView()
            container.addSubview(host)
            window.contentView = container
        }
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        host.frame = NSRect(origin: .zero, size: size)
        window.orderFrontRegardless()
        // A click acts on the button, so the tip it was explaining goes away.
        if clicks == nil {
            clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
                [weak self] event in
                self?.hide()
                return event
            }
        }
    }

    private func hide() {
        pending?.cancel()
        pending = nil
        owner = nil
        window.orderOut(nil)
        if let clicks { NSEvent.removeMonitor(clicks) }
        clicks = nil
    }
}

private struct HoverTipLabel: View {
    /// Built by the view that asked for the tip, so `Text` resolves the catalog on its side and the
    /// tooltip and the accessibility hint can never show two different strings.
    let label: () -> Text
    let keys: String?

    var body: some View {
        HStack(spacing: 8) {
            label()
            if let keys { Text(keys).foregroundStyle(.secondary) }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: Capsule())
        .padding(6)
    }
}

extension View {
    /// A tip whose title is interface wording: `Text` resolves it, so the wording follows the
    /// interface language and the catalog stays the only place a phrase is written.
    func hoverTip(_ title: LocalizedStringKey, keys: String? = nil) -> some View {
        hoverTip(label: { Text(title) }, keys: keys)
    }

    /// A tip naming one of the app's fixed keys, whose title is itself a catalog key.
    func hoverTip(_ key: KeyHint, title: LocalizedStringResource? = nil) -> some View {
        hoverTip(
            label: {
                // `title` is a resource and `key.title` is a catalog key, so the lookup happens here
                // rather than at the call site — and never by interpolating a resource into a String.
                Text(verbatim: L10n.shared.string(title?.key ?? key.title))
            },
            keys: title == nil ? key.keys : nil)
    }

    /// A tip whose text is runtime content — the source a panel is showing — rather than interface
    /// wording, so it is shown as it stands instead of being looked up.
    func hoverTip(verbatim title: String, keys: String? = nil) -> some View {
        hoverTip(label: { Text(verbatim: title) }, keys: keys)
    }

    /// The one place a tip is built, so every overload above shares one implementation.
    private func hoverTip(label: @escaping () -> Text, keys: String?) -> some View {
        modifier(HoverTipContent(label: label, keys: keys))
    }
}

private struct HoverTipContent: ViewModifier {
    let label: () -> Text
    let keys: String?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside {
                    HoverTip.shared.schedule(label, keys: keys, owner: id)
                } else {
                    HoverTip.shared.cancel(owner: id)
                }
            }
            .onDisappear { HoverTip.shared.cancel(owner: id) }
            .accessibilityHint(keys.map { "\(label()) \($0)" } ?? "\(label())")
    }
}
