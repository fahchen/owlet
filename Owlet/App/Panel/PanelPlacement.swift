import AppKit

/// Pure placement math for the floating panel, in AppKit screen coordinates (bottom-left origin).
enum PanelPlacement {
    /// Where the panel is anchored; resizes re-place it from the anchor, not from the old frame.
    enum Anchor: Equatable {
        /// Top edge centered on the point; nil is the default spot on the main screen.
        case topCenter(NSPoint?)
        /// Top-left corner at the point (mouse fallback).
        case topLeft(NSPoint)
        /// Below the selection rect, flipped above when there is no room below.
        case below(NSRect)

        /// Point used to pick the screen; nil means the main screen.
        var reference: NSPoint? {
            switch self {
            case .topCenter(let point): point
            case .topLeft(let point): point
            case .below(let rect): NSPoint(x: rect.midX, y: rect.midY)
            }
        }
    }

    /// Space between the selection and the panel.
    static let gap: CGFloat = 6

    /// Upper-center of `visible`, like Spotlight: top edge a fifth of the way down.
    static func defaultTopCenter(in visible: NSRect) -> NSPoint {
        NSPoint(x: visible.midX, y: visible.maxY - visible.height / 5)
    }

    /// Frame of `size` for `anchor`, kept inside `visible`.
    static func frame(size: NSSize, anchor: Anchor, within visible: NSRect) -> NSRect {
        switch anchor {
        case .topCenter(let point):
            let point = point ?? defaultTopCenter(in: visible)
            return frame(size: size, topLeft: NSPoint(x: point.x - size.width / 2, y: point.y), within: visible)
        case .topLeft(let point):
            return frame(size: size, topLeft: point, within: visible)
        case .below(let rect):
            let below = rect.minY - gap
            let above = rect.maxY + gap + size.height
            let flip = below - size.height < visible.minY && above <= visible.maxY
            return frame(size: size, topLeft: NSPoint(x: rect.minX, y: flip ? above : below), within: visible)
        }
    }

    /// Frame of `size` anchored at `topLeft`, shifted and height-capped to stay inside `visible`.
    static func frame(size: NSSize, topLeft: NSPoint, within visible: NSRect) -> NSRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let x = min(max(topLeft.x, visible.minX), visible.maxX - width)
        let top = min(max(topLeft.y, visible.minY + height), visible.maxY)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }

    /// Converts an AX rect (global, top-left origin at the primary screen, y down) to AppKit
    /// coordinates (bottom-left origin at the primary screen, y up).
    static func appKitRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> NSRect {
        NSRect(
            x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Anchor for the follow-selection mode: below the selection, else at the mouse.
    static func followAnchor(selectionBounds: NSRect?, mouse: NSPoint) -> Anchor {
        selectionBounds.map(Anchor.below) ?? .topLeft(mouse)
    }
}
