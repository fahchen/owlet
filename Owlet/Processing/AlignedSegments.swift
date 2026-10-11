import SwiftUI

/// 逐句对照 body: one pair per response segment, source above its target, so a wrapped line never
/// splits a pair and the correspondence comes from the model rather than from punctuation.
struct AlignedSegments: View {
    let segments: [TranslationResult.Segment]
    var sourceSize: CGFloat
    var targetSize: CGFloat
    var lineSpacing: CGFloat
    var pairSpacing: CGFloat
    /// What each side is, for a lookup in it; nil keeps that side plain selectable text.
    var sourceOrigin: LookupOrigin? = nil
    var targetOrigin: LookupOrigin? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                VStack(alignment: .leading, spacing: 3) {
                    LookupText(
                        text: segment.source, size: sourceSize, lineSpacing: lineSpacing, label: "Source",
                        origin: sourceOrigin)
                    LookupText(
                        text: segment.target, size: targetSize, weight: .medium, lineSpacing: lineSpacing,
                        origin: targetOrigin)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if index < segments.count - 1 {
                    Divider().padding(.vertical, pairSpacing)
                }
            }
        }
        // Selecting across pairs is expected, so the group reads as one selectable result.
        .accessibilityElement(children: .contain)
    }
}
