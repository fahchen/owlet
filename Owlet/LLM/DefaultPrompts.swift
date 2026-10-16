import Foundation

/// The text the app sends the model: the two behavior prompts, the task descriptions, the response
/// shapes and the examples.
///
/// They live in `ModelPrompts.json` rather than in this file so the sources hold no Chinese: these
/// strings address the model, not the user, so they are not in the string catalog. That file is the
/// single copy — there is no second one under `spec/`, so the two cannot drift. The two behavior
/// prompts are the exception to "one text for every language": they are read and edited in the
/// interface, so `DefaultPrompts` picks the entry for the language being shown.
enum ModelPrompts {
    /// Everything in the file, or an empty dictionary when the resource is missing, which a test
    /// catches rather than an empty prompt reaching the model silently.
    static let all: [String: String] = {
        // `Bundle.main` is the running app, which is not the bundle under test: the test host loads the
        // app's resources, so both are searched before giving up.
        let candidates = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in candidates {
            guard let url = bundle.url(forResource: "ModelPrompts", withExtension: "json"),
                let data = try? Data(contentsOf: url),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else { continue }
            return object
        }
        return [:]
    }()

    static subscript(key: String) -> String { all[key] ?? "" }

    /// The same text with its `%@` values filled in, for the prompts assembled at request time.
    static func format(_ key: String, _ arguments: String...) -> String {
        var text = self[key]
        for argument in arguments {
            guard let range = text.range(of: "%@") else { break }
            text.replaceSubrange(range, with: argument)
        }
        return text
    }
}

/// The two behavior prompts, under the name the rest of the app knows them by.
///
/// Unlike the task descriptions and examples, these two follow the interface language: they are the
/// text a user reads and edits on the Model page, and a prompt written in a language the reader cannot
/// read is not editable. Each has one entry per shipped language, keyed `<name>.<locale>`, and the bare
/// key holds the English source text, which is also what a language without its own entry gets.
enum DefaultPrompts {
    static var translate: String { text("translate") }
    static var polish: String { text("polish") }

    /// The prompt for one operation in the interface language.
    static func text(_ name: String) -> String {
        let localized = ModelPrompts["\(name).\(L10n.shared.currentLanguage)"]
        return localized.isEmpty ? ModelPrompts[name] : localized
    }

    /// Every shipped language's text for one prompt. Text equal to any of them is a prompt the user
    /// never edited, whichever language it was shown in — which is what lets a stored prompt that is
    /// still the default be dropped when the language changes rather than pinning the old language.
    static func shippedTexts(of name: String) -> [String] {
        ([name] + AppLanguage.supported.map { "\(name).\($0)" })
            .map { ModelPrompts[$0] }
            .filter { !$0.isEmpty }
    }
}
