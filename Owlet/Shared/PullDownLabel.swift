import SwiftUI

extension View {
    /// The left and right inset a pull-down gives its own content, for the ones whose label is a view of
    /// ours. A `Menu`'s insets are the system's, so padding the label is the only way to widen them;
    /// one value keeps every pull-down in the interface matched.
    func pullDownLabelInset() -> some View {
        padding(.horizontal, 6)
    }
}
