import AppKit
import SwiftUI

final class DashboardWindow {

    private var window: NSWindow?
    private let viewModel = DashboardViewModel()

    func selectSettings() {
        viewModel.selectedTab = .settings
    }

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        viewModel.loadData()

        let dashboardView = DashboardView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: dashboardView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Bak-Bak"
        win.contentViewController = hostingController
        win.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)
        win.center()
        win.setFrameAutosaveName("BakBakDashboard")
        win.minSize = NSSize(width: 600, height: 400)
        win.isReleasedWhenClosed = false

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            self?.viewModel.loadData()
        }

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
