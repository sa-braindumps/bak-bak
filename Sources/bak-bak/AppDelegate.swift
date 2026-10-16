import AppKit
import AVFoundation
import Foundation
import Pipeline

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var hotkeyMonitor: HotkeyMonitor!
    private var coordinator: AppCoordinator!
    private var menu: NSMenu!
    private let overlay = RecordingOverlay()
    private let profileStore = ProfileStore()
    private var dashboard: DashboardWindow?
    private var recordingStartDate: Date = Date()
    private var session = RecordingStateMachine(mode: .hold)
    private var cancelItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        coordinator = AppCoordinator()
        hotkeyMonitor = HotkeyMonitor()

        if let profile = try? profileStore.read() {
            hotkeyMonitor.updateModifiers(from: profile.hotkeyModifiers)
            session.mode = RecordingStateMachine.Mode(configValue: profile.recordingMode)
        }

        setupStatusItem()
        setupHotkey()
        setupMenu()
        setupAudioLevelForwarding()
        setupDurationCallbacks()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyModifiersDidChange(_:)),
            name: .hotkeyModifiersChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(recordingModeDidChange(_:)),
            name: .recordingModeChanged,
            object: nil
        )

        requestMicPermission()
        checkFirstRun()
    }

    private func setupAudioLevelForwarding() {
        coordinator.onSpectrum = { [weak self] bands in
            self?.overlay.injectSpectrum(bands)
        }
    }

    private func setupDurationCallbacks() {
        coordinator.onAutoStop = { [weak self] in
            self?.handle(.limitReached)
        }
        coordinator.onNearLimit = { [weak self] in
            self?.overlay.showNearLimit()
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = menuBarIcon()
            button.toolTip = "Bak-Bak \u{2014} hold \u{2303}\u{2325} to talk"
        }
    }

    private func menuBarIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18))
        img.lockFocus()

        let bars: [(x: CGFloat, h: CGFloat)] = [
            (3, 6), (6, 11), (9, 14), (12, 11), (15, 6)
        ]
        let barW: CGFloat = 2
        let cy: CGFloat = 9

        NSColor.black.setFill()
        for bar in bars {
            let rect = NSRect(x: bar.x, y: cy - bar.h / 2, width: barW, height: bar.h)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            path.fill()
        }

        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    // MARK: - Menu

    private func setupMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false

        cancelItem = NSMenuItem(title: "Cancel Recording (Esc)", action: #selector(cancelFromMenu), keyEquivalent: "")
        cancelItem.target = self
        cancelItem.isEnabled = false
        menu.addItem(cancelItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About Bak-Bak", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let dashboardItem = NSMenuItem(title: "Dashboard", action: #selector(showDashboard), keyEquivalent: ",")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        menu.addItem(NSMenuItem.separator())

        let doctorItem = NSMenuItem(title: "Run Doctor", action: #selector(runDoctor), keyEquivalent: "d")
        doctorItem.target = self
        menu.addItem(doctorItem)

        let vocabItem = NSMenuItem(title: "Show Vocabulary", action: #selector(showVocab), keyEquivalent: "v")
        vocabItem.target = self
        menu.addItem(vocabItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Bak-Bak", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyMonitor.onHotkeyDown = { [weak self] in
            self?.handle(.hotkeyDown)
        }
        hotkeyMonitor.onHotkeyUp = { [weak self] heldFor in
            self?.handle(.hotkeyUp(heldFor: heldFor))
        }
        hotkeyMonitor.onEscape = { [weak self] in
            self?.handle(.cancel)
        }

        hotkeyMonitor.start()
    }

    @objc private func hotkeyModifiersDidChange(_ notification: Notification) {
        if let modifiers = notification.userInfo?["modifiers"] as? String {
            hotkeyMonitor.updateModifiers(from: modifiers)
        }
    }

    @objc private func recordingModeDidChange(_ notification: Notification) {
        if let mode = notification.userInfo?["mode"] as? String {
            session.mode = RecordingStateMachine.Mode(configValue: mode)
        }
    }

    @objc private func cancelFromMenu() {
        handle(.cancel)
    }

    /// Every recording input goes through here. The state machine decides what
    /// it means; this just carries out the action. Main thread only.
    private func handle(_ event: RecordingStateMachine.Event) {
        let action = session.handle(event)

        switch action {
        case .none:
            break
        case .start:
            handleRecordingStart()
        case .stopAndTranscribe:
            handleRecordingStop()
        case .discard(let reason):
            handleRecordingDiscard(reason)
        }

        let isRecording = session.phase == .recording
        hotkeyMonitor.isCapturingEscape = isRecording
        cancelItem.isEnabled = isRecording
    }

    private func handleRecordingStart() {
        recordingStartDate = Date()
        do {
            try coordinator.startRecording()
        } catch {
            handle(.cancel)
            overlay.showError("Couldn't start the mic")
            updateStatusItem(state: .error("Couldn't start the mic: \(error.localizedDescription)"))
            return
        }
        if (try? profileStore.read())?.soundEnabled != false {
            NSSound(named: "Tink")?.play()
        }
        updateStatusItem(state: .recording)
        overlay.show()
    }

    private func handleRecordingDiscard(_ reason: RecordingStateMachine.DiscardReason) {
        coordinator.cancelRecording()
        updateStatusItem(state: .idle)
        switch reason {
        case .cancelled:
            overlay.showDiscarded("Cancelled")
        case .tooShort:
            overlay.hide()
        case .limitReached:
            overlay.showDiscarded("Stopped at 60s")
        }
    }

    private func handleRecordingStop() {
        coordinator.stopRecording(
            onWillTranscribe: { [weak self] in
                guard let self = self else { return }
                self.playReleaseSound()
                let duration = Date().timeIntervalSince(self.recordingStartDate)
                self.overlay.showTranscribing(recordingDuration: duration)
            },
            completion: { [weak self] result in
                DispatchQueue.main.async { self?.handleRecordingResult(result) }
            }
        )
    }

    private func handleRecordingResult(_ result: Result<String, Error>) {
        handle(.finished)

        switch result {
        case .success(let text):
            overlay.showDone(text: text)
            updateStatusItem(state: .idle)
        case .failure(AppCoordinator.CoordinatorError.silenceDetected):
            overlay.showDiscarded()
            updateStatusItem(state: .idle)
        case .failure(AppCoordinator.CoordinatorError.emptyRecording):
            overlay.hide()
            updateStatusItem(state: .idle)
        case .failure(let error):
            let msg = error.localizedDescription
            if !msg.isEmpty {
                overlay.showError(msg)
            } else {
                overlay.hide()
            }
            updateStatusItem(state: .error(msg))
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                // Don't clobber the icon of a recording that started since.
                guard let self, self.session.phase == .idle else { return }
                self.updateStatusItem(state: .idle)
            }
        }
    }

    private func playReleaseSound() {
        if (try? profileStore.read())?.soundEnabled != false {
            NSSound(named: "Pop")?.play()
        }
    }

    // MARK: - Status Updates

    enum AppState {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    func updateStatusItem(state: AppState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch state {
            case .idle:
                self.pulseTimer?.invalidate()
                self.statusItem.button?.image = self.menuBarIcon()
                self.statusItem.button?.toolTip = "Bak-Bak \u{2014} hold \u{2303}\u{2325} to talk"

            case .recording:
                if #available(macOS 11.0, *) {
                    let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording")
                    image?.isTemplate = true
                    self.statusItem.button?.image = image
                }
                self.statusItem.button?.toolTip = "Recording\u{2026} release \u{2303}\u{2325} to transcribe"

            case .transcribing:
                self.startPulseAnimation()
                self.statusItem.button?.toolTip = "Transcribing\u{2026}"

            case .error(let reason):
                if #available(macOS 11.0, *) {
                    let image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Error")
                    image?.isTemplate = true
                    self.statusItem.button?.image = image
                }
                self.statusItem.button?.toolTip = reason
            }
        }
    }

    private var pulseTimer: Timer?

    private func startPulseAnimation() {
        var alt = false
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            alt.toggle()
            if #available(macOS 11.0, *) {
                let name = alt ? "mic" : "mic.fill"
                let image = NSImage(systemSymbolName: name, accessibilityDescription: "Transcribing")
                image?.isTemplate = true
                self.statusItem.button?.image = image
            }
        }
    }

    // MARK: - Mic Permission

    private func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.updateStatusItem(state: .error("Mic access denied \u{2014} grant in System Settings"))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        self.updateStatusItem(state: .idle)
                    }
                }
            }
        }
    }

    // MARK: - Menu Actions

    @objc private func showDashboard() {
        if dashboard == nil {
            dashboard = DashboardWindow()
        }
        dashboard?.showWindow()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Bak-Bak"
        alert.informativeText = "v0.1.0\n\n\u{092C}\u{0915}-\u{092C}\u{0915} \u{2014} Voice dictation with vocabulary that persists and compounds.\n\nHold \u{2303}\u{2325} anywhere and start talking."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func runDoctor() {
        let profileStore = ProfileStore()
        let injector = Injector()

        var report = ""

        report += "accessibility: \(injector.isAccessibilityGranted() ? "granted" : "denied (clipboard fallback)")\n"
        let hasKey = (try? profileStore.getApiKey()) != nil
        report += "api key: \(hasKey ? "set" : "not set")\n"
        let vocabCount = (try? profileStore.read())?.vocab.count ?? 0
        report += "vocab entries: \(vocabCount)\n"

        let alert = NSAlert()
        alert.messageText = "Bak-Bak Doctor"
        alert.informativeText = report
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func showVocab() {
        let profileStore = ProfileStore()
        let profile = try? profileStore.read()
        let vocab = profile?.vocab ?? [:]

        var text = "Vocabulary (\(vocab.count) entries)\n\n"
        for (heard, intended) in vocab.sorted(by: { $0.key < $1.key }) {
            text += "\"\(heard)\" \u{2192} \"\(intended)\"\n"
        }

        let alert = NSAlert()
        alert.messageText = "Bak-Bak Vocabulary"
        alert.informativeText = vocab.isEmpty ? "No entries yet." : text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - First Run

    private func checkFirstRun() {
        let needsApiKey = (try? profileStore.getApiKey())?.isEmpty ?? true
        let needsAccessibility = !Injector().isAccessibilityGranted()

        if needsAccessibility {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showAccessibilityPrompt()
            }
        }

        if needsApiKey {
            DispatchQueue.main.asyncAfter(deadline: .now() + (needsAccessibility ? 1.5 : 0.5)) {
                self.showDashboard()
                self.dashboard?.selectSettings()
            }
        }
    }

    private func showAccessibilityPrompt() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Bak-Bak needs Accessibility access to paste transcriptions into other apps.\n\nOpen System Settings \u{2192} Privacy & Security \u{2192} Accessibility, then enable Bak-Bak."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
