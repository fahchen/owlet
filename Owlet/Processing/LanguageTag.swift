import Foundation

/// BCP 47 comparison keys per `spec/llm/contract.md`: the primary subtag decides, and Chinese is
/// split by script because Simplified and Traditional Chinese are different targets.
enum LanguageTag {
    /// The canonical tag used as a mapping key, a picker tag and a request target. Other languages
    /// keep their lowercased primary subtag; Chinese gains the script the contract requires.
    static func key(_ tag: String) -> String {
        let parts = tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).map(
            String.init)
        guard let primary = parts.first else { return "" }
        guard primary == "zh" else { return primary }
        let rest = parts.dropFirst()
        if rest.contains("hant") { return "zh-Hant" }
        if rest.contains("hans") { return "zh-Hans" }
        return rest.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? "zh-Hant" : "zh-Hans"
    }

    static func same(_ lhs: String, _ rhs: String) -> Bool { key(lhs) == key(rhs) }
}
