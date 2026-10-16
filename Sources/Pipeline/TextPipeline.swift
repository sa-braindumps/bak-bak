import Foundation

/// Everything that happens to a transcript between the speech-to-text call
/// and the cursor: filler removal (if on), vocabulary substitution, snippet
/// expansion. Shared by the app and `bak-bak transcribe` so both run the
/// exact same steps.
public enum TextPipeline {

    /// The transcript in the script the user asked for. Hinglish mode turns
    /// the model's Devanagari into Roman letters; everything else is as-is.
    /// Runs before commands and corrections are parsed, so "scratch that"
    /// works the same in every mode.
    public static func transcript(_ raw: String, profile: ProfileStore.Profile?) -> String {
        profile?.transcription.language == .hinglish ? HinglishRomanizer.romanize(raw) : raw
    }

    public static func process(_ raw: String, profile: ProfileStore.Profile?) -> String {
        let text = transcript(raw, profile: profile)
        let removeFillers = profile?.removeFillers ?? false
        let cleaned = removeFillers ? DisfluencyFilter.apply(text) : text
        let substituted = Substitutor.apply(cleaned, vocab: profile?.vocab ?? [:])
        return SnippetExpander.apply(substituted, snippets: profile?.snippets ?? [:])
    }

    /// `process`, with the optional polish pass first when `[cleanup].polish`
    /// is on. Snippet triggers and short dictations skip it, and if the call
    /// fails the unpolished text is used. Vocab still runs after polish, so
    /// taught terms come out right either way.
    public static func process(_ raw: String, profile: ProfileStore.Profile?, polisher: Polisher?) async -> String {
        let text = transcript(raw, profile: profile)
        guard profile?.polish == true, let polisher, Polisher.shouldPolish(text),
              SnippetExpander.apply(text, snippets: profile?.snippets ?? [:]) == text else {
            return process(text, profile: profile)
        }
        let polished = (try? await polisher.polish(text)) ?? text
        return process(polished, profile: profile)
    }

    /// A polisher if polish is on and there's an OpenAI key to use.
    public static func polisher(profile: ProfileStore.Profile?, openAIKey: String?) -> Polisher? {
        guard profile?.polish == true, let key = openAIKey, !key.isEmpty else { return nil }
        return Polisher(apiKey: key)
    }
}
