import ArgumentParser
import Foundation
import Pipeline

/// `bak-bak history` — show recent transcriptions.
struct History: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show recent transcription history."
    )

    @Option(name: .shortAndLong, help: "Number of entries to show.")
    var count: Int = 20

    func run() throws {
        let history = TranscriptionHistory()
        let entries = history.loadRecent(limit: count)

        if entries.isEmpty {
            print("No transcription history yet.")
            return
        }

        print("Recent transcriptions (\(entries.count)):\n")

        let dateIn = ISO8601DateFormatter()
        dateIn.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateOut = DateFormatter()
        dateOut.dateFormat = "MMM d, h:mm:ss a"

        for entry in entries.reversed() {
            let timeStr: String
            if let date = dateIn.date(from: entry.timestamp) {
                timeStr = dateOut.string(from: date)
            } else {
                timeStr = entry.timestamp
            }

            let latency = "\(entry.latencyMs)ms"

            if entry.raw == entry.corrected {
                print("  \(timeStr)  [\(latency)]  \(entry.corrected)")
            } else {
                print("  \(timeStr)  [\(latency)]  \(entry.corrected)")
                print("               raw: \(entry.raw)")
            }
        }
    }
}
