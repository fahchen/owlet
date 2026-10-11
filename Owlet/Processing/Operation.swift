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

    /// "翻译中…" / "润色中…", as its own catalog entry per operation.
    ///
    /// Not composed from `title`: a resource nested inside another one only resolves through `Text`,
    /// and everywhere else the outer lookup would see the already resolved title and fall back to the
    /// source string — a Chinese tail in an English interface.
    var progress: LocalizedStringResource {
        switch self {
        case .translate: "翻译中…"
        case .polish: "润色中…"
        }
    }

    /// "重新翻译" / "重新润色", for the button that runs the current operation again.
    var retry: LocalizedStringResource {
        switch self {
        case .translate: "重新翻译"
        case .polish: "重新润色"
        }
    }

    /// The empty input's placeholder, which names the operation the submit key will run.
    var placeholder: LocalizedStringResource {
        switch self {
        case .translate: "输入或粘贴文字，⌘↩翻译"
        case .polish: "输入或粘贴文字，⌘↩润色"
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
