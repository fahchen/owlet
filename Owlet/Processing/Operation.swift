import AppKit
import Foundation

/// Text processing operation: translation to a target language, or polishing in place.
enum Operation: String, CaseIterable, Sendable {
    case translate
    case polish

    /// A resource rather than a `String`, so interpolating it into a message keeps that message
    /// localizable; `String(localized:)` is where a plain string is actually needed.
    var title: LocalizedStringResource {
        switch self {
        case .translate: "翻译"
        case .polish: "润色"
        }
    }

    /// The glyph for this operation: the tab in the page's tab view and the submit button.
    var symbol: String {
        switch self {
        case .translate: "translate"
        case .polish: "wand.and.sparkles"
        }
    }

    /// The operation's own color: its selected toolbar symbol and its history marker.
    var tint: NSColor {
        switch self {
        case .translate: .systemBlue
        case .polish: .systemGreen
        }
    }

    var prompt: String {
        switch self {
        case .translate: DefaultPrompts.translate
        case .polish: DefaultPrompts.polish
        }
    }
}
