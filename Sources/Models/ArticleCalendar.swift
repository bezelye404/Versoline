import Foundation

/// The date arithmetic behind the calendar view, kept apart from SwiftUI so it can be tested.
enum ArticleCalendar {

    struct DaySummary: Equatable {
        var total = 0
        var bookmarked = 0
        var unread = 0
    }

    /// Per-day counts for the articles that fall inside `month`. The key is the start of the day.
    static func summaries(for items: [FeedItem], in month: Date, calendar: Calendar = .current) -> [Date: DaySummary] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [:] }
        var result: [Date: DaySummary] = [:]
        for item in items {
            guard let date = item.pubDate, interval.contains(date) else { continue }
            let day = calendar.startOfDay(for: date)
            var summary = result[day] ?? DaySummary()
            summary.total += 1
            if item.isBookmarked { summary.bookmarked += 1 }
            if !item.isRead { summary.unread += 1 }
            result[day] = summary
        }
        return result
    }

    /// The articles published on `day`, newest first. Bookmarked ones only when `bookmarkedOnly` is set.
    static func items(on day: Date, from items: [FeedItem], bookmarkedOnly: Bool, calendar: Calendar = .current) -> [FeedItem] {
        items
            .filter { item in
                guard let date = item.pubDate, calendar.isDate(date, inSameDayAs: day) else { return false }
                return !bookmarkedOnly || item.isBookmarked
            }
            .sortedNewestFirst()
    }

    /// The cells of a month grid: `nil` for the blanks before the first day, then every day of the month.
    /// The first column follows the user's first weekday.
    static func gridDays(for month: Date, calendar: Calendar = .current) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayCount = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let blanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: blanks)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        return cells
    }

    /// Weekday initials in column order, starting with the user's first weekday.
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    static func month(_ month: Date, offsetBy value: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: value, to: month) ?? month
    }
}
