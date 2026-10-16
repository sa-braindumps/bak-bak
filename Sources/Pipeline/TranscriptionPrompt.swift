import Foundation

/// Builds the `prompt` sent with each transcription request from the user's
/// vocabulary, so the model spells taught terms right the first time.
///
/// This is only a hint. `Substitutor` still runs afterwards and is what
/// guarantees a taught term is corrected (SPEC §3.3).
public enum TranscriptionPrompt {

    /// What we send when there's no vocabulary yet.
    public static let base = "Voice dictation."

    /// For Hinglish: an example of the speech rather than an instruction.
    /// The models ignore "write in Roman letters" (they always answer in
    /// Devanagari), but this context made them hear English words inside
    /// Hindi correctly ("deck" instead of "देख").
    public static let hinglishBase = "haan bhai, kal meeting hai. deck bhej dena, aur woh deployment wala issue fix kar dena."

    /// The API reads roughly the last 224 tokens of the prompt; stay well
    /// under that, and a long word list also nudges the model to invent terms.
    public static let maxWords = 150

    /// - Parameters:
    ///   - vocab: `[heard: intended]` from `[vocab]`.
    ///   - order: `[vocab]` keys in file order. New entries are appended, so
    ///     the end of the list is the most recently taught; those win the cap.
    public static func build(vocab: [String: String], order: [String] = [], language: TranscriptionConfig.Language = .english) -> String {
        let opening = language == .hinglish ? hinglishBase : base
        let orderedKeys = order.filter { vocab[$0] != nil }
            + vocab.keys.filter { !order.contains($0) }.sorted()

        var seen = Set<String>()
        var terms: [String] = []
        var words = 0
        for key in orderedKeys.reversed() {
            guard let term = vocab[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !term.isEmpty,
                  seen.insert(term.lowercased()).inserted else { continue }
            let termWords = term.split(whereSeparator: \.isWhitespace).count
            guard words + termWords <= maxWords else { break }
            terms.append(term)
            words += termWords
        }

        guard !terms.isEmpty else { return opening }
        return "\(opening) Vocabulary: \(terms.joined(separator: ", "))."
    }
}
