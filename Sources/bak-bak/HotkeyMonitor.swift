import AppKit
import Foundation

public final class HotkeyMonitor {

    public var onRecordingStart: (() -> Void)?
    public var onRecordingStop: (() -> Void)?
    public var modifierKeys: NSEvent.ModifierFlags = [.control, .option]
    public var recordingMode: String = "hold"

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isKeyHeld = false
    private var isToggleRecording = false
    private var keyDownTime: Date?
    private let tapTooShortThreshold: TimeInterval = 0.3

    public init() {}

    public func updateModifiers(from configString: String) {
        var flags: NSEvent.ModifierFlags = []
        for part in configString.lowercased().split(separator: "+") {
            switch part.trimmingCharacters(in: .whitespaces) {
            case "control": flags.insert(.control)
            case "option": flags.insert(.option)
            case "command": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "fn": flags.insert(.function)
            default: break
            }
        }
        if !flags.isEmpty {
            modifierKeys = flags
        }
    }

    public func resetToggleState() {
        isToggleRecording = false
    }

    deinit {
        stop()
    }

    public func start() {
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
        let bothPressed = flags.contains(modifierKeys)

        if recordingMode == "toggle" {
            if bothPressed && !isKeyHeld {
                isKeyHeld = true
                if isToggleRecording {
                    isToggleRecording = false
                    DispatchQueue.main.async { self.onRecordingStop?() }
                } else {
                    isToggleRecording = true
                    DispatchQueue.main.async { self.onRecordingStart?() }
                }
            } else if !bothPressed && isKeyHeld {
                isKeyHeld = false
            }
        } else {
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
}
