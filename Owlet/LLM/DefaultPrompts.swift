import Foundation

/// The text the app sends the model: the two behavior prompts, the task descriptions, the response
/// shapes and the examples.
///
/// They live in `ModelPrompts.json` rather than in this file so the sources hold no Chinese: these
/// strings address the model, not the user, so they are deliberately not localized. That file is the
/// single copy — there is no second one under `spec/`, so the two cannot drift.
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
enum DefaultPrompts {
    static var translate: String { ModelPrompts["translate"] }
    static var polish: String { ModelPrompts["polish"] }
}
