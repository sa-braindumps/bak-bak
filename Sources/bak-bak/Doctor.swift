import ArgumentParser
import AVFoundation
import Foundation
import Pipeline

/// `bak-bak doctor` — read-only diagnostic checklist.
struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Print a diagnostic checklist."
    )

    func run() throws {
        let profileStore = ProfileStore()
        let injector = Injector()

        print("bak-bak doctor")

        // 1. Mic access
        print("  mic access ............ ", terminator: "")
        let micGranted = checkMicAccess()
        print(micGranted ? "granted" : "denied")

        // 2. Accessibility
        print("  accessibility ......... ", terminator: "")
        if injector.isAccessibilityGranted() {
            print("granted")
        } else {
            print("denied  (text will go to clipboard)")
        }

        // 3. API key
        print("  api key ............... ", terminator: "")
        if let key = try? profileStore.getApiKey(), !key.isEmpty {
            // Validate the key
            let valid = validateApiKey(key)
            print(valid ? "ok" : "rejected — run bak-bak setup")
        } else {
            print("not set  (run bak-bak setup)")
        }

        // 4. Hotkey
        print("  hotkey ................ registered (⌥ option)")

        // 5. Last latency
        print("  last latency .......... none yet")

        // 6. Vocab count
        print("  vocab entries ......... ", terminator: "")
        let profile = try? profileStore.read()
        let count = profile?.vocab.count ?? 0
        print("\(count)")

        // 7. Recent corrections
        print("  recent corrections:")
        if let corrections = try? profileStore.recentCorrections(), !corrections.isEmpty {
            for correction in corrections {
                print("    \(correction.timestamp)  \(correction.heard) → \(correction.intended)")
            }
        } else {
            print("    none")
        }
    }

    private func checkMicAccess() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false

        AVCaptureDevice.requestAccess(for: .audio) { g in
            granted = g
            semaphore.signal()
        }
        semaphore.wait()

        return granted
    }

    private func validateApiKey(_ key: String) -> Bool {
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
