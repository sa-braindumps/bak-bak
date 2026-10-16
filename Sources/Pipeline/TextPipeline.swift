import Foundation

/// Everything that happens to a transcript between the speech-to-text call
/// and the cursor: filler removal (if on), vocabulary substitution, snippet
/// expansion. Shared by the app and `bak-bak transcribe` so both run the
/// exact same steps.
public enum TextPipeline {

    public static func process(_ raw: String, profile: ProfileStore.Profile?) -> String {
        let removeFillers = profile?.removeFillers ?? false
        let cleaned = removeFillers ? DisfluencyFilter.apply(raw) : raw
        let substituted = Substitutor.apply(cleaned, vocab: profile?.vocab ?? [:])
        return SnippetExpander.apply(substituted, snippets: profile?.snippets ?? [:])
    }
}
