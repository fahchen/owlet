import SwiftUI

/// Sentence by Sentence body: one pair per response segment, source above its target, so a wrapped line never
/// splits a pair and the correspondence comes from the model rather than from punctuation.
///
/// Pairs are separated by `pairSpacing` alone; the rule that used to sit between them is gone, and
/// the spacing is what groups each pair.
struct AlignedSegments: View {
    let segments: [TranslationResult.Segment]
    var sourceSize: CGFloat
    var targetSize: CGFloat
    var lineSpacing: CGFloat
    /// The gap between one pair and the next; the gap inside a pair is fixed and smaller.
    var pairSpacing: CGFloat
    /// What each side is, for a lookup in it; nil keeps that side plain selectable text.
    var sourceOrigin: LookupOrigin? = nil
    var targetOrigin: LookupOrigin? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: pairSpacing) {
            ForEach(segments.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 3) {
                    LookupText(
                        text: segments[index].source, size: sourceSize, lineSpacing: lineSpacing,
                        label: "Source", origin: sourceOrigin)
                    LookupText(
                        text: segments[index].target, size: targetSize, weight: .medium,
                        lineSpacing: lineSpacing, origin: targetOrigin)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Selecting across pairs is expected, so the group reads as one selectable result.
        .accessibilityElement(children: .contain)
    }
}
