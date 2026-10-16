import Foundation

/// Parses whole-utterance voice editing commands.
///
/// These are deterministic editing actions spoken in the correction window —
/// plain string matches, not model calls. Recognized in v1:
///   - "scratch that" / "delete that" / "undo that" → `.scratchThat`
///   - "new line"      → `.newLine(1)`
///   - "new paragraph" → `.newLine(2)`
///   - "select that" / "select last sentence" → `.selectLast`
///
/// Anything else parses to `nil` and is treated as normal dictation (or a
/// voice correction). Matching is case-insensitive and tolerant of a single
/// run of trailing punctuation ("scratch that." matches).
///
/// (NOTE: "make that more formal" and other rewrite-by-meaning commands are
/// Phase 2 LLM features and are intentionally not parsed here.)
public struct CommandGrammar {

    public enum Command: Sendable, Equatable {
        /// Delete the just-injected text.
        case scratchThat
        /// Append `count` newline(s): 1 for "new line", 2 for "new paragraph".
        case newLine(Int)
        /// Select the just-injected text backward from the cursor.
        case selectLast
    }

    /// A phrase variant mapped to the command it produces.
    private struct Phrase {
        let triggers: [String]
        let command: Command
    }

    private static let phrases: [Phrase] = [
        Phrase(triggers: ["scratch that", "delete that", "undo that"], command: .scratchThat),
        Phrase(triggers: ["new paragraph"], command: .newLine(2)),
        Phrase(triggers: ["new line"], command: .newLine(1)),
        Phrase(triggers: ["select that", "select last sentence"], command: .selectLast),
    ]

    /// Parse an utterance into an editing command, or `nil` if it is not one.
    public static func parse(_ utterance: String) -> Command? {
        let key = normalize(utterance)
        guard !key.isEmpty else { return nil }

        for phrase in phrases {
            for trigger in phrase.triggers where normalize(trigger) == key {
                return phrase.command
            }
        }

        return nil
    }

    /// Trim, lowercase, and drop a single run of trailing punctuation so
    /// "scratch that!" matches the trigger "scratch that".
    private static func normalize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingPunctuation = CharacterSet(charactersIn: ".!?,;:")
        let stripped = trimmed.unicodeScalars.reversed().drop(while: { trailingPunctuation.contains($0) })
        return String(String.UnicodeScalarView(stripped.reversed()))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
