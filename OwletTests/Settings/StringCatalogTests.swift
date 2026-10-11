import Foundation
import Testing

@testable import Owlet

/// The String Catalog is what the interface actually speaks, so its shape is worth asserting: every
/// entry translated into every supported language, with the app's own source language as the source.
///
/// `scripts/build-strings.py --check` keeps the catalog and the translation table in step; this test
/// guards the catalog itself, which is what ships.
@Suite struct StringCatalogTests {
    /// The catalog source, not the compiled `.strings`: only the source carries `sourceLanguage`, and
    /// it is what review and the generator both work on. Found from this file, so it is the checkout's
    /// own catalog rather than whatever the test bundle happens to contain.
    func catalog() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Settings
            .deletingLastPathComponent()  // OwletTests
            .deletingLastPathComponent()  // the checkout
        let url = root.appendingPathComponent("Owlet/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try #require(object as? [String: Any])
    }

    /// English is the source language, so a key is the English text and Chinese is a translation.
    @Test func theSourceLanguageIsEnglish() throws {
        let catalog = try catalog()
        #expect(catalog["sourceLanguage"] as? String == "en")
    }

    @Test func everyEntryCarriesEverySupportedLanguage() throws {
        let catalog = try catalog()
        let strings = try #require(catalog["strings"] as? [String: Any])
        #expect(!strings.isEmpty)

        var missing: [String] = []
        for (key, raw) in strings {
            guard let entry = raw as? [String: Any],
                let localizations = entry["localizations"] as? [String: Any]
            else {
                missing.append("\(key)（没有 localizations）")
                continue
            }
            for language in ["zh-Hans", "zh-Hant", "en", "ja"] {
                guard
                    let unit = (localizations[language] as? [String: Any])?["stringUnit"]
                        as? [String: Any],
                    let value = unit["value"] as? String, !value.isEmpty
                else {
                    missing.append("\(key)／\(language)")
                    continue
                }
            }
        }
        #expect(missing.isEmpty, "缺少翻译：\(missing.sorted().joined(separator: "、"))")
    }

    /// A translation must use the same format specifiers as the key it belongs to: the app formats the
    /// translated text with the arguments the key's placeholders stand for, so a translation that says
    /// `%lld` where the key says `%@` is handed the wrong type — which Xcode reports as a warning and
    /// which `String(format:)` then renders wrongly.
    @Test func everyTranslationUsesTheKeysFormatSpecifiers() throws {
        let catalog = try catalog()
        let strings = try #require(catalog["strings"] as? [String: Any])
        let specifier = /%(?:\d+\$)?(@|lld|ld|d|s|\.\df)/
        func specifiers(in text: String) -> [String] {
            text.matches(of: specifier).map { String($0.output.1) }
        }
        var wrong: [String] = []
        for (key, raw) in strings {
            let localizations = (raw as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            let expected = specifiers(in: key)
            for language in ["zh-Hans", "zh-Hant", "ja"] {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                guard let value = unit?["value"] as? String else { continue }
                if specifiers(in: value) != expected { wrong.append("\(language) \(key)") }
            }
        }
        #expect(wrong.isEmpty, "占位符与键不一致：\(wrong.sorted().joined(separator: "、"))")
    }

    /// A `LocalizedStringResource` interpolated into a `String` prints its own description — the whole
    /// `LocalizedStringResource(key: "…", defaultValue: …)` — so a resource must never be turned into
    /// text that way. The result only shows at runtime, which is why this reads the sources.
    @Test func noResourceIsInterpolatedIntoAString() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Owlet")
        let files =
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty, "找不到源码目录：\(root.path)")

        // The shape to catch, verbatim: a string interpolation whose expression ends in `.title` or
        // another resource property. Written as plain substrings so it cannot be misread as a regex.
        let resourceProperties = [".title", ".progress", ".retry", ".placeholder", ".prompt"]
        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                guard let open = line.range(of: "\\(") else { continue }
                let rest = line[open.upperBound...]
                guard let close = rest.firstIndex(of: ")") else { continue }
                let expression = rest[..<close]
                if resourceProperties.contains(where: { expression.hasSuffix($0) }) {
                    offenders.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "资源被当作字符串插值：\(offenders.joined(separator: "、"))")
    }

    /// The source value is the key itself, so an entry that says otherwise would show a raw key.
    @Test func theSourceLanguageEqualsTheKey() throws {
        let catalog = try catalog()
        let strings = try #require(catalog["strings"] as? [String: Any])
        var wrong: [String] = []
        for (key, raw) in strings {
            let localizations = (raw as? [String: Any])?["localizations"] as? [String: Any]
            let unit = (localizations?["en"] as? [String: Any])?["stringUnit"] as? [String: Any]
            if unit?["value"] as? String != key { wrong.append(key) }
        }
        #expect(wrong.isEmpty, "源语言与 key 不一致：\(wrong.sorted().joined(separator: "、"))")
    }
}
