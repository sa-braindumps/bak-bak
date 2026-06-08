import Combine
import Foundation
import Pipeline
import ServiceManagement

extension Notification.Name {
    static let hotkeyModifiersChanged = Notification.Name("hotkeyModifiersChanged")
    static let recordingModeChanged = Notification.Name("recordingModeChanged")
}

final class DashboardViewModel: ObservableObject {

    enum Tab: String, CaseIterable, Identifiable {
        case home = "Home"
        case insights = "Insights"
        case dictionary = "Dictionary"
        case settings = "Settings"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .home: return "house"
            case .insights: return "chart.bar"
            case .dictionary: return "book"
            case .settings: return "gear"
            }
        }
    }

    struct Stats {
        let totalWords: Int
        let totalTranscriptions: Int
        let averageLatencyMs: Int
        let estimatedCost: Double

        static let empty = Stats(totalWords: 0, totalTranscriptions: 0, averageLatencyMs: 0, estimatedCost: 0)
    }

    struct DailyStats: Identifiable {
        let date: Date
        let wordCount: Int
        let transcriptionCount: Int
        var id: Date { date }
    }

    struct HourlyStats: Identifiable {
        let hour: Int
        let transcriptionCount: Int
        var id: Int { hour }
    }

    @Published var selectedTab: Tab = .home
    @Published var entries: [TranscriptionHistory.Entry] = []
    @Published var stats: Stats = .empty
    @Published var dailyStats: [DailyStats] = []
    @Published var hourlyStats: [HourlyStats] = []
    @Published var vocab: [String: String] = [:]
    @Published var apiKey: String = ""
    @Published var soundEnabled: Bool = true
    @Published var launchAtLogin: Bool = false
    @Published var hotkeyModifiers: String = "control+option"
    @Published var recordingMode: String = "hold"

    static let availableHotkeys = [
        "control+option",
        "command+option",
        "command+shift",
        "control+shift",
        "control+command"
    ]

    static func hotkeySymbols(_ combo: String) -> String {
        combo.split(separator: "+").map { key in
            switch key {
            case "control": return "\u{2303}"
            case "option": return "\u{2325}"
            case "command": return "\u{2318}"
            case "shift": return "\u{21E7}"
            default: return String(key)
            }
        }.joined()
    }

    private let history = TranscriptionHistory()
    private let profileStore = ProfileStore()

    func loadData() {
        let allEntries = history.loadAll()
        entries = allEntries.reversed()
        stats = computeStats(from: allEntries)
        dailyStats = computeDailyStats(from: allEntries)
        hourlyStats = computeHourlyStats(from: allEntries)

        if let profile = try? profileStore.read() {
            vocab = profile.vocab
            soundEnabled = profile.soundEnabled
            hotkeyModifiers = profile.hotkeyModifiers
            recordingMode = profile.recordingMode
        }
        apiKey = (try? profileStore.getApiKey()) ?? ""
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func computeStats(from entries: [TranscriptionHistory.Entry]) -> Stats {
        let totalWords = entries.reduce(0) { $0 + $1.corrected.split(separator: " ").count }
        let totalTranscriptions = entries.count
        let avgLatency = entries.isEmpty ? 0 : entries.reduce(0) { $0 + $1.latencyMs } / entries.count
        let estimatedAudioSecs = Double(totalWords) / 2.5
        let estimatedCost = (estimatedAudioSecs / 60.0) * 0.003

        return Stats(
            totalWords: totalWords,
            totalTranscriptions: totalTranscriptions,
            averageLatencyMs: avgLatency,
            estimatedCost: estimatedCost
        )
    }

    private func computeDailyStats(from entries: [TranscriptionHistory.Entry]) -> [DailyStats] {
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var byDay: [Date: (words: Int, count: Int)] = [:]
        for entry in entries {
            guard let date = formatter.date(from: entry.timestamp) else { continue }
            let day = calendar.startOfDay(for: date)
            let words = entry.corrected.split(separator: " ").count
            let existing = byDay[day, default: (words: 0, count: 0)]
            byDay[day] = (words: existing.words + words, count: existing.count + 1)
        }

        return byDay.map { DailyStats(date: $0.key, wordCount: $0.value.words, transcriptionCount: $0.value.count) }
            .sorted { $0.date < $1.date }
    }

    private func computeHourlyStats(from entries: [TranscriptionHistory.Entry]) -> [HourlyStats] {
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var byHour: [Int: Int] = [:]
        for entry in entries {
            guard let date = formatter.date(from: entry.timestamp) else { continue }
            let hour = calendar.component(.hour, from: date)
            byHour[hour, default: 0] += 1
        }

        return (0..<24).map { HourlyStats(hour: $0, transcriptionCount: byHour[$0, default: 0]) }
    }

    func saveApiKey(_ key: String) {
        try? profileStore.setApiKey(key)
        apiKey = key
    }

    func saveSoundEnabled(_ enabled: Bool) {
        try? profileStore.setSoundEnabled(enabled)
        soundEnabled = enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLogin = enabled
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    func saveHotkeyModifiers(_ modifiers: String) {
        try? profileStore.setHotkeyModifiers(modifiers)
        hotkeyModifiers = modifiers
        NotificationCenter.default.post(
            name: .hotkeyModifiersChanged,
            object: nil,
            userInfo: ["modifiers": modifiers]
        )
    }

    func saveRecordingMode(_ mode: String) {
        try? profileStore.setRecordingMode(mode)
        recordingMode = mode
        NotificationCenter.default.post(
            name: .recordingModeChanged,
            object: nil,
            userInfo: ["mode": mode]
        )
    }

    func addVocabEntry(heard: String, intended: String) {
        try? profileStore.addVocabEntry(heard: heard, intended: intended)
        vocab[heard] = intended
    }

    func removeVocabEntry(heard: String) {
        if var profile = try? profileStore.read() {
            profile.vocab.removeValue(forKey: heard)
            try? profileStore.write(profile)
            vocab = profile.vocab
        }
    }

    func deleteEntry(timestamp: String, raw: String) {
        history.deleteEntry(timestamp: timestamp, raw: raw)
        loadData()
    }

    func deleteAllHistory() {
        history.deleteAll()
        loadData()
    }
}
