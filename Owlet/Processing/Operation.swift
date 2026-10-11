import AppKit
import Foundation

/// Text processing operation: translation to a target language, or polishing in place.
enum Operation: String, CaseIterable, Sendable {
    case translate
    case polish

    /// A resource rather than a `String`, so interpolating it into a message keeps that message
    /// localizable; `L10n` is where a plain string is actually needed.
    var title: LocalizedStringResource {
        switch self {
        case .translate: "Translate"
        case .polish: "Polish"
        }
    }

    /// The operation's name in the chosen language, resolved when it is shown. `title` is a resource,
    /// so anything that displays it has to go through this to follow a live language change.
    var name: String { L10n.shared.string(title.key) }

    /// "Translating…" / "Polishing…", as its own catalog entry per operation.
    ///
    /// Not composed from `title`: a resource nested inside another one only resolves through `Text`,
    /// and everywhere else the outer lookup would see the already resolved title and fall back to the
    /// source string — a Chinese tail in an English interface.
    var progress: LocalizedStringResource {
        switch self {
        case .translate: "Translating…"
        case .polish: "Polishing…"
        }
    }

    /// "Translate Again" / "Polish Again", for the button that runs the current operation again.
    var retry: LocalizedStringResource {
        switch self {
        case .translate: "Translate Again"
        case .polish: "Polish Again"
        }
    }

    /// The empty input's placeholder, which names the operation the submit key will run.
    var placeholder: LocalizedStringResource {
        switch self {
        case .translate: "Type or paste text, ⌘↩ Translate"
        case .polish: "Type or paste text, ⌘↩ Polish"
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
