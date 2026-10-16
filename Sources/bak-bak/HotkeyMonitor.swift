import AppKit
import Foundation

/// Reports raw hotkey presses and Esc. It doesn't decide what they mean;
/// `RecordingStateMachine` does.
public final class HotkeyMonitor {

    public var onHotkeyDown: (() -> Void)?
    public var onHotkeyUp: ((TimeInterval) -> Void)?
    public var onEscape: (() -> Void)?
    public var modifierKeys: NSEvent.ModifierFlags = [.control, .option]

    /// While true, Esc is caught (and kept from the frontmost app) and reported
    /// through `onEscape`. Set it only while a recording is running.
    public var isCapturingEscape = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var escapeTap: CFMachPort?
    private var escapeFallbackMonitor: Any?
    private var isSwallowingEscape = false
    private var isKeyHeld = false
    private var keyDownTime: Date?
    private static let escapeKeyCode: Int64 = 53

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

    deinit {
        stop()
    }

    public func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        setupGlobalMonitor()
        setupEscapeTap()
    }

    public func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = escapeFallbackMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let tap = escapeTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        globalMonitor = nil
        localMonitor = nil
        escapeFallbackMonitor = nil
        escapeTap = nil
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
        let pressed = event.modifierFlags.contains(modifierKeys)

        if pressed && !isKeyHeld {
            isKeyHeld = true
            keyDownTime = Date()
            DispatchQueue.main.async { self.onHotkeyDown?() }
        } else if !pressed && isKeyHeld {
            isKeyHeld = false
            let heldFor = Date().timeIntervalSince(keyDownTime ?? Date())
            DispatchQueue.main.async { self.onHotkeyUp?(heldFor) }
        }
    }

    // MARK: - Esc to cancel

    /// An event tap lets us swallow Esc while recording, so cancelling doesn't
    /// also close a dialog or interrupt a terminal. If the tap can't be created
    /// we fall back to a passive monitor: Esc still cancels, but the app sees it.
    private func setupEscapeTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handleTapEvent(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            escapeFallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isCapturingEscape, Int64(event.keyCode) == Self.escapeKeyCode else { return }
                self.onEscape?()
            }
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        escapeTap = tap
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that's slow or when input is secure; turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = escapeTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown && isCapturingEscape {
            isSwallowingEscape = true
            DispatchQueue.main.async { self.onEscape?() }
            return nil
        }
        // Swallow the matching key-up too, even though capture has ended by now.
        if type == .keyUp && isSwallowingEscape {
            isSwallowingEscape = false
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
