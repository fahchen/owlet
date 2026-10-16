import SwiftUI

extension View {
    /// The inset a block of quoted text sits in — a captured request, a model reply: a system fill and
    /// one corner, with `showsGuide` adding the line at the left that marks the text as someone else's
    /// words. One implementation, so every quoted block matches (spec/DESIGN.md, 2026-10-16).
    func insetBlock(showsGuide: Bool = true, fill: AnyShapeStyle = AnyShapeStyle(.quaternary))
        -> some View
    {
        let box = padding(10).background(fill, in: .rect(cornerRadius: 8))
        return
            box
            .padding(.leading, showsGuide ? 14 : 0)
            .background(alignment: .leading) {
                Rectangle().fill(fill).frame(width: 2).opacity(showsGuide ? 1 : 0)
            }
    }

    /// A failure's message: the same inset, one step lighter — the system's own next hierarchical fill,
    /// which reads as a quiet step off the page rather than as a grey plate — and without the guide,
    /// because this is a line of interface text rather than captured material.
    func failureBlock() -> some View {
        insetBlock(showsGuide: false, fill: AnyShapeStyle(.quinary))
    }
}
