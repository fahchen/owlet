import SwiftUI

/// The screen region's screenshot beside the source (BDR-0019): a thumbnail as tall as the compact
/// bar's, so the panel keeps its normal height; a click zooms it to the full width in place.
struct ScreenshotThumbnail: View {
    let image: NSImage
    /// Shared by the compact bar and the expanded panel, so the one thumbnail moves from the bar's
    /// leading edge to the source's trailing edge as the panel opens.
    var namespace: Namespace.ID?
    var zoomed = false
    /// Concentric with what holds it: the surface's radius less the inset to its edge.
    var cornerRadius = Self.expandedRadius
    let toggle: () -> Void

    static let height: CGFloat = 38
    /// Inside the expanded panel, which keeps it `contentInset` from its edge.
    static let expandedRadius = PanelMetrics.cornerRadius - PanelMetrics.contentInset
    /// Inside the compact bar, a capsule that keeps it 12pt from its edge.
    static let barRadius = PanelMetrics.sourceBarHeight / 2 - 12
    /// Wide enough for a line of text, so a very wide region does not crowd the source out.
    static let maxWidth: CGFloat = 180

    var body: some View {
        Button(action: toggle) {
            if zoomed {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                // Its own width at this height, so no blank band separates it from the text beside it.
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.width(of: image), height: Self.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
        .buttonStyle(.plain)
        .pointerStyle(zoomed ? .zoomOut : .zoomIn)
        .matchedScreenshot(in: namespace)
        .accessibilityLabel(L10n.shared.string("Screenshot"))
    }

    /// The width the picture has at the thumbnail's height, capped so a very wide region is cropped.
    static func width(of image: NSImage) -> CGFloat {
        let size = image.size
        guard size.height > 0 else { return height }
        return min(height * size.width / size.height, maxWidth)
    }
}

extension View {
    @ViewBuilder fileprivate func matchedScreenshot(in namespace: Namespace.ID?) -> some View {
        if let namespace { matchedGeometryEffect(id: "screenshot", in: namespace) } else { self }
    }
}
