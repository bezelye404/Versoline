import SwiftUI

/// A month grid showing how many articles arrived on each day, with the selected day's articles below it.
struct CalendarView: View {

    @Environment(FeedStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Binding var selectedArticle: FeedItem?

    @State private var month = Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var bookmarksOnly = false

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let everything = store.allItems()
        let summaries = ArticleCalendar.summaries(for: everything, in: month, calendar: calendar)
        let dayItems = ArticleCalendar.items(on: selectedDay, from: everything, bookmarkedOnly: bookmarksOnly, calendar: calendar)

        VStack(spacing: 0) {
            monthHeader
            weekdayRow
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(ArticleCalendar.gridDays(for: month, calendar: calendar).enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, summary: summaries[calendar.startOfDay(for: day)])
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()
            dayHeader(count: dayItems.count)
            dayList(dayItems)
        }
        .background(theme.listBackground)
    }

    // MARK: Month

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Text(month, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button(String(localized: "Today")) {
                month = Date()
                selectedDay = calendar.startOfDay(for: Date())
            }
            .controlSize(.small)
            Button {
                month = ArticleCalendar.month(month, offsetBy: -1, calendar: calendar)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help(String(localized: "Previous Month"))
            .accessibilityLabel(String(localized: "Previous Month"))
            Button {
                month = ArticleCalendar.month(month, offsetBy: 1, calendar: calendar)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help(String(localized: "Next Month"))
            .accessibilityLabel(String(localized: "Next Month"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(ArticleCalendar.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    private func dayCell(_ day: Date, summary: ArticleCalendar.DaySummary?) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        return Button {
            selectedDay = calendar.startOfDay(for: day)
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? theme.activeBadgeText : (summary == nil ? Color.secondary : Color.primary))
                HStack(spacing: 2) {
                    if let summary {
                        Circle()
                            .fill(isSelected ? theme.activeBadgeText : theme.accentColor)
                            .opacity(dotOpacity(summary.total))
                            .frame(width: 5, height: 5)
                        if summary.bookmarked > 0 {
                            Circle()
                                .fill(theme.bookmarkColor)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isSelected ? theme.activeBadgeBackground : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 8).stroke(theme.accentColor.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: day, summary: summary))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Busier days get a stronger dot; the scale tops out at 20 articles.
    private func dotOpacity(_ total: Int) -> Double {
        0.35 + 0.65 * min(Double(total) / 20, 1)
    }

    private func accessibilityLabel(for day: Date, summary: ArticleCalendar.DaySummary?) -> String {
        let name = day.formatted(date: .complete, time: .omitted)
        guard let summary else { return name }
        return String(format: String(localized: "%@, %d articles, %d bookmarked"), name, summary.total, summary.bookmarked)
    }

    // MARK: Selected day

    private func dayHeader(count: Int) -> some View {
        HStack(spacing: 10) {
            Text(selectedDay, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline.weight(.semibold))
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $bookmarksOnly) {
                Text("All").tag(false)
                Text("Bookmarks").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func dayList(_ items: [FeedItem]) -> some View {
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: bookmarksOnly ? "star" : "tray")
                    .font(.system(size: 30, weight: .ultraLight))
                    .foregroundStyle(.quaternary)
                Text(bookmarksOnly ? String(localized: "No bookmarks on this day") : String(localized: "No articles on this day"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: Binding<UUID?>(
                get: { selectedArticle?.id },
                set: { newId in selectedArticle = items.first(where: { $0.id == newId }) }
            )) {
                ForEach(items) { item in
                    let feed = store.feed(for: item.feedId)
                    FeedItemRow(
                        item: item,
                        isSelected: selectedArticle?.id == item.id,
                        feedTitle: feed?.title,
                        feedURL: feed?.url ?? URL(string: item.link)?.host,
                        feedImageURL: feed?.imageURL
                    )
                    .tag(item.id)
                    .listRowBackground(EmptyView())
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowSeparator(.hidden)
                    .contextMenu {
                        Button {
                            store.toggleReadStatus(item)
                        } label: {
                            Label(
                                item.isRead ? String(localized: "Mark as Unread") : String(localized: "Mark as Read"),
                                systemImage: item.isRead ? "circle" : "checkmark.circle"
                            )
                        }
                        Button {
                            store.toggleBookmark(item)
                        } label: {
                            Label(
                                item.isBookmarked ? String(localized: "Remove Bookmark") : String(localized: "Add Bookmark"),
                                systemImage: item.isBookmarked ? "star.fill" : "star"
                            )
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}
