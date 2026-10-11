import SwiftUI

/// BDR-0006's reading notation, one per language. Only languages with a real choice get a picker;
/// the rest show the notation they always use.
enum PronunciationSystem: String, CaseIterable, Sendable {
    case ipa = "IPA"
    case kana
    case romaji
    case pinyin
    case zhuyin

    var title: LocalizedStringResource {
        switch self {
        case .ipa: "IPA"
        case .kana: "Kana"
        case .romaji: "Romaji"
        case .pinyin: "Pinyin"
        case .zhuyin: "Zhuyin"
        }
    }

    /// The notations a language can be read in; the first is its default.
    static func options(for language: String) -> [PronunciationSystem] {
        switch LanguageTag.key(language) {
        case "ja": [.kana, .romaji]
        case "zh-Hans", "zh-Hant": [.pinyin, .zhuyin]
        default: [.ipa]
        }
    }
}

extension SettingsStore {
    static let pronunciationKey = "pronunciation.systems"

    /// The saved notation for a language, or its default; a saved value that no longer fits the
    /// language falls back too.
    static func pronunciationSystem(
        for language: String, in defaults: UserDefaults = .standard
    ) -> PronunciationSystem {
        let options = PronunciationSystem.options(for: language)
        let saved = (defaults.dictionary(forKey: pronunciationKey) as? [String: String])?[
            LanguageTag.key(language)]
        return saved.flatMap(PronunciationSystem.init).flatMap { options.contains($0) ? $0 : nil }
            ?? options[0]
    }

    static func setPronunciationSystem(
        _ system: PronunciationSystem, for language: String, in defaults: UserDefaults = .standard
    ) {
        var saved = defaults.dictionary(forKey: pronunciationKey) as? [String: String] ?? [:]
        saved[LanguageTag.key(language)] = system.rawValue
        defaults.set(saved, forKey: pronunciationKey)
    }
}

/// Reading notation, one row per language, inside the Languages pane.
struct PronunciationSettingsView: View {
    let languages: [String]
    /// Bumped after a write so the pickers re-read the store; the store stays the one source of truth
    /// for what a request actually uses.
    ///
    /// A mirrored `@State` dictionary was used before and did not redraw: reading and writing the same
    /// piece of state within one action does not make SwiftUI re-evaluate the picker that owns it.
    @State private var revision = 0

    var body: some View {
        Section {
            ForEach(languages, id: \.self) { tag in
                let options = PronunciationSystem.options(for: tag)
                if options.count > 1 {
                    Picker(LanguageCatalog.name(for: tag), selection: binding(for: tag)) {
                        ForEach(options, id: \.self) { Text($0.title).tag($0) }
                    }
                } else {
                    // The value is a resource; `LabeledContent` needs a string on both sides.
                    LabeledContent(
                        LanguageCatalog.name(for: tag), value: String(localized: options[0].title))
                }
            }
        } header: {
            Text("Reading Notation")
        } footer: {
            Text(
                "Used when filling in a reading or looking a word up while reading; a change affects later requests only."
            )
        }
    }

    private func binding(for tag: String) -> Binding<PronunciationSystem> {
        Binding(
            get: {
                // Reading the revision is what re-renders a picker after a change.
                _ = revision
                return SettingsStore.pronunciationSystem(for: tag)
            },
            set: { system in
                // Written through the store, which applies the rules a request applies too: a saved
                // value that no longer fits its language falls back to that language's default.
                SettingsStore.setPronunciationSystem(system, for: tag)
                revision &+= 1
            })
    }
}
