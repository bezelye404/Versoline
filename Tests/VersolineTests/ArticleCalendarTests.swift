import Testing
import Foundation
@testable import Versoline

struct ArticleCalendarTests {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2   // Monday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func item(_ title: String, on date: Date?, bookmarked: Bool = false, read: Bool = false) -> FeedItem {
        FeedItem(feedId: UUID(), title: title, link: "https://example.com/\(title)", pubDate: date, isRead: read, isBookmarked: bookmarked)
    }

    @Test func summariesCountPerDayInsideTheMonthOnly() {
        let items = [
            item("a", on: date(2026, 10, 5, hour: 8)),
            item("b", on: date(2026, 10, 5, hour: 20), bookmarked: true, read: true),
            item("c", on: date(2026, 10, 7)),
            item("d", on: date(2026, 9, 30)),
            item("e", on: nil),
        ]
        let summaries = ArticleCalendar.summaries(for: items, in: date(2026, 10, 15), calendar: utc)
        #expect(summaries.count == 2)
        #expect(summaries[utc.startOfDay(for: date(2026, 10, 5))] == .init(total: 2, bookmarked: 1, unread: 1))
        #expect(summaries[utc.startOfDay(for: date(2026, 10, 7))] == .init(total: 1, bookmarked: 0, unread: 1))
    }

    @Test func dayItemsAreNewestFirstAndCanBeLimitedToBookmarks() {
        let items = [
            item("morning", on: date(2026, 10, 5, hour: 8)),
            item("evening", on: date(2026, 10, 5, hour: 20), bookmarked: true),
            item("other", on: date(2026, 10, 6)),
        ]
        let all = ArticleCalendar.items(on: date(2026, 10, 5), from: items, bookmarkedOnly: false, calendar: utc)
        #expect(all.map(\.title) == ["evening", "morning"])
        let starred = ArticleCalendar.items(on: date(2026, 10, 5), from: items, bookmarkedOnly: true, calendar: utc)
        #expect(starred.map(\.title) == ["evening"])
    }

    @Test func gridStartsOnTheFirstWeekday() {
        // 1 October 2026 is a Thursday; with Monday first there are three blanks.
        let cells = ArticleCalendar.gridDays(for: date(2026, 10, 15), calendar: utc)
        #expect(cells.prefix(3).allSatisfy { $0 == nil })
        #expect(cells[3] != nil)
        #expect(cells.count == 3 + 31)

        var sundayFirst = utc
        sundayFirst.firstWeekday = 1
        let other = ArticleCalendar.gridDays(for: date(2026, 10, 15), calendar: sundayFirst)
        #expect(other.prefix(4).allSatisfy { $0 == nil })
    }

    @Test func weekdaySymbolsFollowTheFirstWeekday() {
        let symbols = ArticleCalendar.weekdaySymbols(calendar: utc)
        #expect(symbols.count == 7)
        #expect(symbols.first == utc.veryShortStandaloneWeekdaySymbols[1])
        #expect(symbols.last == utc.veryShortStandaloneWeekdaySymbols[0])
    }

    @Test func monthNavigationCrossesYears() {
        let next = ArticleCalendar.month(date(2026, 12, 10), offsetBy: 1, calendar: utc)
        #expect(utc.component(.year, from: next) == 2027)
        #expect(utc.component(.month, from: next) == 1)
    }
}
