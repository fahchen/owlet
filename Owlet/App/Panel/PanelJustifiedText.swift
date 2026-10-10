import AppKit
import SwiftUI

/// SwiftUI Text has no justified alignment; use the native selectable wrapping label.
struct PanelJustifiedText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        // A click starts selection in the field editor, which falls back to the plain `font` and
        // drops the paragraph style unless the attributes are kept and the font matches.
        label.allowsEditingTextAttributes = true
        label.font = Self.font
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateNSView(_ label: NSTextField, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.lineSpacing = 2
        label.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: Self.font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
    }

    private static let font = NSFont.systemFont(ofSize: PanelMetrics.textSize, weight: .medium)

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        nsView.preferredMaxLayoutWidth = width
        let bounds = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)
        guard let size = nsView.cell?.cellSize(forBounds: bounds) else { return nil }
        return CGSize(width: width, height: ceil(size.height))
    }
}
