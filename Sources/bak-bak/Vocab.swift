import ArgumentParser
import Foundation
import Pipeline

/// `bak-bak vocab add` and `bak-bak vocab list`.
struct Vocab: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vocab",
        abstract: "Manage your vocabulary.",
        subcommands: [Add.self, List.self]
    )

    /// `bak-bak vocab add "heard" "intended"`
    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add or update a vocabulary entry."
        )

        @Argument(help: "What Whisper heard")
        var heard: String

        @Argument(help: "What you intended")
        var intended: String

        func run() throws {
            let profileStore = ProfileStore()
            try profileStore.addVocabEntry(heard: heard, intended: intended)
            print("added: \"\(heard)\" → \"\(intended)\"")
        }
    }

    /// `bak-bak vocab list`
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Print the current vocabulary."
        )

        func run() throws {
            let profileStore = ProfileStore()
            let profile = try profileStore.read()

            guard !profile.vocab.isEmpty else {
                print("No vocabulary entries.")
                return
            }

            // Calculate column widths
            let heardWidth = max("heard".count, profile.vocab.keys.map { $0.count }.max() ?? 0)
            let intendedWidth = max("intended".count, profile.vocab.values.map { $0.count }.max() ?? 0)

            print("heard\(String(repeating: " ", count: heardWidth - "heard".count + 2))intended")
            print("\(String(repeating: "─", count: heardWidth))  \(String(repeating: "─", count: intendedWidth))")

            for (heard, intended) in profile.vocab.sorted(by: { $0.key < $1.key }) {
                let padding1 = String(repeating: " ", count: heardWidth - heard.count + 2)
                let padding2 = String(repeating: " ", count: intendedWidth - intended.count)
                print("\(heard)\(padding1)\(intended)\(padding2)")
            }
        }
    }
}
