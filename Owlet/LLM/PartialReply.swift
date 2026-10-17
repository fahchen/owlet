import Foundation

/// What a still-arriving reply can already show (BDR-0017): the parts of a structurally complete
/// prefix of a reply, extracted without ever validating anything. A partial has not been through
/// the contract's `parse`; callers display it, never copy, replace or record it.
enum PartialReply {
    /// Every `{"source","target"}` pair the accumulated reply has already closed. A pair shows only
    /// once its object is complete, so the display never trades on a half-written value, and the
    /// raw JSON frame itself never reaches a user.
    static func segments(from accumulated: String) -> [TranslationResult.Segment] {
        guard let head = accumulated.range(of: "\"segments\"") else { return [] }
        var content = accumulated[head.upperBound...]
        guard let array = content.firstIndex(of: "[") else { return [] }
        content = content[array...]
        var pairs: [TranslationResult.Segment] = []
        var depth = 0
        var inString = false
        var escaped = false
        var objectStart: String.Index?
        var index = content.startIndex
        while index < content.endIndex, depth >= 0 {
            let character = content[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                switch character {
                case "\"":
                    inString = true
                case "{":
                    if depth == 0 { objectStart = index }
                    depth += 1
                case "}":
                    depth -= 1
                    if depth == 0, let start = objectStart {
                        objectStart = nil
                        if let pair = pair(content[start...index]) { pairs.append(pair) }
                    }
                default:
                    break
                }
            }
            index = content.index(after: index)
        }
        return pairs
    }

    /// The `meaning` string of an accumulated lookup reply, once its value has closed. It shows the
    /// explanation growing in the card without ever confirming it as an answer.
    ///
    /// The scan starts at the first `"meaning"`; a quoted word inside an earlier string value would
    /// match too, which can only shift the display of a prefix the parser later judges anyway — the
    /// validation never reads from here.
    static func meaning(from accumulated: String) -> String? {
        guard let header = accumulated.range(of: "\"meaning\"") else { return nil }
        var content = accumulated[header.upperBound...]
        guard let colon = content.firstIndex(of: ":") else { return nil }
        content = content[colon...]
        var index = content.index(after: colon)
        // JSON allows any whitespace between key and value; the quote that opens the string
        // follows it.
        while index < content.endIndex, content[index].isWhitespace {
            index = content.index(after: index)
        }
        guard index < content.endIndex, content[index] == "\"" else { return nil }
        let opening = index
        var escaped = false
        var closing: String.Index?
        index = content.index(after: index)
        while index < content.endIndex {
            let character = content[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                closing = index
                break
            }
            index = content.index(after: index)
        }
        // A value still being written is not a value yet — nothing shows until it is complete.
        guard let end = closing else { return nil }
        // JSONSerialization accepts only an object or an array as its root, so the quoted value
        // travels as a one-element array and its unescape is read from there.
        let quoted = "[" + String(content[opening...end]) + "]"
        let data = Data(quoted.utf8)
        guard let wrapped = try? JSONSerialization.jsonObject(with: data, options: []) as? [String],
            let text = wrapped.first, !text.isEmpty
        else { return nil }
        return text
    }

    /// One closed pair as the contract would accept it, so nothing is displayed that the validation
    /// is bound to drop. `TranslationResult.Segment`'s rules apply verbatim.
    private static func pair(_ object: Substring) -> TranslationResult.Segment? {
        guard let data = String(object).data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            let source = dict["source"] as? String, let target = dict["target"] as? String
        else { return nil }
        let blank = TranslationResult.isBlank(source)
        guard !source.isEmpty, !target.isEmpty || blank else { return nil }
        return TranslationResult.Segment(source: source, target: target)
    }
}
