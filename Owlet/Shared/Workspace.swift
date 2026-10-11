import SwiftUI

extension View {
    /// The main window pages' one surface: a glass card with the panel's fixed corner radius.
    func workspaceCard() -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius))
    }
}

/// The detail column's geometry, for content that sizes itself within it.
struct WorkspaceColumn {
    let width: CGFloat
    /// The toolbar's height over the column; scroll content already starts below it.
    let top: CGFloat
}

/// A list beside its detail, sized from the space offered rather than from either column, so the
/// window can always shrink the page instead of pushing it past its edges. No card: these are
/// library pages, and only the translate page's text sits on glass.
struct WorkspaceSplit<List: View, Detail: View>: View {
    @ViewBuilder let list: () -> List
    @ViewBuilder let detail: (WorkspaceColumn) -> Detail

    var body: some View {
        GeometryReader { proxy in
            let listWidth = min(max(proxy.size.width * 0.38, 220), 340)
            HStack(spacing: 0) {
                // A list takes the toolbar's height as safe area; it ignores a top content margin.
                list().safeAreaPadding(.top, proxy.safeAreaInsets.top).frame(width: listWidth)
                Divider()
                detail(WorkspaceColumn(width: max(proxy.size.width - listWidth - 1, 0), top: proxy.safeAreaInsets.top))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Up under the translucent toolbar, so both columns scroll beneath it; the toolbar's
            // height comes back as a content margin, so at rest their content starts below it.
            .contentMargins(.top, proxy.safeAreaInsets.top, for: .scrollContent)
            .frame(width: proxy.size.width)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
        }
    }
}

extension View {
    /// The split's list: no background of its own.
    func workspaceList() -> some View {
        listStyle(.inset)
            .scrollContentBackground(.hidden)
    }
}

/// The card's 36pt round glass action, as on the panel. Its tooltip names its key, which it binds
/// unless a menu command already owns that key.
struct CardButton: View {
    let title: String
    let symbol: String
    var key: KeyHint? = nil
    /// False for ⌘C, which the Edit menu's 拷贝 routes, so selected text still copies itself.
    var bindsKey = true
    /// A state that is on rather than an action, such as a stored bookmark: the glyph takes the
    /// accent and the label names the state instead of the command.
    var isOn = false
    let action: () -> Void

    var body: some View {
        CardGlassButton(
            title: title, symbol: symbol,
            tint: isOn ? Color.accentColor : Color.primary,
            key: bindsKey ? key?.shortcut : nil, keys: bindsKey ? key?.keys : nil, action: action
        )
    }
}

/// The one round glass button both card actions use, so the bookmark and the speaker are the same
/// control: 13pt glyph, `.glass`, circular border shape, 36pt.
struct CardGlassButton: View {
    let title: String
    let symbol: String
    var tint: Color = .primary
    var key: KeyboardShortcut? = nil
    /// The key's display string, when it has one, for the hover tip.
    var keys: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).foregroundStyle(tint)
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 13, weight: .medium))
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.extraLarge)
        .buttonSizing(.flexible)
        .frame(width: 36, height: 36)
        .keyboardShortcut(key)
        .hoverTip(title, keys: keys)
    }
}

extension FocusedValues {
    /// What ⌘C copies on the focused page when no text is selected: its result or expression.
    @Entry var copyText: String?
}
