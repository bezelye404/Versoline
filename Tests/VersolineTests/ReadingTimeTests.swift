import Testing
import Foundation
@testable import Versoline

@Suite("Reading Time Tests")
@MainActor
struct ReadingTimeTests {

    private func words(_ n: Int) -> String { String(repeating: "word ", count: n) }

    private func longArticleFeed() -> String {
        """
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel><title>T</title>
          <item><title>Long</title><link>https://example.com/long</link>
            <description>Short teaser</description>
            <content:encoded><![CDATA[<p>\(words(1600))</p>]]></content:encoded></item>
          <item><title>Short</title><link>https://example.com/short</link>
            <description>Just a few words here</description></item>
        </channel></rss>
        """
    }

    // MARK: - FeedItem

    @Test("Estimate is 200 words per minute, at least one, and ignores HTML tags")
    func estimate() {
        #expect(FeedItem.estimateReadingMinutes(from: "") == 1)
        #expect(FeedItem.estimateReadingMinutes(from: words(200)) == 1)
        #expect(FeedItem.estimateReadingMinutes(from: words(201)) == 2)
        #expect(FeedItem.estimateReadingMinutes(from: "<p>\(words(1400))</p><div class=\"x\"></div>") == 7)
    }

    @Test("Scan skips tags and entities, keeps apostrophes and bare angle brackets, handles non-ASCII")
    func scanEdgeCases() {
        // 200 real words wrapped in markup and entities must still be exactly one minute.
        let marked = String(repeating: "<span class=\"a\">word</span>&nbsp;", count: 200)
        #expect(FeedItem.estimateReadingMinutes(from: marked) == 1)
        let marked201 = String(repeating: "<span class=\"a\">word</span>&nbsp;", count: 201)
        #expect(FeedItem.estimateReadingMinutes(from: marked201) == 2)

        // "don\u{2019}t" is one word; a bare "<" in text is not a tag.
        #expect(FeedItem.estimateReadingMinutes(from: String(repeating: "don\u{2019}t ", count: 200)) == 1)
        #expect(FeedItem.estimateReadingMinutes(from: String(repeating: "a < b ", count: 100) + "tail") == 2)

        // Non-ASCII text counts as words; no-break spaces separate them.
        #expect(FeedItem.estimateReadingMinutes(from: String(repeating: "\u{015E}ehir\u{00A0}\u{0131}\u{015F}\u{0131}k ", count: 201)) == 3)

        // Unterminated tag or entity at the end must not crash or loop.
        #expect(FeedItem.estimateReadingMinutes(from: "text <b") == 1)
        #expect(FeedItem.estimateReadingMinutes(from: "text &amp") == 1)
        #expect(FeedItem.estimateReadingMinutes(from: "") == 1)
    }

    @Test("Stored readingMinutes wins over the snippet-based estimate")
    func storedValueWins() {
        let id = UUID()
        let plain = FeedItem(feedId: id, title: "t", link: "l", itemDescription: "tiny")
        let stored = FeedItem(feedId: id, title: "t", link: "l", itemDescription: "tiny", readingMinutes: 9)

        #expect(plain.estimatedReadingMinutes == 1)
        #expect(plain.isQuickRead && !plain.isLongRead)
        #expect(stored.estimatedReadingMinutes == 9)
        #expect(stored.isLongRead && !stored.isQuickRead)
    }

    @Test("Podcasts are neither quick nor long reads")
    func podcastsExcluded() {
        let item = FeedItem(feedId: UUID(), title: "t", link: "l", audioURL: "https://x.com/a.mp3", audioType: "audio/mpeg", readingMinutes: 10)

        #expect(!item.isQuickRead && !item.isLongRead)
    }

    @Test("readingMinutes round-trips and old data without the key still decodes")
    func codable() throws {
        let item = FeedItem(feedId: UUID(), title: "t", link: "l", readingMinutes: 8)
        let data = try JSONEncoder().encode(item)
        #expect(try JSONDecoder().decode(FeedItem.self, from: data).readingMinutes == 8)

        let legacy = Data("""
        {"id":"\(UUID().uuidString)","feedId":"\(UUID().uuidString)","title":"old","link":"l"}
        """.utf8)
        let decoded = try JSONDecoder().decode(FeedItem.self, from: legacy)
        #expect(decoded.readingMinutes == nil)
        #expect(decoded.estimatedReadingMinutes == 1)
    }

    // MARK: - Ingest

    @Test("Parser computes reading time from the full body, not the teaser")
    func parserComputes() throws {
        let result = try #require(RSSParser(feedId: UUID()).parse(data: Data(longArticleFeed().utf8)))
        let long = try #require(result.items.first { $0.title == "Long" })
        let short = try #require(result.items.first { $0.title == "Short" })

        #expect(long.readingMinutes == 8)
        #expect(long.isLongRead)
        #expect(short.readingMinutes == 1)
        #expect(short.isQuickRead)
    }

    @Test("After ingest the body is dropped but the item is still a long read, and it survives a relaunch")
    func ingestKeepsReadingTime() throws {
        let ts = try TestStore()
        defer { ts.cleanup() }
        let feed = Feed(title: "T", url: "https://example.com/feed")
        ts.store.feeds = [feed]
        let result = try #require(RSSParser(feedId: feed.id).parse(data: Data(longArticleFeed().utf8)))

        ts.store.applyFeedUpdate(feedId: feed.id, result: result)
        ts.store.updateCachedCounts()

        let stored = try #require(ts.store.items[feed.id]?.first { $0.title == "Long" })
        #expect(stored.content == nil)
        #expect(stored.isLongRead)
        #expect(ts.store.items(for: .longReads).map(\.title) == ["Long"])
        #expect(ts.store.count(for: .longReads) == 1)
        #expect(ts.store.items(for: .quickReads).map(\.title) == ["Short"])

        ts.store.save(immediate: true)
        let reopened = ts.reopen()
        #expect(reopened.items(for: .longReads).map(\.title) == ["Long"])
    }

    @Test("Refreshing an existing item fills in readingMinutes")
    func refreshUpgradesExistingItem() throws {
        let ts = try TestStore()
        defer { ts.cleanup() }
        let feed = Feed(title: "T", url: "https://example.com/feed")
        ts.store.feeds = [feed]
        // Item stored by an older version: no readingMinutes, no body.
        let old = FeedItem(feedId: feed.id, title: "Long", link: "https://example.com/long", itemDescription: "Short teaser", isRead: true)
        ts.store.items = [feed.id: [old]]
        let result = try #require(RSSParser(feedId: feed.id).parse(data: Data(longArticleFeed().utf8)))

        ts.store.applyFeedUpdate(feedId: feed.id, result: result)

        let updated = try #require(ts.store.items[feed.id]?.first { $0.link == "https://example.com/long" })
        #expect(updated.id == old.id)
        #expect(updated.isRead)
        #expect(updated.readingMinutes == 8)
    }

    @Test("Legacy databases that still embed the body get readingMinutes on load")
    func legacyLoadBackfills() throws {
        let feed = Feed(title: "T", url: "https://example.com/feed")
        let legacyItem = FeedItem(feedId: feed.id, title: "Legacy long", link: "https://example.com/legacy",
                                  itemDescription: "teaser", content: "<p>\(words(1600))</p>")
        let storage = FeedStore.StorageData(feeds: [feed], items: [feed.id: [legacyItem]], folders: [])
        let ts = try TestStore { dir in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(storage).write(to: dir.appendingPathComponent("data.json"))
        }
        defer { ts.cleanup() }

        let loaded = try #require(ts.store.items[feed.id]?.first)

        #expect(loaded.content == nil)
        #expect(loaded.readingMinutes == 8)
        #expect(ts.store.items(for: .longReads).map(\.title) == ["Legacy long"])
    }
}
