import AppKit
import Pipeline

/// Manages the 10-second correction window after each injection.
/// Parses correction grammars, writes vocabulary, and performs in-place rewrite.
public final class CorrectionController {

    public struct CorrectionResult {
        public let learned: Bool
        public let heard: String
        public let intended: String
        /// The fixed text that replaced the original on screen, or nil if the
        /// rewrite was skipped (focus changed) and only the vocab was updated.
        public let rewriteText: String?
    }

    private let profileStore: ProfileStore
    private let injector: Injector
    private var correctionWindowStart: Date?
    private var windowDuration: TimeInterval
    /// The text typed by the last dictation, while the window is open.
    private var lastInjectedText: String?
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
        return lastInjectedText?.count
    }

    public init(profileStore: ProfileStore, injector: Injector) {
        self.profileStore = profileStore
        self.injector = injector
        let profile = try? profileStore.read()
        self.windowDuration = TimeInterval(profile?.correctionWindowSecs ?? 10)
    }

    /// Open the correction window after `text` was typed.
    public func openWindow(afterInjecting text: String) {
        lastInjectedText = text
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
        lastInjectedText = nil
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

    /// If `utterance` is a correction of the last dictation ("no, X is Y"),
    /// learn X → Y and fix the text on screen. Returns nil (and closes the
    /// window) when it isn't, so the caller treats it as normal dictation.
    public func processUtterance(_ utterance: String) -> CorrectionResult? {
        guard windowOpen, let lastText = lastInjectedText else { return nil }

        guard let correction = CorrectionGrammar.parse(utterance, lastText: lastText) else {
            closeWindow()
            return nil
        }

        do {
            try profileStore.addVocabEntry(heard: correction.heard, intended: correction.intended, learnedAt: Date())
        } catch {
            closeWindow()
            return CorrectionResult(learned: false, heard: correction.heard, intended: correction.intended, rewriteText: nil)
        }

        // Retype the *original* text with the new rule applied. If focus has
        // moved we can't safely backspace, so the fix only applies from the
        // next dictation on (SPEC §7.5).
        var rewritten: String?
        if let length = lastInjectionLength {
            let fixed = Substitutor.apply(lastText, vocab: [correction.heard: correction.intended])
            if fixed != lastText {
                injector.sendBackspaces(count: length)
                injector.typeCharacters(fixed)
                rewritten = fixed
            }
        }

        closeWindow()
        return CorrectionResult(learned: true, heard: correction.heard, intended: correction.intended, rewriteText: rewritten)
    }

    /// Check if a term was heard (for auto-correction during normal dictation).
    public func autoCorrectIfNeeded(_ text: String, vocab: [String: String]) -> String {
        return Substitutor.apply(text, vocab: vocab)
    }
}
