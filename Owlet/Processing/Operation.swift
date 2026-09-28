/// Text processing operation: translation to a target language, or polishing in place.
enum Operation: String, CaseIterable, Sendable {
    case translate
    case polish

    var title: String {
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

    var prompt: String {
        switch self {
        case .translate: DefaultPrompts.translate
        case .polish: DefaultPrompts.polish
        }
    }
}
