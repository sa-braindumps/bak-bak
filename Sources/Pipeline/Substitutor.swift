import Foundation

/// Deterministic, case-insensitive string substitution from `[vocab]`.
/// This is the core guarantee: a taught term is corrected on the next dictation.
public struct Substitutor {

    public struct Substitution: Sendable {
        public let pattern: String
        public let replacement: String
    }

    /// Apply vocabulary substitutions to a raw transcript.
    /// Matching is case-insensitive, longest-key-first, on token boundaries.
    public static func apply(_ raw: String, vocab: [String: String]) -> String {
        guard !vocab.isEmpty else { return raw }

        // Sort by key length descending so longer phrases win
        let sorted = vocab
            .sorted { $0.key.count > $1.key.count }

        var result = raw

        for entry in sorted {
            let pattern = entry.key
            let replacement = entry.value
            result = replaceOccurrences(of: pattern, in: result, with: replacement)
        }

        return result
    }

    /// Replace occurrences of `pattern` in `text` with `replacement`.
    /// Case-insensitive, whole-word, and loose about how the words of a
    /// multi-word key are joined (see `PhraseMatch`).
    private static func replaceOccurrences(of pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = PhraseMatch.regex(for: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        guard !matches.isEmpty else { return text }

        var result = text
        // Replace in reverse order to preserve indices
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            // Preserve the original case of the first character of the replacement
            result.replaceSubrange(matchRange, with: replacement)
        }

        return result
    }
}
