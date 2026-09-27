import SwiftUI

/// 逐句对照 body: one pair per response segment, source above its target, so a wrapped line never
/// splits a pair and the correspondence comes from the model rather than from punctuation.
struct AlignedSegments: View {
    let segments: [TranslationResult.Segment]
    var sourceSize: CGFloat
    var targetSize: CGFloat
    var lineSpacing: CGFloat
    var pairSpacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                VStack(alignment: .leading, spacing: 3) {
                    Text(segment.source)
                        .font(.system(size: sourceSize))
                        .lineSpacing(lineSpacing)
                    Text(segment.target)
                        .font(.system(size: targetSize))
                        .lineSpacing(lineSpacing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                if index < segments.count - 1 {
                    Divider().padding(.vertical, pairSpacing)
                }
            }
        }
        // Selecting across pairs is expected, so the group reads as one selectable result.
        .accessibilityElement(children: .contain)
    }
}
