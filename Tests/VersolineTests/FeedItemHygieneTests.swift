import Testing
import Foundation
@testable import Versoline

@Suite("Feed Item Hygiene Tests")
@MainActor
struct FeedItemHygieneTests {

    private func item(_ title: String, _ link: String, audio: String? = nil) -> FeedItem {
        FeedItem(feedId: UUID(), title: title, link: link, audioURL: audio, audioType: audio == nil ? nil : "audio/mpeg")
    }

    // MARK: - Link resolution

    @Test("A web link wins; otherwise a web guid; otherwise the audio file; otherwise nothing")
    func resolvedLink() {
        #expect(FeedItemHygiene.resolvedLink(link: "https://a.com/x", guid: "https://b.com/y", enclosureURL: "https://c.com/z.mp3") == "https://a.com/x")
        #expect(FeedItemHygiene.resolvedLink(link: "", guid: "https://b.com/y", enclosureURL: "https://c.com/z.mp3") == "https://b.com/y")
        #expect(FeedItemHygiene.resolvedLink(link: "  ", guid: "urn:uuid:123", enclosureURL: "https://c.com/z.mp3") == "https://c.com/z.mp3")
        #expect(FeedItemHygiene.resolvedLink(link: "", guid: "abc-123", enclosureURL: nil) == nil)
        #expect(FeedItemHygiene.resolvedLink(link: "javascript:void(0)", guid: "", enclosureURL: nil) == nil)
    }

    // MARK: - Non-articles

    @Test("Home pages, social promos and store links are not articles")
    func nonArticles() {
        #expect(FeedItemHygiene.isNotAnArticle(title: "Haberler", link: "https://news.example.com/", hasEnclosure: false, feedHost: "news.example.com"))
        #expect(FeedItemHygiene.isNotAnArticle(title: "Abone olmak için tıklayın", link: "https://www.whatsapp.com/channel/0029Vb5e", hasEnclosure: false, feedHost: "feeds.bbci.co.uk"))
        #expect(FeedItemHygiene.isNotAnArticle(title: "Get the app", link: "https://apps.apple.com/app/id1", hasEnclosure: false, feedHost: "news.example.com"))
        #expect(FeedItemHygiene.isNotAnArticle(title: "Bizi takip edin", link: "https://news.example.com/takip", hasEnclosure: false, feedHost: "news.example.com"))
        #expect(FeedItemHygiene.isNotAnArticle(title: "x", link: "not a url", hasEnclosure: false, feedHost: nil))
    }

    @Test("Real articles, deep links and podcast episodes are kept")
    func articlesKept() {
        #expect(!FeedItemHygiene.isNotAnArticle(title: "Real story", link: "https://news.example.com/world/2026/story-title", hasEnclosure: false, feedHost: "news.example.com"))
        // A feed hosted on a social site may link to that site.
        #expect(!FeedItemHygiene.isNotAnArticle(title: "Post", link: "https://www.facebook.com/page/posts/123", hasEnclosure: false, feedHost: "facebook.com"))
        // Podcast episode pointing at the show's home page is still an episode.
        #expect(!FeedItemHygiene.isNotAnArticle(title: "Episode 1", link: "https://show.example.com/", hasEnclosure: true, feedHost: "feeds.example.org"))
        // A legitimate article that merely contains the word in a deep URL is kept.
        #expect(!FeedItemHygiene.isNotAnArticle(title: "Takip edin: 10 ipucu", link: "https://news.example.com/yasam/takip-edin-10-ipucu", hasEnclosure: false, feedHost: "news.example.com"))
    }

    // MARK: - Duplicates

    @Test("The same article under different tracking parameters, fragments and trailing slashes is kept once")
    func deduplication() {
        let items = [
            item("A", "https://news.example.com/a/story?utm_source=x&id=7"),
            item("A again", "https://NEWS.example.com/a/story/?id=7&utm_campaign=y#comments"),
            item("B", "https://news.example.com/b/story"),
        ]

        let cleaned = FeedItemHygiene.clean(items, feedHost: "news.example.com")

        #expect(cleaned.map(\.title) == ["A", "B"])
    }

    @Test("Different query values are different articles")
    func differentQueryIsDifferentArticle() {
        let items = [item("One", "https://example.com/read?id=1"), item("Two", "https://example.com/read?id=2")]

        #expect(FeedItemHygiene.clean(items, feedHost: nil).count == 2)
    }

    @Test("Order is preserved and podcast episodes with distinct audio files all survive")
    func podcastsSurvive() {
        let items = (0..<5).map { item("Ep \($0)", "https://cdn.example.com/ep\($0).mp3", audio: "https://cdn.example.com/ep\($0).mp3") }

        #expect(FeedItemHygiene.clean(items, feedHost: "feeds.example.com").map(\.title) == (0..<5).map { "Ep \($0)" })
    }

    // MARK: - Through the parser

    @Test("Podcast items without a link get their own identity from the audio file")
    func parserFallsBackToEnclosure() throws {
        let xml = """
        <rss version="2.0"><channel><title>Pod</title>
          <item><title>Ep 1</title><enclosure url="https://cdn.example.com/1.mp3" type="audio/mpeg" length="1"/><guid isPermaLink="false">a-1</guid></item>
          <item><title>Ep 2</title><enclosure url="https://cdn.example.com/2.mp3" type="audio/mpeg" length="1"/><guid isPermaLink="false">a-2</guid></item>
        </channel></rss>
        """
        let result = try #require(RSSParser(feedId: UUID(), feedURL: URL(string: "https://feeds.example.com/rss")).parse(data: Data(xml.utf8)))

        #expect(result.items.map(\.link) == ["https://cdn.example.com/1.mp3", "https://cdn.example.com/2.mp3"])
        #expect(Set(result.items.map(\.link)).count == 2)
    }

    @Test("A web guid is used when the link is missing; an entry with neither is dropped")
    func parserGuidAndDrop() throws {
        let xml = """
        <rss version="2.0"><channel><title>T</title>
          <item><title>Has guid</title><guid>https://example.com/p/1</guid></item>
          <item><title>Nothing</title><guid isPermaLink="false">opaque</guid></item>
        </channel></rss>
        """
        let result = try #require(RSSParser(feedId: UUID()).parse(data: Data(xml.utf8)))

        #expect(result.items.map(\.title) == ["Has guid"])
        #expect(result.items.first?.link == "https://example.com/p/1")
    }

    @Test("The parser removes duplicates and promos from a news feed")
    func parserCleansNewsFeed() throws {
        let xml = """
        <rss version="2.0"><channel><title>News</title>
          <item><title>Story</title><link>https://news.example.com/world/story-1</link></item>
          <item><title>Story</title><link>https://news.example.com/world/story-1?utm_source=rss</link></item>
          <item><title>Abone olmak için tıklayın</title><link>https://www.whatsapp.com/channel/abc</link></item>
          <item><title>Front page</title><link>https://news.example.com/</link></item>
          <item><title>Another</title><link>https://news.example.com/world/story-2</link></item>
        </channel></rss>
        """
        let result = try #require(RSSParser(feedId: UUID(), feedURL: URL(string: "https://news.example.com/rss")).parse(data: Data(xml.utf8)))

        #expect(result.items.map(\.title) == ["Story", "Another"])
    }

    // MARK: - Stored items without a link

    @Test("Items stored without a link get distinct identities on load, so one read state no longer covers all")
    func loadRepairsEmptyLinks() throws {
        let feed = Feed(title: "Pod", url: "https://feeds.example.com/rss")
        let a = FeedItem(feedId: feed.id, title: "A", link: "", audioURL: "https://cdn.example.com/a.mp3", audioType: "audio/mpeg")
        let b = FeedItem(feedId: feed.id, title: "B", link: "", audioURL: "https://cdn.example.com/b.mp3", audioType: "audio/mpeg")
        let storage = FeedStore.StorageData(feeds: [feed], items: [feed.id: [a, b]], folders: [])
        let ts = try TestStore { dir in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(storage).write(to: dir.appendingPathComponent("data.json"))
        }
        defer { ts.cleanup() }

        let links = try #require(ts.store.items[feed.id]).map(\.link)

        #expect(Set(links).count == 2)
        #expect(!links.contains(""))
    }
}
