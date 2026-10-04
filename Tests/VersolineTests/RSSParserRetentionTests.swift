import Testing
import Foundation
@testable import Versoline

struct RSSParserRetentionTests {

    private func feed(count: Int, oldestFirst: Bool = false, dated: Bool = true) -> Data {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let numbers = oldestFirst ? Array(0..<count) : Array((0..<count).reversed())   // n = age rank: higher is newer
        let items = numbers.map { n -> String in
            let date = dated ? "<pubDate>\(formatter.string(from: base.addingTimeInterval(Double(n) * 60)))</pubDate>" : ""
            return "<item><title>Story \(n)</title><link>https://news.example.com/story-\(n)</link>\(date)</item>"
        }.joined()
        return Data("<rss version=\"2.0\"><channel><title>T</title>\(items)</channel></rss>".utf8)
    }

    private func titles(_ result: RSSParser.ParseResult) -> [String] { result.items.map(\.title) }

    @Test func unboundedParserKeepsEverything() throws {
        let result = try #require(RSSParser(feedId: UUID()).parse(data: feed(count: 300)))
        #expect(result.items.count == 300)
    }

    @Test func newestFirstFeedKeepsTheNewest() throws {
        let result = try #require(RSSParser(feedId: UUID(), retainItems: 100).parse(data: feed(count: 500)))
        #expect(result.items.count == 100)
        #expect(Set(titles(result)) == Set((400..<500).map { "Story \($0)" }))
    }

    @Test func oldestFirstFeedStillKeepsTheNewest() throws {
        let result = try #require(RSSParser(feedId: UUID(), retainItems: 100).parse(data: feed(count: 500, oldestFirst: true)))
        #expect(result.items.count == 100)
        #expect(Set(titles(result)) == Set((400..<500).map { "Story \($0)" }))
    }

    @Test func undatedItemsKeepTheirFeedOrder() throws {
        // Without dates the first items of the feed count as the newest.
        let result = try #require(RSSParser(feedId: UUID(), retainItems: 50).parse(data: feed(count: 400, dated: false)))
        #expect(result.items.count == 50)
        #expect(Set(titles(result)) == Set((350..<400).reversed().prefix(50).map { "Story \($0)" }))
    }

    @Test func smallFeedsAreUntouched() throws {
        let result = try #require(RSSParser(feedId: UUID(), retainItems: 100).parse(data: feed(count: 12)))
        #expect(result.items.count == 12)
    }

    @Test func memoryStaysBoundedWhileParsing() throws {
        // 3,000 items would be megabytes of FeedItems; the parser never holds more than twice the limit.
        let result = try #require(RSSParser(feedId: UUID(), retainItems: 100).parse(data: feed(count: 3000)))
        #expect(result.items.count == 100)
        #expect(titles(result).contains("Story 2999"))
    }

    @Test func sortedFeedsStopEarly() throws {
        // Newest first for 250 items, then (impossible in a real feed) a far newer item. Parsing stops after twice
        // the limit, so the later item is never seen; that is how the saving shows.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var xml = "<rss version=\"2.0\"><channel><title>T</title>"
        for n in 0..<250 {
            xml += "<item><title>Story \(n)</title><link>https://news.example.com/s-\(n)</link><pubDate>\(formatter.string(from: base.addingTimeInterval(Double(-n) * 3600)))</pubDate></item>"
        }
        xml += "<item><title>LATE</title><link>https://news.example.com/late</link><pubDate>\(formatter.string(from: base.addingTimeInterval(86_400)))</pubDate></item></channel></rss>"
        let result = try #require(RSSParser(feedId: UUID(), retainItems: 50).parse(data: Data(xml.utf8)))
        #expect(result.items.count == 50)
        #expect(!titles(result).contains("LATE"))
        #expect(titles(result).first == "Story 0")
        #expect(result.title == "T")
    }

    @Test func feedsThatStartWithAnOlderItemAreParsedToTheEnd() throws {
        // A pinned old item first: the order is not newest first, so nothing may be skipped.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var xml = "<rss version=\"2.0\"><channel><title>T</title>"
        xml += "<item><title>Pinned</title><link>https://news.example.com/pinned</link><pubDate>\(formatter.string(from: base.addingTimeInterval(-9_000_000)))</pubDate></item>"
        for n in 0..<250 {
            xml += "<item><title>Story \(n)</title><link>https://news.example.com/s-\(n)</link><pubDate>\(formatter.string(from: base.addingTimeInterval(Double(-n) * 3600)))</pubDate></item>"
        }
        xml += "<item><title>LATE</title><link>https://news.example.com/late</link><pubDate>\(formatter.string(from: base.addingTimeInterval(86_400)))</pubDate></item></channel></rss>"
        let result = try #require(RSSParser(feedId: UUID(), retainItems: 50).parse(data: Data(xml.utf8)))
        #expect(titles(result).first == "LATE")
    }
}
