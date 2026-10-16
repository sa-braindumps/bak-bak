import Foundation

/// The rules for when a recording starts, stops, or gets thrown away.
///
/// The app feeds it raw input (hotkey down/up, Esc, the 60s cap, pipeline
/// finished) and does whatever action comes back. Keeping the rules here, in
/// one value type, means there's a single source of truth for "are we
/// recording?" instead of flags spread across the hotkey monitor and the app.
public struct RecordingStateMachine: Equatable {

    public enum Mode: String, Equatable {
        /// Hold the hotkey to record, release to transcribe.
        case hold
        /// Press once to start, press again to transcribe.
        case toggle

        public init(configValue: String) {
            self = Mode(rawValue: configValue) ?? .hold
        }
    }

    public enum Phase: Equatable {
        case idle
        case recording
        /// Audio has been sent off; a new recording can't start until the
        /// pipeline reports `.finished`. Stops two runs typing out of order.
        case transcribing
    }

    public enum Event: Equatable {
        case hotkeyDown
        case hotkeyUp(heldFor: TimeInterval)
        /// Esc or the menu's Cancel item.
        case cancel
        /// The recorder hit its maximum duration.
        case limitReached
        /// The mic changed under us (AirPods connected, …); the engine stopped.
        case inputChanged
        /// A non-modifier key was pressed while the hotkey was held, so the
        /// hotkey was part of a shortcut (⌘⇧4), not a dictation.
        case otherKeyPressed
        /// Transcription and injection are done (success or failure).
        case finished
    }

    public enum DiscardReason: Equatable {
        case cancelled
        /// Hotkey tapped too briefly to be a dictation.
        case tooShort
        /// Toggle mode hit the cap; likely a forgotten recording.
        case limitReached
        /// The hotkey turned out to be part of a keyboard shortcut.
        case shortcut
    }

    public enum Action: Equatable {
        case none
        case start
        case stopAndTranscribe
        case discard(DiscardReason)
    }

    /// A hold shorter than this is treated as an accidental tap.
    public static let minimumHold: TimeInterval = 0.3

    public var mode: Mode
    public private(set) var phase: Phase = .idle

    public init(mode: Mode) {
        self.mode = mode
    }

    public mutating func handle(_ event: Event) -> Action {
        switch (phase, event) {

        case (.idle, .hotkeyDown):
            phase = .recording
            return .start

        case (.recording, .hotkeyDown) where mode == .toggle:
            phase = .transcribing
            return .stopAndTranscribe

        case (.recording, .hotkeyUp(let heldFor)) where mode == .hold:
            if heldFor < Self.minimumHold {
                phase = .idle
                return .discard(.tooShort)
            }
            phase = .transcribing
            return .stopAndTranscribe

        case (.recording, .cancel):
            phase = .idle
            return .discard(.cancelled)

        case (.recording, .limitReached):
            // Holding the key for a full minute is deliberate, so keep it.
            // In toggle mode it's most likely a recording someone forgot.
            if mode == .hold {
                phase = .transcribing
                return .stopAndTranscribe
            }
            phase = .idle
            return .discard(.limitReached)

        case (.recording, .inputChanged):
            // Keep what was said before the switch.
            phase = .transcribing
            return .stopAndTranscribe

        case (.recording, .otherKeyPressed):
            phase = .idle
            return .discard(.shortcut)

        case (.transcribing, .finished):
            phase = .idle
            return .none

        default:
            return .none
        }
    }
}
