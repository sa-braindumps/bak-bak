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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        coordinator = AppCoordinator()
        hotkeyMonitor = HotkeyMonitor()

        setupStatusItem()
        setupHotkey()
        setupMenu()

        requestMicPermission()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if #available(macOS 11.0, *) {
                let image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Bak-Bak")
                image?.isTemplate = true
                button.image = image
            }
            button.toolTip = "Bak-Bak — hold ⌃⌥ to talk"
        }
    }

    // MARK: - Menu

    private func setupMenu() {
        menu = NSMenu()

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
        hotkeyMonitor.onRecordingStart = { [weak self] in
            self?.handleRecordingStart()
        }

        hotkeyMonitor.onRecordingStop = { [weak self] in
            self?.handleRecordingStop()
        }

        hotkeyMonitor.start()
    }

    private func handleRecordingStart() {
        if (try? profileStore.read())?.soundEnabled != false {
            NSSound(named: "Tink")?.play()
        }
        coordinator.startRecording()
        updateStatusItem(state: .recording)
        overlay.show()
    }

    private func handleRecordingStop() {
        if (try? profileStore.read())?.soundEnabled != false {
            NSSound(named: "Pop")?.play()
        }
        overlay.showTranscribing()
        coordinator.stopRecording { [weak self] result in
            switch result {
            case .success:
                self?.overlay.hide()
                self?.updateStatusItem(state: .idle)
            case .failure(let error):
                let msg = error.localizedDescription
                if !msg.isEmpty {
                    self?.overlay.showError(msg)
                } else {
                    self?.overlay.hide()
                }
                self?.updateStatusItem(state: .error(msg))
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self?.updateStatusItem(state: .idle)
                }
            }
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
                if #available(macOS 11.0, *) {
                    let image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Bak-Bak")
                    image?.isTemplate = true
                    self.statusItem.button?.image = image
                }
                self.statusItem.button?.toolTip = "Bak-Bak — hold ⌃⌥ to talk"

            case .recording:
                if #available(macOS 11.0, *) {
                    let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording")
                    image?.isTemplate = true
                    self.statusItem.button?.image = image
                }
                self.statusItem.button?.toolTip = "Recording… release ⌃⌥ to transcribe"

            case .transcribing:
                self.startPulseAnimation()
                self.statusItem.button?.toolTip = "Transcribing…"

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
                    self.updateStatusItem(state: .error("Mic access denied — grant in System Settings"))
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
        alert.informativeText = "बक-बक — Voice dictation with vocabulary that persists and compounds.\n\nHold ⌃⌥ anywhere and start talking."
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
            text += "\"\(heard)\" → \"\(intended)\"\n"
        }

        let alert = NSAlert()
        alert.messageText = "Bak-Bak Vocabulary"
        alert.informativeText = vocab.isEmpty ? "No entries yet." : text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
