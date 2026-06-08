import AppKit
import Foundation

/// Monitors the global ⌥ hotkey (hold to record, release to transcribe).
/// Uses NSEvent flagsChanged for modifier detection.
public final class HotkeyMonitor {

    public var onRecordingStart: (() -> Void)?
    public var onRecordingStop: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isKeyHeld = false
    private var keyDownTime: Date?
    private let tapTooShortThreshold: TimeInterval = 0.3

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        // Request accessibility permission (needed for global event monitoring)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        setupGlobalMonitor()
    }

    public func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - NSEvent monitors

    private func setupGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        // Require BOTH Control + Option pressed
        let bothPressed = flags.contains(.control) && flags.contains(.option)

        if bothPressed && !isKeyHeld {
            isKeyHeld = true
            keyDownTime = Date()
            DispatchQueue.main.async { self.onRecordingStart?() }
        } else if !bothPressed && isKeyHeld {
            isKeyHeld = false

            let elapsed = Date().timeIntervalSince(keyDownTime ?? Date())
            if elapsed >= tapTooShortThreshold {
                DispatchQueue.main.async { self.onRecordingStop?() }
            }
        }
    }
}
