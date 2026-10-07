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
    }

    let items: [Item]

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
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
            control.setLabel(item.title, forSegment: index)
            control.setImage(
                NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.accessibilityLabel ?? item.title),
                forSegment: index)
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

    @MainActor final class Coordinator: NSObject {
        var items: [Item]
        init(items: [Item]) { self.items = items }

        @objc func activate(_ control: NSSegmentedControl) {
            let index = control.selectedSegment
            guard items.indices.contains(index) else { return }
            items[index].action()
        }
    }
}
