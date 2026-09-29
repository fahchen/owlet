import Foundation

/// The 文本处理 arrangement: side by side only once the content area is wide enough to keep both
/// the source and the result readable, stacked below that.
enum ProcessingLayout: Equatable {
    case sideBySide
    case stacked

    /// The content-area width at which both columns still fit.
    static let sideBySideThreshold: CGFloat = 600

    static func choose(width: CGFloat) -> ProcessingLayout {
        width >= sideBySideThreshold ? .sideBySide : .stacked
    }
}
