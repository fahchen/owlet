import AppKit
import SwiftUI

/// The editable source with a clear area at its top trailing corner that the lines wrap around, for
/// the screenshot thumbnail (BDR-0019). SwiftUI text cannot flow around a view; TextKit's exclusion
/// paths can, so this one field is an `NSTextView`.
struct WrappingSourceEditor: NSViewRepresentable {
    @Binding var text: String
    /// The top trailing area the text keeps clear.
    let clearArea: CGSize

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> ClearingTextView {
        let view = ClearingTextView(usingTextLayoutManager: false)
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        // The view sizes its container itself, so the cleared corner moves with the width.
        view.textContainer?.widthTracksTextView = false
        view.typingAttributes = Self.attributes
        view.delegate = context.coordinator
        view.clearArea = clearArea
        setText(text, in: view)
        return view
    }

    func updateNSView(_ view: ClearingTextView, context: Context) {
        context.coordinator.text = $text
        view.clearArea = clearArea
        if view.string != text { setText(text, in: view) }
    }

    /// Lays the text out at the proposed width to measure it, then back at the view's own width:
    /// SwiftUI asks for several widths before it settles, and the last one asked is not the one set.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: ClearingTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        let height = view.layoutHeight(at: width)
        if view.bounds.width > 0 { view.fit(width: view.bounds.width) }
        return CGSize(width: width, height: max(height, clearArea.height))
    }

    private func setText(_ text: String, in view: NSTextView) {
        view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
    }

    /// The same look as the panel's plain source field.
    private static var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        return [
            .font: NSFont.systemFont(ofSize: PanelMetrics.sourceTextSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }

    /// Keeps the text container's width and the cleared corner in step with the view's own width.
    final class ClearingTextView: NSTextView {
        var clearArea: CGSize = .zero {
            didSet { if clearArea != oldValue { fit(width: bounds.width) } }
        }

        override func setFrameSize(_ size: NSSize) {
            super.setFrameSize(size)
            fit(width: size.width)
        }

        func fit(width: CGFloat) {
            guard let container = textContainer, width > 0 else { return }
            container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
            container.exclusionPaths = [
                NSBezierPath(
                    rect: CGRect(x: width - clearArea.width, y: 0, width: clearArea.width, height: clearArea.height))
            ]
        }

        func layoutHeight(at width: CGFloat) -> CGFloat {
            guard let container = textContainer, let layout = layoutManager else { return 0 }
            fit(width: width)
            layout.ensureLayout(for: container)
            return ceil(layout.usedRect(for: container).height)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}
