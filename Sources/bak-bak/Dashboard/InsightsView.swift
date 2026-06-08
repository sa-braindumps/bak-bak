import SwiftUI

struct InsightsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                Text("Insights")
                    .font(.appLargeTitle)
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.xl)

                if viewModel.entries.isEmpty {
                    emptyState
                } else {
                    summaryCards
                    dailyWordsSection
                    peakHoursSection
                }
            }
            .padding(.bottom, AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.background)
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: AppSpacing.md) {
            summaryCard(title: "Busiest Day", value: busiestDay)
            summaryCard(title: "Peak Hour", value: peakHour)
            summaryCard(title: "Best Streak", value: longestStreak > 0 ? "\(longestStreak) days" : "—")
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.appStatLabel)
                .foregroundColor(AppColors.textMuted)
                .tracking(0.3)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
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

    // MARK: - Daily Words Chart

    private var dailyWordsSection: some View {
        let maxWords = max(1, viewModel.dailyStats.map(\.wordCount).max() ?? 1)
        let recentDays = Array(viewModel.dailyStats.suffix(14))
        let chartHeight: CGFloat = 140

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("WORDS PER DAY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.textMuted)
                    .tracking(0.8)
                Spacer()
                Text("Last \(recentDays.count) days")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textMuted)
            }

            VStack(spacing: 3) {
                // Bar area
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(recentDays) { day in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(day.wordCount > 0 ? AppColors.accent.opacity(0.75) : AppColors.barGhost)
                                .frame(maxWidth: 32)
                                .frame(height: max(3, CGFloat(day.wordCount) / CGFloat(maxWords) * chartHeight))
                            Text(dayAbbrev(day.date))
                                .font(.system(size: 9))
                                .foregroundColor(AppColors.textMuted)
                                .frame(height: 12)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: chartHeight + 15, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(AppColors.divider.opacity(0.7))
                            .frame(maxWidth: .infinity, maxHeight: 0.5)
                        Spacer()
                    }
                    .frame(height: chartHeight)
                    .allowsHitTesting(false)
                }

                // Baseline
                Rectangle()
                    .fill(AppColors.dividerStrong)
                    .frame(maxWidth: .infinity, maxHeight: 0.5)
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.cardBorder, lineWidth: 0.5)
        )
        .padding(.horizontal, AppSpacing.xl)
    }

    // MARK: - Peak Hours Chart

    private var peakHoursSection: some View {
        let maxCount = max(1, viewModel.hourlyStats.map(\.transcriptionCount).max() ?? 1)
        let chartHeight: CGFloat = 120

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("ACTIVITY BY HOUR")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.textMuted)
                    .tracking(0.8)
                Spacer()
                Text("All time")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textMuted)
            }

            VStack(spacing: 3) {
                // Bar area
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(viewModel.hourlyStats) { hour in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(hourBarColor(for: hour.transcriptionCount, max: maxCount))
                                .frame(maxWidth: 20)
                                .frame(height: max(2, CGFloat(hour.transcriptionCount) / CGFloat(maxCount) * chartHeight))
                            Text(hour.hour % 6 == 0 ? hourLabel(hour.hour) : "")
                                .font(.system(size: 9))
                                .foregroundColor(AppColors.textMuted)
                                .frame(height: 12)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: chartHeight + 15, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(AppColors.divider.opacity(0.7))
                            .frame(maxWidth: .infinity, maxHeight: 0.5)
                        Spacer()
                    }
                    .frame(height: chartHeight)
                    .allowsHitTesting(false)
                }

                // Baseline
                Rectangle()
                    .fill(AppColors.dividerStrong)
                    .frame(maxWidth: .infinity, maxHeight: 0.5)
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.cardBorder, lineWidth: 0.5)
        )
        .padding(.horizontal, AppSpacing.xl)
    }

    // MARK: - Helpers

    private var busiestDay: String {
        guard let busiest = viewModel.dailyStats.max(by: { $0.wordCount < $1.wordCount }) else {
            return "—"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: busiest.date)
    }

    private var peakHour: String {
        guard let peak = viewModel.hourlyStats.max(by: { $0.transcriptionCount < $1.transcriptionCount }),
              peak.transcriptionCount > 0 else {
            return "—"
        }
        return hourLabel(peak.hour)
    }

    private var longestStreak: Int {
        let calendar = Calendar.current
        let days = Set(viewModel.dailyStats.map { calendar.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return 0 }

        let sorted = days.sorted()
        var streak = 1
        var maxStreak = 1

        for i in 1..<sorted.count {
            if calendar.date(byAdding: .day, value: 1, to: sorted[i - 1]) == sorted[i] {
                streak += 1
                maxStreak = max(maxStreak, streak)
            } else {
                streak = 1
            }
        }
        return maxStreak
    }

    private func dayAbbrev(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "E"
        return String(fmt.string(from: date).prefix(1))
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12a" }
        if hour == 12 { return "12p" }
        if hour < 12 { return "\(hour)a" }
        return "\(hour - 12)p"
    }

    private func hourBarColor(for count: Int, max: Int) -> Color {
        guard count > 0, max > 0 else { return AppColors.barGhost }
        let intensity = Double(count) / Double(max)
        return AppColors.accent.opacity(0.20 + 0.68 * intensity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "chart.bar")
                .font(.appEmptyIcon)
                .foregroundColor(AppColors.textMuted)
            VStack(spacing: AppSpacing.xs) {
                Text("Not enough data yet")
                    .font(.appTitle)
                    .foregroundColor(AppColors.textSecondary)
                Text("Insights will appear after you start dictating.")
                    .font(.appCaption)
                    .foregroundColor(AppColors.textMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
