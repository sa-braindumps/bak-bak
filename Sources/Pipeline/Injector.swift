import ApplicationServices
import AppKit
import Foundation

/// Inserts text at the cursor via clipboard + simulated Cmd+V.
/// Requires Accessibility permission for CGEvent posting.
public final class Injector: @unchecked Sendable {

    public enum InjectionResult: Sendable {
        case inserted
        case failure(String)
    }

    public init() {}

    /// Insert text at the currently focused element.
    /// Uses clipboard + Cmd+V which works in all apps (browsers, Electron, native).
    public func inject(_ text: String) -> InjectionResult {
        guard isAccessibilityGranted() else {
            return .failure("accessibility denied")
        }
        return insertViaClipboard(text)
    }

    /// Place text on the clipboard, simulate Cmd+V, then restore the previous clipboard.
    private func insertViaClipboard(_ text: String) -> InjectionResult {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.pasteboardItems?.compactMap { item -> (NSPasteboard.PasteboardType, Data)? in
            guard let type = item.types.first, let data = item.data(forType: type) else { return nil }
            return (type, data)
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

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

        // Restore previous clipboard after paste completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let items = previousContents, !items.isEmpty {
                pasteboard.clearContents()
                for (type, data) in items {
                    pasteboard.setData(data, forType: type)
                }
            }
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

    /// Check if Accessibility permission is granted.
    public func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }
}
