import AppKit
import SwiftUI

/// SwiftUI's segmented Picker omits mixed image/text labels and equalizes action widths.
/// Keep the platform's momentary segmented control rather than drawing an action group.
struct PanelSegmentedControl: NSViewRepresentable {
    struct Item {
        let title: String
        let symbol: String
        let action: () -> Void
        var accessibilityLabel: String? = nil
        /// Label and symbol color; nil is the regular label color.
        var tint: NSColor? = nil
        /// The segment's key, shown with its label in the hover tip.
        var key: KeyHint? = nil
    }

    let items: [Item]

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = HoverSegmentedControl()
        control.tip = { [coordinator = context.coordinator] index in coordinator.tip(at: index) }
        control.trackingMode = .momentary
        control.segmentDistribution = .fit
        control.controlSize = .extraLarge
        control.font = .systemFont(ofSize: 13, weight: .medium)
        control.borderShape = .capsule
        control.cell?.isBordered = false
        control.target = context.coordinator
        control.action = #selector(Coordinator.activate(_:))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.items = items
        control.segmentCount = items.count
        for (index, item) in items.enumerated() {
            control.setLabel("", forSegment: index)
            control.setImage(Self.content(of: item, font: control.font), forSegment: index)
            control.setWidth(item.title.isEmpty ? 36 : 0, forSegment: index)
        }
        control.subviews.compactMap { $0 as? NSBox }.forEach { $0.removeFromSuperview() }
        // Borderless segments retain native tracking; system separators distinguish their actions.
        for index in items.indices.dropFirst() where items[index...].allSatisfy({ $0.title.isEmpty }) {
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            control.addSubview(separator)
            NSLayoutConstraint.activate([
                separator.trailingAnchor.constraint(
                    equalTo: control.trailingAnchor, constant: -CGFloat(items.count - index) * 36),
                separator.centerYAnchor.constraint(equalTo: control.centerYAnchor),
                separator.widthAnchor.constraint(equalToConstant: 1),
                separator.heightAnchor.constraint(equalToConstant: 16),
            ])
        }
        control.invalidateIntrinsicContentSize()
    }

    /// Symbol and title drawn into one non-template image. The panel never activates the app, so
    /// the native cell would draw a label and a template symbol in its dimmed, inactive gray; the
    /// image keeps the regular label color, or the item's tint, and the native bezel and tracking.
    /// Drawn on demand, so the label color follows light and dark appearance.
    static func content(of item: Item, font: NSFont?) -> NSImage {
        let font = font ?? .systemFont(ofSize: 13, weight: .medium)
        let symbol = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        let symbolSize = symbol?.size ?? .zero
        let titleSize = NSAttributedString(string: item.title, attributes: [.font: font]).size()
        let gap: CGFloat = item.title.isEmpty || symbol == nil ? 0 : 4
        let size = NSSize(
            width: ceil(symbolSize.width + gap + titleSize.width),
            height: ceil(max(symbolSize.height, titleSize.height)))
        let image = NSImage(size: size, flipped: false) { rect in
            let color = item.tint ?? .labelColor
            if let symbol = symbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color])) {
                symbol.draw(
                    in: NSRect(
                        x: 0, y: rect.midY - symbolSize.height / 2, width: symbolSize.width,
                        height: symbolSize.height))
            }
            NSAttributedString(string: item.title, attributes: [.font: font, .foregroundColor: color])
                .draw(at: NSPoint(x: symbolSize.width + gap, y: rect.midY - titleSize.height / 2))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = item.accessibilityLabel ?? item.title
        return image
    }

    @MainActor final class Coordinator: NSObject {
        var items: [Item]
        init(items: [Item]) { self.items = items }

        /// The hovered segment's label and key, for the hover tip.
        func tip(at index: Int) -> (String, String?)? {
            guard items.indices.contains(index) else { return nil }
            let item = items[index]
            // The label is a catalog key written at the call site, resolved here because the tip is a
            // String by the time AppKit asks for it.
            return (item.accessibilityLabel ?? item.title, item.key?.keys)
        }

        @objc func activate(_ control: NSSegmentedControl) {
            let index = control.selectedSegment
            guard items.indices.contains(index) else { return }
            items[index].action()
        }
    }
}

/// Reports the segment under the pointer, so each segment gets its own hover tip; the system tooltip
/// never shows in the never-active panel. Icon-only segments are a fixed 36pt at the trailing end,
/// and a titled one takes the rest, so the segment is found from the pointer's distance to the end.
final class HoverSegmentedControl: NSSegmentedControl {
    var tip: (Int) -> (String, String?)? = { _ in nil }
    private var hovered: Int?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let fixed = (0..<segmentCount).reversed().prefix { width(forSegment: $0) > 0 }
        var index = 0
        var edge = bounds.maxX
        for segment in fixed {
            edge -= width(forSegment: segment)
            if x >= edge {
                index = segment
                break
            }
            index = segment - 1
        }
        guard index != hovered else { return }
        HoverTip.shared.cancel(owner: ObjectIdentifier(self))
        hovered = index
        if let (title, keys) = tip(max(index, 0)) {
            HoverTip.shared.schedule(title, keys: keys, owner: ObjectIdentifier(self))
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        HoverTip.shared.cancel(owner: ObjectIdentifier(self))
    }
}
