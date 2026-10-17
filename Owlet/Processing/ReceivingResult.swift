import SwiftUI

/// The pieces a stream has already completed, laid out the way the chosen display mode lays the
/// finished result out: Sentence by Sentence grows the pairs as they close, Source / Result Sections
/// grows the result text alone. What the user reads while waiting is therefore the shape they will
/// keep, with no jump from pairs to whole text when the reply is validated.
///
/// Display only: the pieces have never been through `TranslationResult.parse` (BDR-0017), so no
/// origin is wired and nothing here offers a lookup, copy, replace or history.
struct ReceivingResult: View {
    let segments: [TranslationResult.Segment]
    let mode: TranslationDisplayMode
    /// Whether the sectioned text is justified, as the finished result it grows into is.
    var justified = false

    var body: some View {
        if mode == .aligned {
            AlignedSegments(
                segments: segments, sourceSize: PanelMetrics.sourceTextSize,
                targetSize: PanelMetrics.textSize,
                lineSpacing: 4, pairSpacing: 12,
                sourceOrigin: nil, targetOrigin: nil
            )
            .accessibilityLabel(L10n.shared.string("Generating the result"))
        } else {
            LookupText(
                text: Self.text(of: segments), size: PanelMetrics.textSize, weight: .medium,
                justified: justified, label: L10n.shared.string("Generating the result"), origin: nil
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The sectioned layout's text: the completed targets joined exactly as a finished result joins
    /// them (`TranslationResult.text`), so the text only grows as pairs close.
    static func text(of segments: [TranslationResult.Segment]) -> String {
        segments.map(\.target).joined()
    }
}
