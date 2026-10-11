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
        case .kana: "假名"
        case .romaji: "罗马字"
        case .pinyin: "拼音"
        case .zhuyin: "注音"
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

/// 读音体系 section of the 语言 pane.
struct PronunciationSettingsView: View {
    let languages: [String]
    /// Mirrors the store so a picker redraws on change; the store stays the source of truth.
    @State private var systems: [String: PronunciationSystem] = [:]

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
            Text("读音体系")
        } footer: {
            Text("用于生词本补充读音与阅读查词；改动只影响之后的请求。")
        }
        .onAppear { reload() }
        .onChange(of: languages) { _, _ in reload() }
    }

    private func binding(for tag: String) -> Binding<PronunciationSystem> {
        Binding(
            get: { systems[tag] ?? SettingsStore.pronunciationSystem(for: tag) },
            set: {
                SettingsStore.setPronunciationSystem($0, for: tag)
                systems[tag] = $0
            })
    }

    private func reload() {
        systems = Dictionary(
            uniqueKeysWithValues: languages.map { ($0, SettingsStore.pronunciationSystem(for: $0)) })
    }
}
