import ArgumentParser
import Foundation
import Pipeline

/// `bak-bak snippet add`, `bak-bak snippet list`, `bak-bak snippet remove`.
struct Snippet: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snippet",
        abstract: "Manage your voice snippets (trigger phrase → expansion).",
        subcommands: [Add.self, List.self, Remove.self]
    )

    /// `bak-bak snippet add "<trigger>" "<expansion>"`
    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add or update a snippet."
        )

        @Argument(help: "The trigger phrase you speak")
        var trigger: String

        @Argument(help: "The text it expands to")
        var expansion: String

        func run() throws {
            let profileStore = ProfileStore()
            try profileStore.addSnippet(trigger: trigger, expansion: expansion)
            print("added: \"\(trigger)\" → \"\(expansion)\"")
        }
    }

    /// `bak-bak snippet list`
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Print the current snippets."
        )

        func run() throws {
            let profileStore = ProfileStore()
            let profile = try profileStore.read()

            guard !profile.snippets.isEmpty else {
                print("No snippets.")
                return
            }

            // First line of each expansion only, so multi-line bodies stay readable.
            let triggerWidth = max("trigger".count, profile.snippets.keys.map { $0.count }.max() ?? 0)
            let preview: (String) -> String = { value in
                let firstLine = value.components(separatedBy: .newlines).first ?? value
                return value.contains("\n") ? "\(firstLine) …" : firstLine
            }
            let expandWidth = max("expansion".count, profile.snippets.values.map { preview($0).count }.max() ?? 0)

            print("trigger\(String(repeating: " ", count: triggerWidth - "trigger".count + 2))expansion")
            print("\(String(repeating: "─", count: triggerWidth))  \(String(repeating: "─", count: expandWidth))")

            for (trigger, expansion) in profile.snippets.sorted(by: { $0.key < $1.key }) {
                let padding = String(repeating: " ", count: triggerWidth - trigger.count + 2)
                print("\(trigger)\(padding)\(preview(expansion))")
            }
        }
    }

    /// `bak-bak snippet remove "<trigger>"`
    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove a snippet by trigger."
        )

        @Argument(help: "The trigger phrase to remove")
        var trigger: String

        func run() throws {
            let profileStore = ProfileStore()
            try profileStore.removeSnippet(trigger: trigger)
            print("removed: \"\(trigger)\"")
        }
    }
}
