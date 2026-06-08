import Foundation
import TOMLKit

/// Manages read/write access to `~/.bak-bak/profile.toml`.
/// All writes are comment-preserving via TOMLKit so that
/// `# learned <timestamp>` comments survive round-trips.
public final class ProfileStore: @unchecked Sendable {

    public struct Profile: Codable {
        public var vocab: [String: String]
        public var hotkeyModifiers: String
        public var recordingMode: String
        public var correctionWindowSecs: Int
        public var soundEnabled: Bool

        public init(
            vocab: [String: String] = [:],
            hotkeyModifiers: String = "control+option",
            recordingMode: String = "hold",
            correctionWindowSecs: Int = 10,
            soundEnabled: Bool = true
        ) {
            self.vocab = vocab
            self.hotkeyModifiers = hotkeyModifiers
            self.recordingMode = recordingMode
            self.correctionWindowSecs = correctionWindowSecs
            self.soundEnabled = soundEnabled
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

    public func write(_ profile: Profile) throws {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectoryExists()

        // Read existing TOML to preserve fields not in Profile (e.g. api_key)
        var toml: TOMLTable
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try String(contentsOf: fileURL, encoding: .utf8)
            toml = try TOMLTable(string: raw)
        } else {
            toml = TOMLTable()
        }

        let vocabTable = TOMLTable()
        for (key, value) in profile.vocab {
            vocabTable[key] = value
        }
        toml["vocab"] = vocabTable

        let hotkeyTable = toml["hotkey"]?.table ?? TOMLTable()
        hotkeyTable["modifiers"] = profile.hotkeyModifiers
        hotkeyTable["recording_mode"] = profile.recordingMode
        toml["hotkey"] = hotkeyTable

        let correctionTable = toml["correction"]?.table ?? TOMLTable()
        correctionTable["correction_window_secs"] = profile.correctionWindowSecs
        toml["correction"] = correctionTable

        let generalTable = toml["general"]?.table ?? TOMLTable()
        generalTable["sound_enabled"] = profile.soundEnabled
        toml["general"] = generalTable

        let output = toml.convert()
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Vocab operations

    public func addVocabEntry(heard: String, intended: String) throws {
        lock.lock()
        defer { lock.unlock() }

        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try String(contentsOf: fileURL, encoding: .utf8)
            let toml = try TOMLTable(string: raw)

            let vocabTable = toml["vocab"]?.table ?? TOMLTable()
            vocabTable[heard] = intended
            toml["vocab"] = vocabTable

            let output = toml.convert()
            try output.write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            var profile = Profile()
            profile.vocab[heard] = intended
            try write(profile)
        }
    }

    public func setApiKey(_ key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectoryExists()

        var toml: TOMLTable
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try String(contentsOf: fileURL, encoding: .utf8)
            toml = try TOMLTable(string: raw)
        } else {
            toml = TOMLTable()
        }

        let generalTable = toml["general"]?.table ?? TOMLTable()
        generalTable["api_key"] = key
        toml["general"] = generalTable

        let output = toml.convert()
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func setHotkeyModifiers(_ modifiers: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectoryExists()

        var toml: TOMLTable
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try String(contentsOf: fileURL, encoding: .utf8)
            toml = try TOMLTable(string: raw)
        } else {
            toml = TOMLTable()
        }

        let hotkeyTable = toml["hotkey"]?.table ?? TOMLTable()
        hotkeyTable["modifiers"] = modifiers
        toml["hotkey"] = hotkeyTable

        let output = toml.convert()
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func setRecordingMode(_ mode: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectoryExists()

        var toml: TOMLTable
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try String(contentsOf: fileURL, encoding: .utf8)
            toml = try TOMLTable(string: raw)
        } else {
            toml = TOMLTable()
        }

        let hotkeyTable = toml["hotkey"]?.table ?? TOMLTable()
        hotkeyTable["recording_mode"] = mode
        toml["hotkey"] = hotkeyTable

        let output = toml.convert()
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func setSoundEnabled(_ enabled: Bool) throws {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectoryExists()

        var toml: TOMLTable
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try String(contentsOf: fileURL, encoding: .utf8)
            toml = try TOMLTable(string: raw)
        } else {
            toml = TOMLTable()
        }

        let generalTable = toml["general"]?.table ?? TOMLTable()
        generalTable["sound_enabled"] = enabled
        toml["general"] = generalTable

        let output = toml.convert()
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
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
