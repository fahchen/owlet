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
        let host = NSHostingView(rootView: HoverTipLabel(title: "", keys: nil))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        return host
    }()
    private var pending: Task<Void, Never>?
    private var owner: AnyHashable?
    private var clicks: Any?

    /// Shows the tip after the system's hover delay, under the pointer, unless the pointer leaves first.
    func schedule(_ title: String, keys: String?, owner: AnyHashable) {
        pending?.cancel()
        self.owner = owner
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.show(title, keys: keys)
        }
    }

    /// Hides the tip, but only for the view that asked: moving straight onto another button must not
    /// let the old one's exit hide the new one's tip.
    func cancel(owner: AnyHashable) {
        guard self.owner == owner else { return }
        hide()
    }

    private func show(_ title: String, keys: String?) {
        let label = HoverTipLabel(title: title, keys: keys)
        host.rootView = label
        // Measured off-screen, so the shown view never has to report a size of its own.
        let size = NSHostingController(rootView: label).sizeThatFits(in: CGSize(width: 600, height: 200))
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
    let title: String
    let keys: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
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
    /// The app's tooltip: the action and its key, shown on hover even in the never-active panel.
    func hoverTip(_ title: String, keys: String? = nil) -> some View {
        modifier(HoverTipModifier(title: title, keys: keys))
    }

    func hoverTip(_ key: KeyHint, title: String? = nil) -> some View {
        hoverTip(title ?? String(localized: "\(key.title)"), keys: key.keys)
    }
}

private struct HoverTipModifier: ViewModifier {
    let title: String
    let keys: String?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside {
                    HoverTip.shared.schedule(title, keys: keys, owner: id)
                } else {
                    HoverTip.shared.cancel(owner: id)
                }
            }
            .onDisappear { HoverTip.shared.cancel(owner: id) }
            .accessibilityHint(keys.map { "\(title) \($0)" } ?? title)
    }
}
