import SwiftUI

/// The screen region's screenshot beside the source (BDR-0019): small enough that the panel keeps
/// its normal height, and a click shows it at full size to check the recognised text against.
struct ScreenshotThumbnail: View {
    let image: NSImage
    /// Shared by the compact bar and the expanded panel, so the one thumbnail moves from the bar's
    /// leading edge to the source's trailing edge as the panel opens.
    var namespace: Namespace.ID?
    @State private var showsFull = false

    static let height: CGFloat = 38
    /// Wide enough for a line of text, so a very wide region does not crowd the source out.
    static let maxWidth: CGFloat = 180
    private static let fullWidth: CGFloat = 640

    var body: some View {
        Button {
            showsFull.toggle()
        } label: {
            // Its own width at this height, so no blank band separates it from the text beside it.
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: Self.height)
                .clipped()
                .clipShape(ConcentricRectangle(corners: .concentric(minimum: 6), isUniform: true))
        }
        .buttonStyle(.plain)
        .matchedScreenshot(in: namespace)
        .accessibilityLabel(L10n.shared.string("Screenshot"))
        .hoverTip("Screenshot")
        // A fixed size: a popover that sized itself from its content would resize the panel's
        // hosting view in a loop (see AGENTS.md).
        .popover(isPresented: $showsFull) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: fullSize.width, height: fullSize.height)
                .padding(10)
        }
    }

    /// The width the picture has at the thumbnail's height, capped so a very wide region is cropped.
    private var width: CGFloat {
        let size = image.size
        guard size.height > 0 else { return Self.height }
        return min(Self.height * size.width / size.height, Self.maxWidth)
    }

    private var fullSize: CGSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return CGSize(width: Self.fullWidth, height: 200) }
        let width = min(size.width, Self.fullWidth)
        return CGSize(width: width, height: width * size.height / size.width)
    }
}

extension View {
    @ViewBuilder fileprivate func matchedScreenshot(in namespace: Namespace.ID?) -> some View {
        if let namespace { matchedGeometryEffect(id: "screenshot", in: namespace) } else { self }
    }
}
