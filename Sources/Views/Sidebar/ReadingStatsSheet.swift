import SwiftUI
import Charts

struct ReadingStatsSheet: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettingsKeys.appColorPalette) private var appColorPaletteRaw = AppColorPalette.slate.rawValue

    private var palette: AppColorPalette {
        AppColorPalette(rawValue: appColorPaletteRaw) ?? .slate
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Reading Insights"))
                        .font(.title3.bold())
                    Text(String(localized: "Your weekly reading activity and flow"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // Stat Cards Row
            HStack(spacing: 12) {
                statCard(
                    title: String(localized: "Total Read"),
                    value: "\(store.totalReadCount())",
                    icon: "checkmark.circle",
                    accent: palette.accentColor
                )
                statCard(
                    title: String(localized: "Consistency"),
                    value: "\(store.readingStreakDays()) days",
                    icon: "flame",
                    accent: palette.bookmarkColor
                )
                statCard(
                    title: String(localized: "Total Feeds"),
                    value: "\(store.feeds.count)",
                    icon: "newspaper",
                    accent: palette.accentColor
                )
            }
            .padding(.horizontal, 24)

            // Chart Section
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Articles Read (Last 7 Days)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                let history = store.weeklyReadHistory()

                Chart(history) { stat in
                    BarMark(
                        x: .value("Day", stat.day),
                        y: .value("Articles", stat.count)
                    )
                    .foregroundStyle(palette.accentColor)
                    .cornerRadius(4)
                }
                .frame(height: 150)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.hairlineBorder, lineWidth: 1))
            .padding(.horizontal, 24)

            Spacer(minLength: 4)
        }
        .frame(width: 480, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func statCard(title: String, value: String, icon: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(accent)
                    .font(.caption)
                Spacer()
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.hairlineBorder, lineWidth: 1))
    }
}
