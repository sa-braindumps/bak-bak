import Foundation

/// Deterministic disfluency (filler) removal. Strips a fixed set of filler
/// tokens (um, uh, …) from a transcript as **whole tokens only**, then cleans
/// up the spacing left behind. This is plain string surgery — not a model call
/// — so the result is identical every time.
///
/// Real words are never touched: "like", "so", and "you know" are left alone,
/// and a filler is only removed when it stands as its own word — "summary"
/// keeps its "um" and "ahem" is untouched.
public struct DisfluencyFilter {

    /// The fixed filler set, matched case-insensitively as whole tokens.
    private static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "erm", "er", "ah", "hmm", "mm",
    ]

    /// Remove filler tokens and tidy the surrounding whitespace/punctuation.
    /// Whole-token, case-insensitive removal; collapses the double spaces that
    /// removal leaves, trims, removes a space left before punctuation, and
    /// re-capitalizes the first letter if a leading filler was stripped.
    public static func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        // Match a filler that stands as its own word. \b boundaries keep us from
        // gutting substrings ("summary", "ahem"); the (?i) makes it case-insensitive.
        let alternation = fillers
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = "(?i)\\b(?:\(alternation))\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let range = NSRange(text.startIndex..., in: text)

        // Did the utterance *begin* with a filler? If so, the first surviving
        // letter was previously mid-sentence and may need re-capitalizing.
        let leadingFiller = (try? NSRegularExpression(pattern: "(?i)^\\s*(?:\(alternation))\\b"))
            .map { $0.firstMatch(in: text, range: range) != nil } ?? false

        var result = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")

        // Collapse runs of whitespace left by removal.
        result = result.replacingOccurrences(
            of: "[ \\t]{2,}",
            with: " ",
            options: .regularExpression
        )

        // Remove a space left dangling before punctuation ("hello , world" → "hello, world").
        result = result.replacingOccurrences(
            of: " +([.,!?;:])",
            with: "$1",
            options: .regularExpression
        )

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Re-capitalize the first letter only when a leading filler was the
        // thing stripped — never touch an utterance that already started clean.
        if leadingFiller, let first = result.first, first.isLowercase {
            result = String(first).uppercased() + result.dropFirst()
        }

        return result
    }
}
