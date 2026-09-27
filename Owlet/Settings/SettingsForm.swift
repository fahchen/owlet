import SwiftUI

/// Main-window page footer, placed in a bottom safe-area bar: status left, glass actions right.
struct PageFooter<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading.font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            GlassEffectContainer {
                HStack(spacing: 8) { trailing }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }
}
