import AppKit
import SwiftUI

/// The processing edge highlight: an accent ring whose bright sheen sweeps around the panel while
/// it breathes, with a soft inner glow. Reduce Motion holds it still at one visible level.
enum ProcessingEdge {
    static let brightOpacity: Float = 1
    static let dimOpacity: Float = 0.45
    /// Reduce Motion keeps a single visible level instead of pulsing.
    static let steadyOpacity: Float = 0.75
    static let duration: CFTimeInterval = 1.6
    /// One full turn of the sheen around the panel.
    static let sweepDuration: CFTimeInterval = 2.4
    static let lineWidth: CGFloat = 2
    /// Blur of the glow; the panel's rounded mask keeps only its inner half.
    static let glowRadius: CGFloat = 6

    /// The edge's opacity; a steady value whenever Reduce Motion is on.
    static func opacity(reduceMotion: Bool, bright: Bool) -> Float {
        reduceMotion ? steadyOpacity : (bright ? brightOpacity : dimOpacity)
    }

    /// Light accent at rest, near-white at the sheen, so the ring stays bright in the app's one colour.
    static func colors(accent: NSColor) -> [CGColor] {
        let sheen = accent.blended(withFraction: 0.8, of: .white) ?? accent
        let base = accent.blended(withFraction: 0.3, of: .white) ?? accent
        return [base, accent, sheen, accent, base].map(\.cgColor)
    }
}

/// Window content container masked to the glass corner radius that also hosts the processing edge,
/// so the mark rides the exact panel edge without becoming another view.
final class PanelSurface: NSView {
    /// Breathes and glows; holds the ring.
    let edge = CALayer()
    /// Conic accent sweep, clipped to the ring and rotated while processing.
    let sheen = CAGradientLayer()
    private let ring = CALayer()
    private let stroke = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        edge.opacity = 0
        edge.zPosition = 1
        edge.shadowOffset = .zero
        edge.shadowRadius = ProcessingEdge.glowRadius
        edge.shadowOpacity = 0.9
        stroke.fillColor = nil
        stroke.strokeColor = NSColor.black.cgColor
        stroke.lineWidth = ProcessingEdge.lineWidth
        sheen.type = .conic
        sheen.startPoint = CGPoint(x: 0.5, y: 0.5)
        sheen.endPoint = CGPoint(x: 0.5, y: 0)
        ring.mask = stroke
        ring.addSublayer(sheen)
        edge.addSublayer(ring)
        layer?.addSublayer(edge)
    }

    required init?(coder: NSCoder) { fatalError("PanelSurface is created in code only") }

    override func layout() {
        super.layout()
        // A dynamic system colour cannot be blended; resolve it to plain sRGB first.
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor
        sheen.colors = ProcessingEdge.colors(accent: accent)
        edge.shadowColor = (accent.blended(withFraction: 0.4, of: .white) ?? accent).cgColor
        edge.frame = bounds
        ring.frame = bounds
        stroke.frame = bounds
        // A square wide enough to cover the ring at every angle of its turn.
        let side = hypot(bounds.width, bounds.height)
        sheen.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        sheen.position = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = layer?.cornerRadius ?? 0
        let inset = stroke.lineWidth / 2
        let path = CGPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerWidth: radius,
            cornerHeight: radius, transform: nil)
        stroke.path = path
        // An explicit shadow path keeps the glow from being re-rendered every frame of the sweep.
        edge.shadowPath = path.copy(
            strokingWithWidth: stroke.lineWidth, lineCap: .butt, lineJoin: .round, miterLimit: 0)
    }
}

/// Frameless, fully transparent panel whose only content is a native glass view, so the window
/// server draws the glass alone. Dismisses on intent only — Esc, 完成, or a click outside — never on
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
    /// Overridable so a test can prove Reduce Motion holds the processing edge steady.
    var prefersReducedMotion: () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    /// Key of the breathing animation, so a test can tell it is running and remove it cleanly.
    static let breatheKey = "processingEdge"
    /// Key of the sheen's turn around the panel.
    static let sweepKey = "processingSweep"
    private var anchor = PanelPlacement.Anchor.topCenter(nil)
    /// Set while the panel moves itself, so only user drags reach `onDrag`.
    private var placing = false
    private let host: NSHostingController<PanelRootView>
    private var sizeObservation: NSKeyValueObservation?
    private var closing = false
    /// The rounded shape the window presents to the window server, so the shadow follows the glass
    /// instead of the rectangle around it; it also hosts the processing edge.
    private let shape = PanelSurface()
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
        // The glass needs a shadow to read against a light background, and a borderless window takes
        // its shape — and so its shadow — from its content layer.
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        delegate = self
        // The glass keeps its own default corner radius and style. It is wrapped in a container
        // masked to that same shape, because a square layer is what used to cast a square shadow
        // around rounded glass: the rounded mask is what the window server now follows.
        let glass = NSGlassEffectView()
        glass.contentView = host.view
        glass.frame = shape.bounds
        glass.autoresizingMask = [.width, .height]
        shape.addSubview(glass)
        shape.wantsLayer = true
        shape.layer?.cornerRadius = glass.cornerRadius
        shape.layer?.masksToBounds = true
        contentView = shape
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

    /// Runs or stops the processing edge: a breathing, sweeping accent ring, and a steady mark under Reduce
    /// Motion so the state never depends on the animation alone.
    func setProcessing(_ active: Bool) {
        guard let surface = contentView as? PanelSurface else { return }
        let edge = surface.edge
        edge.removeAnimation(forKey: Self.breatheKey)
        surface.sheen.removeAnimation(forKey: Self.sweepKey)
        guard active else {
            edge.opacity = 0
            return
        }
        let reduced = prefersReducedMotion()
        edge.opacity = ProcessingEdge.opacity(reduceMotion: reduced, bright: true)
        guard !reduced else { return }
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = ProcessingEdge.opacity(reduceMotion: false, bright: false)
        breathe.toValue = ProcessingEdge.opacity(reduceMotion: false, bright: true)
        breathe.duration = ProcessingEdge.duration
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        edge.add(breathe, forKey: Self.breatheKey)
        let sweep = CABasicAnimation(keyPath: "transform.rotation.z")
        sweep.fromValue = 0
        sweep.toValue = -2 * CGFloat.pi
        sweep.duration = ProcessingEdge.sweepDuration
        sweep.repeatCount = .infinity
        surface.sheen.add(sweep, forKey: Self.sweepKey)
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
    /// resized over an ease rather than snapped; Reduce Motion takes the direct path.
    private func grow(to rect: NSRect) {
        // The animation's own frames move the window, so placement stays flagged for its whole
        // duration; otherwise a mid-animation frame is mistaken for a drag and saved as the anchor.
        placing = true
        guard !prefersReducedMotion() else {
            setFrame(rect, display: true)
            placing = false
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(rect, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.placing = false }
        }
    }
}
