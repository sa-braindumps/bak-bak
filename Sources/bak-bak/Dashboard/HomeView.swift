import SwiftUI
import Pipeline

struct HomeView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            StatsBar(stats: viewModel.stats)
                .padding()

            Divider()

            if viewModel.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedEntries, id: \.key) { group in
                            Section {
                                ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                                    TranscriptionRow(entry: entry)
                                    Divider().padding(.leading, 90)
                                }
                            } header: {
                                Text(group.key)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 16)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No transcriptions yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Hold \u{2303}\u{2325} anywhere and start talking.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var groupedEntries: [(key: String, entries: [TranscriptionHistory.Entry])] {
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var groups: [(key: String, date: Date, entries: [TranscriptionHistory.Entry])] = []
        var currentKey: String?
        var currentDate: Date = .distantPast
        var currentEntries: [TranscriptionHistory.Entry] = []

        for entry in viewModel.entries {
            guard let date = formatter.date(from: entry.timestamp) else { continue }
            let label = dayLabel(for: date, calendar: calendar)

            if label != currentKey {
                if let key = currentKey {
                    groups.append((key: key, date: currentDate, entries: currentEntries))
                }
                currentKey = label
                currentDate = date
                currentEntries = [entry]
            } else {
                currentEntries.append(entry)
            }
        }
        if let key = currentKey {
            groups.append((key: key, date: currentDate, entries: currentEntries))
        }

        return groups.map { (key: $0.key, entries: $0.entries) }
    }

    private func dayLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: date)
    }
}

// MARK: - Stats Bar

struct StatsBar: View {
    let stats: DashboardViewModel.Stats

    var body: some View {
        HStack(spacing: 16) {
            StatCard(title: "Words", value: formatNumber(stats.totalWords), icon: "text.word.spacing")
            StatCard(title: "Transcriptions", value: "\(stats.totalTranscriptions)", icon: "waveform")
            StatCard(title: "Avg Latency", value: "\(stats.averageLatencyMs)ms", icon: "timer")
            StatCard(title: "Est. Cost", value: formatCost(stats.estimatedCost), icon: "dollarsign.circle")
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1000 {
            return String(format: "%.1fK", Double(n) / 1000)
        }
        return "\(n)"
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.2f", cost)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Transcription Row

struct TranscriptionRow: View {
    let entry: TranscriptionHistory.Entry
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(formatTime(entry.timestamp))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.corrected)
                    .font(.body)
                    .textSelection(.enabled)

                if entry.raw != entry.corrected {
                    Text("raw: \(entry.raw)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: copyToClipboard) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundColor(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func formatTime(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: timestamp) else { return "" }
        let display = DateFormatter()
        display.dateFormat = "h:mm a"
        return display.string(from: date)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.corrected, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
