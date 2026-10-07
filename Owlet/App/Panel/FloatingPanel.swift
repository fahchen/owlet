import AppKit
import SwiftUI

/// Transparent host for the panel’s separate native glass surfaces.
/// Dismisses on intent only — Esc, 完成, or a click outside — never on
/// losing key, because an inactive app can take and drop key with no user action at all.
/// Not final: tests that only assert controller state substitute a panel that stays off screen.
class FloatingPanel: NSPanel, NSWindowDelegate {
    /// What the panel does with a key it claims. Owlet is an accessory app whose panel never
    /// activates it, so a SwiftUI key equivalent would have to travel through a menu bar that is
    /// never active: the panel reads the key event itself instead.
    enum Command {
        case replace
        case copy
        case cancel
    }

    var onClose: () -> Void = {}
    /// User drag ended at this top-center point; the panel then stays anchored there.
    var onDrag: (NSPoint) -> Void = { _ in }
    var onCommand: (Command) -> Void = { _ in }
    /// While a write-back is in flight the panel lets go of the keyboard without dismissing itself:
    /// the keystroke has to reach the app underneath, and the panel has to survive to report a miss.
    var suspendsDismissal = false
    /// Injectable so placement tests can disable the resize animation.
    var prefersReducedMotion: () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    private var anchor = PanelPlacement.Anchor.topCenter(nil)
    /// Set while the panel moves itself, so only user drags reach `onDrag`.
    private var placing = false
    private let host: NSHostingController<PanelRootView>
    private var sizeObservation: NSKeyValueObservation?
    private var closing = false
    /// Live while the panel is up; removed on close so the panel holds nothing after it goes.
    private var keys: Any?
    /// Live while the panel is visible; a click that lands outside the glass dismisses it.
    private var mouseMonitor: Any?

    init(rootView: PanelRootView) {
        host = NSHostingController(rootView: rootView)
        host.sizingOptions = .preferredContentSize
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        delegate = self
        // Keep intrinsic hosting size out of window constraints; preferredContentSize drives placement.
        let surface = NSView()
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.frame = surface.bounds
        host.view.autoresizingMask = [.width, .height]
        surface.addSubview(host.view)
        contentView = surface
        sizeObservation = host.observe(\.preferredContentSize) { [weak self] host, _ in
            MainActor.assumeIsolated { self?.fit(host.preferredContentSize) }
        }
    }

    /// Shows at `anchor`, kept inside the visible frame of the screen containing it.
    func show(anchor: PanelPlacement.Anchor) {
        self.anchor = anchor
        place(size: host.preferredContentSize)
        orderFrontRegardless()
        makeKey()
        // Becoming key hands the responder to SwiftUI's key view proxy, which focuses the first
        // control; the panel has nothing to type into on open, so it starts with nothing focused.
        // A click or Tab still reaches every control.
        makeFirstResponder(nil)
        if keys == nil { keys = watchKeys() }
        if mouseMonitor == nil { mouseMonitor = watchMouse() }
    }

    /// Hands the keyboard to whatever is underneath without dismissing the panel: a synthetic ⌘V
    /// follows the keyboard, so the panel cannot still own it when the keystroke goes out.
    func releaseKeyboard() {
        orderOut(nil)
        stopWatchingMouse()
    }

    /// ⌘↩ replaces, ⌘⇧C copies, Esc dismisses; every other key stays with the panel's controls.
    /// Return and keypad Enter both count, so a full keyboard reaches replace either way.
    static func command(for event: NSEvent) -> Command? {
        switch (event.keyCode, event.modifierFlags.intersection(.deviceIndependentFlagsMask)) {
        case (36, .command), (76, .command): .replace
        case (8, [.command, .shift]): .copy
        case (53, []): .cancel
        default: nil
        }
    }

    /// Consumes the keys this panel claims, so they never reach a text field behind them.
    private func watchKeys() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self, let command = Self.command(for: event) else {
                return event
            }
            onCommand(command)
            return nil
        }
    }

    /// Installs the outside-click monitor while the panel is visible: a click that misses the glass
    /// is a dismissal, but losing key — by deactivation or a system dialog — is not.
    private func watchMouse() -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] _ in
            self?.dismissIfOutside(NSEvent.mouseLocation)
        }
    }

    /// Closes when a click landed outside the glass; a click on the panel is the user acting on it.
    func dismissIfOutside(_ screenPoint: NSPoint) {
        guard isVisible, !suspendsDismissal, Self.dismisses(screenPoint, from: frame) else { return }
        close()
    }

    /// Whether a click is a click outside the glass. Pure, so the rule is tested without a window.
    static func dismisses(_ point: NSPoint, from frame: NSRect) -> Bool { !frame.contains(point) }

    /// Whether the outside-click monitor is installed, so a test can prove it follows visibility.
    var watchesMouse: Bool { mouseMonitor != nil }

    private func stopWatchingMouse() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    func windowDidMove(_ notification: Notification) {
        guard !placing else { return }
        let topCenter = NSPoint(x: frame.midX, y: frame.maxY)
        anchor = .topCenter(topCenter)
        onDrag(topCenter)
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
    override func close() {
        guard !closing else { return }
        closing = true
        defer { closing = false }
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        stopWatchingMouse()
        onClose()
        super.close()
    }

    /// Content-driven resizes re-place from the anchor, so the compact bar expands downward
    /// (or, below a selection near the screen bottom, flips above it).
    private func fit(_ size: NSSize) {
        guard size != frame.size else { return }
        place(size: size)
    }

    private func place(size: NSSize) {
        let screen = anchor.reference.flatMap { point in
            NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
        }
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else {
            // No screen to place on: keep the current top-center so the panel still expands downward.
            let top = NSPoint(x: frame.midX, y: frame.maxY)
            grow(
                to: NSRect(
                    x: top.x - size.width / 2, y: top.y - size.height, width: size.width,
                    height: size.height))
            invalidateShadow()
            return
        }
        grow(to: PanelPlacement.frame(size: size, anchor: anchor, within: visible))
        // The shape changed with the size, so the shadow has to be recomputed from it.
        invalidateShadow()
    }

    /// The panel grows taller when the compact strip becomes the expanded panel, so the window is
    /// resized with the same native spring as its content; Reduce Motion takes the direct path.
    private func grow(to rect: NSRect) {
        // The animation's own frames move the window, so placement stays flagged for its whole
        // duration; otherwise a mid-animation frame is mistaken for a drag and saved as the anchor.
        placing = true
        guard isVisible, !prefersReducedMotion() else {
            setFrame(rect, display: true)
            placing = false
            return
        }
        NSAnimationContext.animate(.spring(duration: 0.36, bounce: 0.12)) {
            animator().setFrame(rect, display: true)
        } completion: { [weak self] in
            self?.placing = false
        }
    }
}
