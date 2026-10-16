import Foundation

/// How a spoken phrase is matched against transcript text.
///
/// The model writes the same words differently from one dictation to the
/// next: "bug bug", "bug-bug", "BugBug". So between the words of a phrase, a
/// space, a hyphen, or nothing at all are treated alike, and case is ignored.
/// Used by vocab substitution, snippet triggers and the correction grammar,
/// so all three agree on what "the same phrase" means.
public enum PhraseMatch {

    /// Spaces and the hyphen/dash characters the model emits between words.
    static let separators = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "-\u{2010}\u{2011}\u{2012}\u{2013}"))

    /// A case-insensitive regex matching `phrase` as whole words, with any
    /// mix of separators (or none) between its words. Nil for an empty phrase.
    public static func regex(for phrase: String) -> NSRegularExpression? {
        let words = phrase.components(separatedBy: separators).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let body = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "[\\s\\-\\u2010-\\u2013]*")
        return try? NSRegularExpression(pattern: "(?i)(?<![\\p{L}\\p{N}])\(body)(?![\\p{L}\\p{N}])")
    }

    public static func contains(_ text: String, phrase: String) -> Bool {
        guard let regex = regex(for: phrase) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// A form of `s` for whole-string comparison: lowercased, with every
    /// separator removed. "My sign-off" and "my sign off" both become
    /// "mysignoff".
    public static func key(_ s: String) -> String {
        s.lowercased().components(separatedBy: separators).joined()
    }
}
