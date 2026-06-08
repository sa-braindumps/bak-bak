import AppKit
import ArgumentParser
import Foundation

// MARK: - CLI mode

struct BakBakCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bak-bak",
        abstract: "Voice dictation with vocabulary that persists and compounds.",
        subcommands: [Setup.self, Doctor.self, Vocab.self, History.self],
        defaultSubcommand: Doctor.self
    )
}

// MARK: - App mode

let arguments = CommandLine.arguments
let isCLI = arguments.count > 1 && ["setup", "doctor", "vocab", "history", "--help", "-h"].contains(arguments[1])

if isCLI {
    BakBakCLI.main()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
