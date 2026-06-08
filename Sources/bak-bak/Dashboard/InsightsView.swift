import SwiftUI

struct InsightsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Insights")
                    .font(.title2)
                    .fontWeight(.semibold)

                if viewModel.entries.isEmpty {
                    emptyState
                } else {
                    dailyWordsSection
                    peakHoursSection
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Not enough data yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Insights will appear after you start dictating.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Daily Words

    private var dailyWordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Words per Day")
                .font(.headline)

            let maxWords = viewModel.dailyStats.map(\.wordCount).max() ?? 1
            let recentDays = viewModel.dailyStats.suffix(14)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(recentDays)) { day in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(0.8))
                            .frame(width: 28, height: max(4, CGFloat(day.wordCount) / CGFloat(maxWords) * 120))

                        Text(dayAbbrev(day.date))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 150, alignment: .bottom)
            .padding(.vertical, 8)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Peak Hours

    private var peakHoursSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Peak Dictation Hours")
                .font(.headline)

            let maxCount = viewModel.hourlyStats.map(\.transcriptionCount).max() ?? 1

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(viewModel.hourlyStats) { hour in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(for: hour.transcriptionCount, max: maxCount))
                            .frame(width: 16, height: max(2, CGFloat(hour.transcriptionCount) / CGFloat(maxCount) * 80))

                        if hour.hour % 6 == 0 {
                            Text(hourLabel(hour.hour))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(height: 110, alignment: .bottom)
            .padding(.vertical, 8)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func dayAbbrev(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "E"
        return fmt.string(from: date)
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12a" }
        if hour == 12 { return "12p" }
        if hour < 12 { return "\(hour)a" }
        return "\(hour - 12)p"
    }

    private func barColor(for count: Int, max: Int) -> Color {
        if count == 0 { return Color.secondary.opacity(0.2) }
        let intensity = Double(count) / Double(max)
        return Color.accentColor.opacity(0.3 + 0.7 * intensity)
    }
}
