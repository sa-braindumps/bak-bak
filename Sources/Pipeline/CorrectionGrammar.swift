import Foundation

/// Parses voice correction grammars.
/// Exactly three patterns in v0.1:
///   - "no, X is Y"
///   - "correction: X is Y"
///   - "actually X is Y"
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

    /// Parse an utterance against correction grammars.
    /// Returns a `Correction` if it matches, `nil` if it's a normal dictation.
    public static func parse(_ utterance: String) -> Correction? {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)

        for pattern in patterns {
            if let correction = tryPattern(pattern, on: trimmed) {
                return correction
            }
        }

        return nil
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

            let heard = String(remaining[remaining.startIndex..<isRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let intended = String(remaining[isRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !heard.isEmpty, !intended.isEmpty else { continue }

            return Correction(heard: heard, intended: intended)
        }

        return nil
    }
}
