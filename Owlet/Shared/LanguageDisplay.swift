import Foundation

/// Language chip and header text for the notebook; unknown tags fall back to the raw BCP 47 value.
enum LanguageDisplay {
    static func primaryCode(for tag: String) -> String {
        let primary =
            tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? tag
        return primary.uppercased()
    }

    static func localizedName(for tag: String) -> String {
        switch primaryCode(for: tag) {
        case "EN": "英语"
        case "JA": "日语"
        case "ZH": "中文"
        case "KO": "韩语"
        case "FR": "法语"
        case "DE": "德语"
        case "ES": "西班牙语"
        default: tag
        }
    }
}
