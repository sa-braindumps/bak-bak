import Foundation
import Pipeline

/// Manages the 10-second correction window after each injection.
/// Parses correction grammars, writes vocabulary, and performs in-place rewrite.
public final class CorrectionController {

    public struct CorrectionResult {
        public let learned: Bool
        public let rewriteText: String?
    }

    private let profileStore: ProfileStore
    private let injector: Injector
    private var correctionWindowStart: Date?
    private var windowDuration: TimeInterval
    private var priorInjectionLength: Int?
    private var isWindowOpen = false

    public init(profileStore: ProfileStore, injector: Injector) {
        self.profileStore = profileStore
        self.injector = injector
        let profile = try? profileStore.read()
        self.windowDuration = TimeInterval(profile?.correctionWindowSecs ?? 10)
    }

    /// Open the correction window after an injection.
    public func openWindow(afterInjectionLength length: Int) {
        priorInjectionLength = length
        correctionWindowStart = Date()
        isWindowOpen = true

        // Auto-close after window duration
        DispatchQueue.main.asyncAfter(deadline: .now() + windowDuration) { [weak self] in
            self?.closeWindow()
        }
    }

    /// Close the correction window.
    public func closeWindow() {
        isWindowOpen = false
        priorInjectionLength = nil
        correctionWindowStart = nil
    }

    /// Check if the window is open and process a potential correction.
    public func processUtterance(_ utterance: String) -> CorrectionResult? {
        guard isWindowOpen else { return nil }

        // Try to parse as a correction
        guard let correction = CorrectionGrammar.parse(utterance) else {
            // Not a correction — close window and return nil
            closeWindow()
            return nil
        }

        // Write the correction to vocab
        do {
            try profileStore.addVocabEntry(heard: correction.heard, intended: correction.intended)
        } catch {
            return CorrectionResult(learned: false, rewriteText: nil)
        }

        // Perform in-place rewrite if we have the prior injection length
        if let priorLength = priorInjectionLength {
            // Backspace-delete the prior text
            injector.sendBackspaces(count: priorLength)
            // Type the corrected text (with the new vocab entry applied)
            let correctedText = Substitutor.apply(utterance, vocab: (try? profileStore.read())?.vocab ?? [:])
            injector.typeCharacters(correctedText)
        } else {
            // Focus changed — skip delete, just inject the corrected text
            let correctedText = Substitutor.apply(utterance, vocab: (try? profileStore.read())?.vocab ?? [:])
            _ = injector.inject(correctedText)
        }

        closeWindow()
        return CorrectionResult(learned: true, rewriteText: utterance)
    }

    /// Check if a term was heard (for auto-correction during normal dictation).
    public func autoCorrectIfNeeded(_ text: String, vocab: [String: String]) -> String {
        return Substitutor.apply(text, vocab: vocab)
    }
}
