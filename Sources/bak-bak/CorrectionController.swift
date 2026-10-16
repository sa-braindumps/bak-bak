import AppKit
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
    private var windowOpen = false
    /// The app the text was injected into. If the user has switched apps since,
    /// we treat the injection length as unknown (SPEC §7.5).
    private var injectionTargetPID: pid_t?
    /// Bumped on every open so an older window's close timer can't cut a newer
    /// window short.
    private var windowGeneration = 0

    /// Whether the correction/command window is currently open.
    public var isWindowOpen: Bool { windowOpen }

    /// The length of the just-injected text, if known (nil after focus change
    /// or once the window has closed). Drives the §7.5 safety rule.
    public var lastInjectionLength: Int? {
        guard let pid = injectionTargetPID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        return priorInjectionLength
    }

    public init(profileStore: ProfileStore, injector: Injector) {
        self.profileStore = profileStore
        self.injector = injector
        let profile = try? profileStore.read()
        self.windowDuration = TimeInterval(profile?.correctionWindowSecs ?? 10)
    }

    /// Open the correction window after an injection.
    public func openWindow(afterInjectionLength length: Int) {
        priorInjectionLength = length
        injectionTargetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        correctionWindowStart = Date()
        windowOpen = true
        windowGeneration += 1

        let generation = windowGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + windowDuration) { [weak self] in
            guard let self, self.windowGeneration == generation else { return }
            self.closeWindow()
        }
    }

    /// Close the correction window.
    public func closeWindow() {
        windowOpen = false
        priorInjectionLength = nil
        injectionTargetPID = nil
        correctionWindowStart = nil
    }

    /// Execute a parsed voice editing command against the just-injected text.
    /// Returns a short status string for the menu bar/overlay, or `nil` if the
    /// window is closed (so the caller falls through to normal dictation).
    ///
    /// Safety (SPEC §7.5): `.scratchThat` and `.selectLast` are **no-ops** when
    /// the prior injection length is unknown (e.g. focus changed) — we never
    /// backspace or select blindly into the user's surrounding text.
    public func processCommand(_ command: CommandGrammar.Command) -> String? {
        guard windowOpen else { return nil }

        let priorLength = lastInjectionLength

        switch command {
        case .scratchThat:
            if let length = priorLength, length > 0 {
                injector.sendBackspaces(count: length)
            }
            // Unknown length → no-op (never backspace blindly).
        case .newLine(let n):
            injector.typeCharacters(String(repeating: "\n", count: n))
        case .selectLast:
            if let length = priorLength, length > 0 {
                injector.selectBackward(count: length)
            }
            // Unknown length → no-op (never select blindly).
        }

        closeWindow()

        switch command {
        case .scratchThat: return "scratched"
        case .newLine: return "new line"
        case .selectLast: return "selected"
        }
    }

    /// Check if the window is open and process a potential correction.
    public func processUtterance(_ utterance: String) -> CorrectionResult? {
        guard windowOpen else { return nil }

        // Try to parse as a correction
        guard let correction = CorrectionGrammar.parse(utterance) else {
            // Not a correction — close window and return nil
            closeWindow()
            return nil
        }

        // Write the correction to vocab
        do {
            try profileStore.addVocabEntry(heard: correction.heard, intended: correction.intended, learnedAt: Date())
        } catch {
            return CorrectionResult(learned: false, rewriteText: nil)
        }

        // Perform in-place rewrite if we have the prior injection length
        if let priorLength = lastInjectionLength {
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
