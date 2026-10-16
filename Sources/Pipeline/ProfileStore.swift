import Foundation
import TOMLKit

/// Manages read/write access to `~/.bak-bak/profile.toml`.
/// Reads go through TOMLKit; writes go through `TOMLLineEditor` so comments
/// (including the load-bearing `# learned <timestamp>` ones) survive.
public final class ProfileStore: @unchecked Sendable {

    public struct Profile: Codable {
        public var vocab: [String: String]
        public var snippets: [String: String]
        public var hotkeyModifiers: String
        public var recordingMode: String
        public var correctionWindowSecs: Int
        public var soundEnabled: Bool
        public var removeFillers: Bool

        public init(
            vocab: [String: String] = [:],
            snippets: [String: String] = [:],
            hotkeyModifiers: String = "control+option",
            recordingMode: String = "hold",
            correctionWindowSecs: Int = 10,
            soundEnabled: Bool = true,
            removeFillers: Bool = false
        ) {
            self.vocab = vocab
            self.snippets = snippets
            self.hotkeyModifiers = hotkeyModifiers
            self.recordingMode = recordingMode
            self.correctionWindowSecs = correctionWindowSecs
            self.soundEnabled = soundEnabled
            self.removeFillers = removeFillers
        }
    }

    public let fileURL: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()

    public init(fileURL: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.fileURL = fileURL ?? home.appendingPathComponent(".bak-bak/profile.toml")
    }

    // MARK: - Ensure directory exists

    private func ensureDirectoryExists() throws {
        let dir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Read

    public func read() throws -> Profile {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return Profile()
        }
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        let toml = try TOMLTable(string: raw)
        return try parseProfile(toml)
    }

    private func parseProfile(_ toml: TOMLTable) throws -> Profile {
        var profile = Profile()

        if let vocabTable = toml["vocab"]?.table {
            for (key, value) in vocabTable {
                if let str = value.string {
                    profile.vocab[key] = str
                }
            }
        }

        if let snippetsTable = toml["snippets"]?.table {
            for (key, value) in snippetsTable {
                if let str = value.string {
                    profile.snippets[key] = str
                }
            }
        }

        if let cleanup = toml["cleanup"]?.table {
            profile.removeFillers = cleanup["remove_fillers"]?.bool ?? false
        }

        if let hotkey = toml["hotkey"]?.table {
            profile.hotkeyModifiers = hotkey["modifiers"]?.string ?? "control+option"
            profile.recordingMode = hotkey["recording_mode"]?.string ?? "hold"
        }

        if let correction = toml["correction"]?.table {
            profile.correctionWindowSecs = correction["correction_window_secs"]?.int ?? 10
        }

        if let general = toml["general"]?.table {
            profile.soundEnabled = general["sound_enabled"]?.bool ?? true
        }

        return profile
    }

    // MARK: - Write

    /// Write the whole profile. Existing comments, unknown keys (e.g. `api_key`)
    /// and layout are kept; `[vocab]` and `[snippets]` end up exactly matching
    /// `profile`.
    public func write(_ profile: Profile) throws {
        try edit { editor in
            for table in ["vocab", "snippets"] {
                let wanted = table == "vocab" ? profile.vocab : profile.snippets
                for key in editor.keys(in: table) where wanted[key] == nil {
                    editor.remove(key, in: table)
                }
                for (key, value) in wanted.sorted(by: { $0.key < $1.key }) {
                    editor.set(key, to: TOMLLineEditor.string(value), in: table)
                }
            }
            editor.set("remove_fillers", to: String(profile.removeFillers), in: "cleanup")
            editor.set("modifiers", to: TOMLLineEditor.string(profile.hotkeyModifiers), in: "hotkey")
            editor.set("recording_mode", to: TOMLLineEditor.string(profile.recordingMode), in: "hotkey")
            editor.set("correction_window_secs", to: String(profile.correctionWindowSecs), in: "correction")
            editor.set("sound_enabled", to: String(profile.soundEnabled), in: "general")
        }
    }

    /// Apply line-level edits to the file under the lock. The result is parsed
    /// before it is saved, so a bad edit never replaces a readable file.
    private func edit(_ body: (inout TOMLLineEditor) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectoryExists()

        let raw = fileManager.fileExists(atPath: fileURL.path)
            ? try String(contentsOf: fileURL, encoding: .utf8)
            : ""
        var editor = TOMLLineEditor(raw)
        body(&editor)

        let output = editor.text
        _ = try TOMLTable(string: output)
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Vocab operations

    /// Add or update a vocab entry. Pass `learnedAt` for corrections taught by
    /// voice: the entry gets a `# learned <ISO-8601-Z>` comment, which is what
    /// `doctor` reads back as correction history.
    public func addVocabEntry(heard: String, intended: String, learnedAt: Date? = nil) throws {
        let comment = learnedAt.map { "learned \(ISO8601DateFormatter().string(from: $0))" }
        try edit { $0.set(heard, to: TOMLLineEditor.string(intended), in: "vocab", comment: comment) }
    }

    public func removeVocabEntry(heard: String) throws {
        try edit { $0.remove(heard, in: "vocab") }
    }

    // MARK: - Snippet operations

    /// Add or update a snippet (`"trigger" = "expansion"`).
    public func addSnippet(trigger: String, expansion: String) throws {
        try edit { $0.set(trigger, to: TOMLLineEditor.string(expansion), in: "snippets") }
    }

    /// Remove a snippet by trigger. No-op if the file or trigger is absent.
    public func removeSnippet(trigger: String) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try edit { $0.remove(trigger, in: "snippets") }
    }

    // MARK: - Settings

    /// Toggle deterministic filler removal (`[cleanup].remove_fillers`).
    public func setRemoveFillers(_ enabled: Bool) throws {
        try edit { $0.set("remove_fillers", to: String(enabled), in: "cleanup") }
    }

    public func setApiKey(_ key: String) throws {
        try edit { $0.set("api_key", to: TOMLLineEditor.string(key), in: "general") }
    }

    public func setHotkeyModifiers(_ modifiers: String) throws {
        try edit { $0.set("modifiers", to: TOMLLineEditor.string(modifiers), in: "hotkey") }
    }

    public func setRecordingMode(_ mode: String) throws {
        try edit { $0.set("recording_mode", to: TOMLLineEditor.string(mode), in: "hotkey") }
    }

    public func setSoundEnabled(_ enabled: Bool) throws {
        try edit { $0.set("sound_enabled", to: String(enabled), in: "general") }
    }

    public func getApiKey() throws -> String? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        let toml = try TOMLTable(string: raw)
        return toml["general"]?.table?["api_key"]?.string
    }

    // MARK: - Learned corrections (for doctor)

    public func recentCorrections(limit: Int = 5) throws -> [(heard: String, intended: String, timestamp: String)] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        let toml = try TOMLTable(string: raw)

        guard toml["vocab"]?.table != nil else {
            return []
        }

        // Parse lines for "# learned <timestamp>" comments followed by entries
        var corrections: [(heard: String, intended: String, timestamp: String)] = []
        let lines = raw.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# learned ") {
                let timestamp = String(trimmed.dropFirst("# learned ".count))
                // Next non-empty line should be the entry
                if index + 1 < lines.count {
                    let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    if let eqIndex = nextLine.firstIndex(of: "=") {
                        let key = nextLine[nextLine.startIndex..<eqIndex]
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        let value = nextLine[nextLine.index(after: eqIndex)...]
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        corrections.append((heard: key, intended: String(value), timestamp: timestamp))
                    }
                }
            }
        }

        return Array(corrections.suffix(limit))
    }
}
