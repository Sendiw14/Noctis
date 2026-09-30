import Foundation

/// `{{fact.id}}` tokens: how a draft points at a number without writing it.
/// The app puts the real, formatted value in after the draft has been checked.
public enum CoachTokens {
    /// A well-formed token: `{{` a fact id `}}`.
    static let pattern = try! NSRegularExpression(pattern: #"\{\{\s*([A-Za-z0-9_.]+)\s*\}\}"#)

    /// The fact ids `text` points at, in order.
    public static func ids(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// `text` with every well-formed token taken out (replaced by a space, so
    /// the words around it stay apart): what is left is what the model wrote.
    public static func stripped(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }

    /// Whether a brace is left once the tokens are out: a token that was
    /// never closed, or nested, is not a token.
    public static func hasMalformedBraces(_ text: String) -> Bool {
        let rest = stripped(text)
        return rest.contains("{") || rest.contains("}")
    }

    /// `text` with each token replaced by its fact's display; nil when a
    /// token names a fact that isn't there.
    public static func resolve(_ text: String, facts: [String: CoachFact]) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        var out = ""
        var cursor = text.startIndex
        for match in pattern.matches(in: text, range: range) {
            guard let whole = Range(match.range, in: text), let id = Range(match.range(at: 1), in: text) else { return nil }
            guard let fact = facts[String(text[id])] else { return nil }
            out += text[cursor..<whole.lowerBound]
            out += fact.display
            cursor = whole.upperBound
        }
        out += text[cursor...]
        return out
    }

    /// The length a person will see: the text with each token as its display.
    public static func visibleLength(_ text: String, facts: [String: CoachFact]) -> Int {
        (resolve(text, facts: facts) ?? text).count
    }
}
