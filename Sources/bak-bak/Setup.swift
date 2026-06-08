import ArgumentParser
import AVFoundation
import Foundation
import Pipeline

/// `bak-bak setup` — exactly 4 actions.
struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Configure bak-bak: API key, hotkey, and accessibility permission."
    )

    @Option(name: .long, help: "OpenAI API key")
    var apiKey: String?

    func run() throws {
        let profileStore = ProfileStore()

        print("bak-bak setup")

        // Step 1: Get API key
        let key: String
        if let providedKey = apiKey {
            key = providedKey
            print("  [1/4] API key ......... pasted")
        } else {
            print("  [1/4] API key ......... ", terminator: "")
            guard let input = readLine() else {
                throw ExitCode.failure
            }
            key = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                print("\nNo key provided. Exiting.")
                throw ExitCode.failure
            }
        }

        // Step 2: Validate key (make a minimal API call)
        print("  [2/4] Validating ...... ", terminator: "")
        let validated = validateApiKey(key)
        if !validated {
            print("API key rejected. Run bak-bak setup again with a valid key.")
            throw ExitCode.failure
        }
        print("ok")

        // Step 3: Confirm hotkey
        print("  [3/4] Hotkey .......... ⌥ Option   (press enter to keep)")
        _ = readLine()

        // Step 4: Accessibility
        print("  [4/4] Accessibility ... ", terminator: "")
        let injector = Injector()
        if injector.isAccessibilityGranted() {
            print("granted ✓")
        } else {
            print("waiting…")
            // Open Accessibility settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            print("  Grant Accessibility to bak-bak in System Settings, then press enter.")
            _ = readLine()

            if injector.isAccessibilityGranted() {
                print("  granted ✓")
            } else {
                print("  still denied — text will go to clipboard. You can grant later.")
            }
        }

        // Write profile
        try profileStore.setApiKey(key)

        // Also write a default profile.toml with commented examples
        let defaultProfile = """
        # ~/.bak-bak/profile.toml
        # This file is yours. Edit it, diff it, put it in git. There is no hidden state.

        [vocab]
        # Teach Bak-Bak a term once and it is corrected forever.
        # Format:  "what whisper heard" = "what you meant"
        # Example (uncomment or copy your own):
        # "cube cuttle" = "kubectl"
        # "nicks"       = "Nginx"

        [hotkey]
        trigger = "option"

        [correction]
        correction_window_secs = 10
        """

        let dir = profileStore.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? defaultProfile.write(to: profileStore.fileURL, atomically: true, encoding: .utf8)

        // Re-write the API key since the default profile might have overwritten it
        try profileStore.setApiKey(key)

        print()
        print("Setup complete. Hold ⌥ anywhere and start talking.")
        print("Note: first launch may say \"can't be opened\" — right-click the app → Open.")
    }

    private func validateApiKey(_ key: String) -> Bool {
        // Make a minimal request to the Whisper API to check if the key is valid.
        // We'll use the models endpoint which requires auth but doesn't need audio.
        let semaphore = DispatchSemaphore(value: 0)
        var isValid = false

        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                isValid = httpResponse.statusCode == 200
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        return isValid
    }
}

import AppKit
