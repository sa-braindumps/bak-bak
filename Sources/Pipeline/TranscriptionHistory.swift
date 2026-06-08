import Foundation

/// Append-only JSONL log at `~/.bak-bak/history.jsonl`.
/// Each line is one transcription event — easy to tail, grep, or load in bulk.
public final class TranscriptionHistory: @unchecked Sendable {

    public struct Entry: Codable {
        public let timestamp: String
        public let raw: String
        public let corrected: String
        public let latencyMs: Int
        public let model: String
        public let injectionMethod: String?

        public init(timestamp: String, raw: String, corrected: String, latencyMs: Int, model: String, injectionMethod: String? = nil) {
            self.timestamp = timestamp
            self.raw = raw
            self.corrected = corrected
            self.latencyMs = latencyMs
            self.model = model
            self.injectionMethod = injectionMethod
        }
    }

    private let fileURL: URL
    private let lock = NSLock()
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init(fileURL: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.fileURL = fileURL ?? home.appendingPathComponent(".bak-bak/history.jsonl")
    }

    public func append(raw: String, corrected: String, latencyMs: Int, model: String = "gpt-4o-mini-transcribe", injectionMethod: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        let entry = Entry(
            timestamp: Self.dateFormatter.string(from: Date()),
            raw: raw,
            corrected: corrected,
            latencyMs: latencyMs,
            model: model,
            injectionMethod: injectionMethod
        )

        guard let data = try? JSONEncoder().encode(entry),
              let line = String(data: data, encoding: .utf8) else { return }

        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            handle.closeFile()
        } else {
            try? (line + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    public func loadAll() -> [Entry] {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return raw
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(Entry.self, from: data)
            }
    }

    public func loadRecent(limit: Int = 20) -> [Entry] {
        let all = loadAll()
        return Array(all.suffix(limit))
    }
}
