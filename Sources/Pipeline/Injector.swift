import ApplicationServices
import AppKit
import Foundation

/// Inserts text at the cursor via clipboard + simulated Cmd+V.
/// Requires Accessibility permission for CGEvent posting.
public final class Injector: @unchecked Sendable {

    public enum InjectionResult: Sendable, Equatable {
        case inserted
        /// Couldn't type (no Accessibility permission), so the text was left
        /// on the clipboard for the user to paste.
        case copiedToClipboard
        case failure(String)
    }

    /// How long to wait before putting the user's clipboard back. Slow apps
    /// (Electron, remote desktops) read the pasteboard well after Cmd+V.
    private static let restoreDelay: TimeInterval = 0.5

    public init() {}

    /// Insert text at the currently focused element.
    /// Uses clipboard + Cmd+V which works in all apps (browsers, Electron, native).
    public func inject(_ text: String) -> InjectionResult {
        guard isAccessibilityGranted() else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copiedToClipboard
        }
        return insertViaClipboard(text)
    }

    /// Place text on the clipboard, simulate Cmd+V, then restore the previous clipboard.
    private func insertViaClipboard(_ text: String) -> InjectionResult {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot(of: pasteboard)
        let ourChangeCount = ClipboardSnapshot.placeTransient(text, on: pasteboard)

        usleep(50_000)

        let source = CGEventSource(stateID: .hidSystemState)
        source?.setLocalEventsFilterDuringSuppressionState(.permitLocalKeyboardEvents, state: .eventSuppressionStateSuppressionInterval)

        let vKeyCode: CGKeyCode = 9
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return .failure("failed to create CGEvent")
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        usleep(10_000)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        // Put the user's clipboard back once the paste has had time to land.
        // Skipped if they copied something new in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay) {
            snapshot.restore(to: pasteboard, ifUnchangedSince: ourChangeCount)
        }

        return .inserted
    }

    /// Type characters via CGEvent (for backspace+retype rewrite).
    public func typeCharacters(_ text: String) {
        for char in text {
            var utf16 = Array(String(char).utf16)
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            event?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            event?.post(tap: .cgAnnotatedSessionEventTap)

            let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            upEvent?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            upEvent?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// Send backspace keystrokes.
    public func sendBackspaces(count: Int) {
        for _ in 0..<count {
            let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: true)
            downEvent?.post(tap: .cgAnnotatedSessionEventTap)

            let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: false)
            upEvent?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// Select text backward from the cursor by posting Shift+LeftArrow `count`
    /// times. Used by the "select that" / "select last sentence" voice command
    /// to highlight the just-injected text.
    public func selectBackward(count: Int) {
        let leftArrow: CGKeyCode = 123
        for _ in 0..<count {
            let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: leftArrow, keyDown: true)
            downEvent?.flags = .maskShift
            downEvent?.post(tap: .cgAnnotatedSessionEventTap)

            let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: leftArrow, keyDown: false)
            upEvent?.flags = .maskShift
            upEvent?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// Check if Accessibility permission is granted.
    public func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }
}
