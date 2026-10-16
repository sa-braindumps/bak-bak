import Foundation

/// Deterministic voice snippets / macros: a whole-utterance trigger phrase
/// expands to a stored template. Like `Substitutor`, this is plain string
/// matching — not a hint to a model. A trigger you teach once expands the same
/// way every time.
///
/// v1 matches the **whole utterance only** (trimmed, case-insensitive, tolerant
/// of a trailing punctuation mark like "." or "!"). Mid-sentence / embedded
/// expansion is intentionally not supported in v1 for predictability — you
/// always know exactly when a snippet fires.
public struct SnippetExpander {

    /// Expand a snippet trigger if the whole utterance matches one.
    /// Matching is case-insensitive on the trigger, tolerant of trailing
    /// punctuation, and longest-trigger-first so a longer phrase wins over a
    /// shorter overlapping one. Empty/missing snippets pass through unchanged;
    /// a non-matching utterance passes through unchanged.
    public static func apply(_ text: String, snippets: [String: String]) -> String {
        guard !snippets.isEmpty else { return text }

        let key = normalize(text)
        guard !key.isEmpty else { return text }

        // Longest trigger first so a longer phrase wins over a shorter overlap.
        let sorted = snippets.sorted { $0.key.count > $1.key.count }

        for (trigger, expansion) in sorted {
            if normalize(trigger) == key {
                return expansion
            }
        }

        return text
    }

    /// Normalize for whole-utterance comparison: trim whitespace, lowercase,
    /// and drop a single run of trailing sentence punctuation ("." / "!" / "?"
    /// and friends) so "send my address." matches the trigger "send my address".
    private static func normalize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingPunctuation = CharacterSet(charactersIn: ".!?,;:")
        let stripped = trimmed.unicodeScalars.reversed().drop(while: { trailingPunctuation.contains($0) })
        return String(String.UnicodeScalarView(stripped.reversed()))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
