/// A fixed key the floating panel claims, shown on the 快捷键 page as a row instead of a recorder.
struct PanelKey: Equatable, Sendable {
    /// The glyph sequence printed in the row's trailing column.
    let keys: String
    /// What the key does to the panel's result.
    let title: String
    /// Where the key applies.
    let scope: String

    /// Mirrors `FloatingPanel.command(for:)`: replace, copy, cancel; Esc cancels a run before it closes.
    static let all: [PanelKey] = [
        PanelKey(keys: "⌘ ↩", title: "替换", scope: "浮动面板"),
        PanelKey(keys: "⌘ ⇧ C", title: "复制", scope: "浮动面板"),
        PanelKey(keys: "Esc", title: "停止处理 / 关闭", scope: "浮动面板"),
    ]
}
