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

    var prompt: String {
        switch self {
        case .translate: DefaultPrompts.translate
        case .polish: DefaultPrompts.polish
        }
    }
}
