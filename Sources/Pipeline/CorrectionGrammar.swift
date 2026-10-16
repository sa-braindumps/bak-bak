import Foundation

/// Parses voice correction grammars.
/// Exactly three patterns in v0.1:
///   - "no, X is Y"
///   - "correction: X is Y"
///   - "actually X is Y"
///
/// Ordinary speech starts with "no" or "actually" all the time ("Actually the
/// meeting is at 3pm"), so a match also has to look like a word fix: X and Y
/// are short, X isn't just a pronoun, and X appears in the text that was just
/// typed. Anything else is treated as normal dictation.
public struct CorrectionGrammar {

    public struct Correction: Sendable, Equatable {
        public let heard: String
        public let intended: String
    }

    /// A pattern matcher with a leading keyword and optional punctuation.
    private struct Pattern {
        let keywords: [String]
        let description: String
    }

    private static let patterns: [Pattern] = [
        Pattern(keywords: ["no"], description: "no, X is Y"),
        Pattern(keywords: ["correction"], description: "correction: X is Y"),
        Pattern(keywords: ["actually"], description: "actually X is Y"),
    ]

    private static let connective = " is "

    /// Longest X or Y, in words, that still reads as a vocabulary fix.
    public static let maxWords = 4

    /// A lone pronoun is never the misheard word ("no, it is fine").
    private static let pronouns: Set<String> = [
        "it", "that", "this", "there", "he", "she", "they", "we", "i", "you", "what",
    ]

    /// Parse an utterance against correction grammars.
    /// Returns a `Correction` if it matches, `nil` if it's a normal dictation.
    ///
    /// - Parameter lastText: the text that was just typed. When given, X must
    ///   appear in it as whole words (case-insensitive).
    public static func parse(_ utterance: String, lastText: String? = nil) -> Correction? {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)

        for pattern in patterns {
            guard let correction = tryPattern(pattern, on: trimmed) else { continue }
            guard looksLikeWordFix(correction) else { return nil }
            if let lastText, !containsWords(lastText, correction.heard) { return nil }
            return correction
        }

        return nil
    }

    private static func looksLikeWordFix(_ correction: Correction) -> Bool {
        let heardWords = correction.heard.split(whereSeparator: \.isWhitespace)
        let intendedWords = correction.intended.split(whereSeparator: \.isWhitespace)
        guard heardWords.count <= maxWords, intendedWords.count <= maxWords else { return false }
        if heardWords.count == 1, pronouns.contains(correction.heard.lowercased()) { return false }
        return correction.heard.lowercased() != correction.intended.lowercased()
    }

    private static func containsWords(_ text: String, _ phrase: String) -> Bool {
        let pattern = "(?i)(?<![\\w])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\w])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Trim whitespace, trailing sentence punctuation and wrapping quotes, so
    /// "Bak-Bak." becomes "Bak-Bak" (but "Node.js" is left alone).
    private static func clean(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = out.last, ".,!?;:".contains(last) { out.removeLast() }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tryPattern(_ pattern: Pattern, on text: String) -> Correction? {
        let lower = text.lowercased()

        for keyword in pattern.keywords {
            let prefix = keyword + " "
            let prefixWithComma = keyword + ", "
            let prefixWithColon = keyword + ": "

            var remainder: String?

            if lower.hasPrefix(prefixWithComma) {
                remainder = String(text.dropFirst(prefixWithComma.count))
            } else if lower.hasPrefix(prefixWithColon) {
                remainder = String(text.dropFirst(prefixWithColon.count))
            } else if lower.hasPrefix(prefix) {
                remainder = String(text.dropFirst(prefix.count))
            }

            guard let remaining = remainder else { continue }

            // Find the connective " is " (case-insensitive)
            let remainingLower = remaining.lowercased()
            guard let isRange = remainingLower.range(of: connective) else { continue }

            let heard = clean(String(remaining[remaining.startIndex..<isRange.lowerBound]))
            let intended = clean(String(remaining[isRange.upperBound...]))

            guard !heard.isEmpty, !intended.isEmpty else { continue }

            return Correction(heard: heard, intended: intended)
        }

        return nil
    }
}
