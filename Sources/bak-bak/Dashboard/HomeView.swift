import SwiftUI
import Pipeline

struct HomeView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showClearAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.xl)
                .padding(.bottom, AppSpacing.md)

            StatsBar(stats: viewModel.stats)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.lg)

            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 1)

            if viewModel.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedEntries, id: \.key) { group in
                            Section {
                                ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                                    TranscriptionRow(entry: entry) {
                                        viewModel.deleteEntry(timestamp: entry.timestamp, raw: entry.raw)
                                    }
                                }
                            } header: {
                                dayHeader(group.key)
                            }
                        }
                    }
                    .padding(.bottom, AppSpacing.xxl)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .alert("Clear All History", isPresented: $showClearAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                viewModel.deleteAllHistory()
            }
        } message: {
            Text("This will permanently delete all \(viewModel.entries.count) transcriptions. This cannot be undone.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("History")
                    .font(.appLargeTitle)
                    .foregroundColor(AppColors.textPrimary)
                Text("\(viewModel.entries.count) transcriptions")
                    .font(.appCaption)
                    .foregroundColor(AppColors.textMuted)
            }

            Spacer()

            if !viewModel.entries.isEmpty {
                Button(action: { showClearAllConfirm = true }) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                        Text("Clear All")
                            .font(.appCaptionBold)
                    }
                    .foregroundColor(AppColors.deleteRed)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.deleteRed.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                            .stroke(AppColors.deleteRed.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help("Delete all transcription history")
            }
        }
    }

    // MARK: - Day Header

    private func dayHeader(_ text: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Text(text)
                .font(.appSectionTitle)
                .foregroundColor(AppColors.textMuted)
                .tracking(0.3)
            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 0.5)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.sm)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "mic")
                .font(.appEmptyIcon)
                .foregroundColor(AppColors.textMuted)
            VStack(spacing: AppSpacing.xs) {
                Text("No transcriptions yet")
                    .font(.appTitle)
                    .foregroundColor(AppColors.textSecondary)
                Text("Hold \u{2303}\u{2325} anywhere and start talking.")
                    .font(.appCaption)
                    .foregroundColor(AppColors.textMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grouping

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
        HStack(spacing: AppSpacing.md) {
            StatCard(title: "Words", value: formatNumber(stats.totalWords))
            StatCard(title: "Transcriptions", value: "\(stats.totalTranscriptions)")
            StatCard(title: "Avg Latency", value: "\(stats.averageLatencyMs)ms")
            StatCard(title: "Est. Cost", value: formatCost(stats.estimatedCost))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.appStatLabel)
                .foregroundColor(AppColors.textMuted)
                .tracking(0.3)

            Text(value)
                .font(.appStatValue)
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.md)
        .background(AppColors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.cardBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Transcription Row

struct TranscriptionRow: View {
    let entry: TranscriptionHistory.Entry
    var onDelete: (() -> Void)?
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            timelineSection
            contentSection
            Spacer()
            copyButton
        }
        .padding(.horizontal, AppSpacing.xl - AppSpacing.sm)
        .padding(.vertical, AppSpacing.md - 2)
        .rowHover()
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .padding(.horizontal, AppSpacing.sm)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: { onDelete?() }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(spacing: 0) {
            TimelineDot()
            TimelineConnector()
        }
        .frame(width: 20)
        .padding(.trailing, AppSpacing.md)
        .padding(.top, 5)
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs + 2) {
            HStack(spacing: AppSpacing.sm) {
                Text(formatTime(entry.timestamp))
                    .font(.appMonospaced)
                    .foregroundColor(AppColors.textMuted)

                if entry.raw != entry.corrected {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .medium))
                        Text("corrected")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal, AppSpacing.xs + 1)
                    .padding(.vertical, 2)
                    .background(AppColors.accentDim)
                    .clipShape(Capsule())
                }
            }

            Text(entry.corrected)
                .font(.appBody)
                .foregroundColor(AppColors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if entry.raw != entry.corrected {
                HStack(spacing: AppSpacing.xs) {
                    Text("raw:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.textMuted)
                    Text(entry.raw)
                        .font(.appCaption)
                        .foregroundColor(AppColors.textMuted)
                        .italic()
                        .lineLimit(2)
                }
            }
        }
        .padding(.leading, AppSpacing.xs)
    }

    // MARK: - Copy Button

    private var copyButton: some View {
        Button(action: copyToClipboard) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(copied ? AppColors.successGreen.opacity(0.12) : Color.clear)
                    .frame(width: 30, height: 30)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(copied ? AppColors.successGreen : AppColors.textMuted)
            }
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
        .padding(.top, 2)
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
