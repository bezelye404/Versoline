import Testing
import Foundation
@testable import Versoline

@Suite("RSSParser Tests")
struct RSSParserTests {

    private let feedId = UUID()

    private func parse(_ xml: String) -> RSSParser.ParseResult? {
        RSSParser(feedId: feedId).parse(data: Data(xml.utf8))
    }

    @Test("Parses an RSS 2.0 feed with channel metadata and items")
    func rss2() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title>Example Blog</title>
          <description>Posts about things</description>
          <item>
            <title>First Post</title>
            <link>https://example.com/1</link>
            <description>Hello world</description>
            <pubDate>Sat, 06 Sep 2026 10:30:00 +0000</pubDate>
          </item>
          <item>
            <title>Second Post</title>
            <link>https://example.com/2</link>
          </item>
        </channel></rss>
        """
        let result = try #require(parse(xml))

        #expect(result.title == "Example Blog")
        #expect(result.description == "Posts about things")
        #expect(result.items.count == 2)
        #expect(result.items[0].title == "First Post")
        #expect(result.items[0].link == "https://example.com/1")
        #expect(result.items[0].feedId == feedId)
        #expect(result.items[0].pubDate != nil)
        #expect(result.items[1].pubDate == nil)
    }

    @Test("Parses an Atom feed using link href and entry elements")
    func atom() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Feed</title>
          <entry>
            <title>Entry One</title>
            <link rel="alternate" href="https://example.com/a1"/>
            <updated>2026-09-06T10:30:00Z</updated>
          </entry>
        </feed>
        """
        let result = try #require(parse(xml))

        #expect(result.title == "Atom Feed")
        #expect(result.items.count == 1)
        #expect(result.items[0].title == "Entry One")
        #expect(result.items[0].link == "https://example.com/a1")
    }

    @Test("Detects audio enclosures as podcast episodes")
    func podcastEnclosure() throws {
        let xml = """
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
          <title>Pod</title>
          <item>
            <title>Episode 1</title>
            <link>https://example.com/ep1</link>
            <enclosure url="https://cdn.example.com/ep1.mp3" type="audio/mpeg" length="12345"/>
            <itunes:duration>2712</itunes:duration>
          </item>
        </channel></rss>
        """
        let item = try #require(parse(xml)?.items.first)

        #expect(item.audioURL == "https://cdn.example.com/ep1.mp3")
        #expect(item.audioLength == 12345)
        #expect(item.isPodcast)
        #expect(item.audioDuration == "2712")
    }

    @Test("Ignores image enclosures instead of treating them as audio")
    func imageEnclosureIsNotAudio() throws {
        let xml = """
        <rss version="2.0"><channel><title>T</title>
          <item>
            <title>Post</title>
            <link>https://example.com/p</link>
            <enclosure url="https://example.com/cover.jpg" type="image/jpeg" length="10"/>
          </item>
        </channel></rss>
        """
        let item = try #require(parse(xml)?.items.first)

        #expect(item.audioURL == nil)
        #expect(!item.isPodcast)
    }

    @Test("Handles CDATA and HTML entities in titles")
    func cdataAndEntities() throws {
        let xml = """
        <rss version="2.0"><channel><title>T</title>
          <item>
            <title><![CDATA[Fish &amp; Chips]]></title>
            <link>https://example.com/f</link>
            <description><![CDATA[<p>Some <b>bold</b> text</p>]]></description>
          </item>
        </channel></rss>
        """
        let item = try #require(parse(xml)?.items.first)

        #expect(item.title == "Fish & Chips")
        #expect(!item.itemDescription.contains("<"))
        #expect(item.itemDescription.contains("bold"))
    }

    @Test("Falls back to the link when an item has no title")
    func missingTitleUsesLink() throws {
        let xml = """
        <rss version="2.0"><channel><title>T</title>
          <item><link>https://example.com/untitled</link></item>
        </channel></rss>
        """
        let item = try #require(parse(xml)?.items.first)

        #expect(item.title == "https://example.com/untitled")
    }

    @Test("Truncates long snippets to 180 characters")
    func snippetTruncation() throws {
        let long = String(repeating: "word ", count: 200)
        let xml = """
        <rss version="2.0"><channel><title>T</title>
          <item><title>Long</title><link>https://example.com/l</link>
          <description>\(long)</description></item>
        </channel></rss>
        """
        let item = try #require(parse(xml)?.items.first)

        #expect(item.itemDescription.count <= 180)
    }

    @Test("Returns nil for malformed XML")
    func malformedXML() {
        #expect(parse("<rss><channel><title>Broken") == nil)
        #expect(parse("not xml at all") == nil)
    }

    @Test("Parses ISO 8601 and RFC 822 dates to the same instant")
    func dateFormats() throws {
        let xml = """
        <rss version="2.0"><channel><title>T</title>
          <item><title>A</title><link>https://example.com/a</link>
            <pubDate>Sat, 06 Sep 2026 10:30:00 +0000</pubDate></item>
          <item><title>B</title><link>https://example.com/b</link>
            <pubDate>2026-09-06T10:30:00Z</pubDate></item>
        </channel></rss>
        """
        let items = try #require(parse(xml)?.items)
        let a = try #require(items[0].pubDate)
        let b = try #require(items[1].pubDate)

        #expect(a == b)
    }

    @Test("Decodes ISO-8859-1 feeds declared in the XML prolog")
    func latin1Encoding() throws {
        let xml = """
        <?xml version="1.0" encoding="ISO-8859-1"?>
        <rss version="2.0"><channel><title>Caf\u{E9} Blog</title>
          <item><title>Cr\u{E8}me br\u{FB}l\u{E9}e</title><link>https://example.com/c</link></item>
        </channel></rss>
        """
        let data = try #require(xml.data(using: .isoLatin1))
        let result = try #require(RSSParser(feedId: feedId).parse(data: data))

        #expect(result.title == "Caf\u{E9} Blog")
        #expect(result.items.first?.title == "Cr\u{E8}me br\u{FB}l\u{E9}e")
    }

    @Test("Handles a UTF-8 byte order mark and non-Latin text")
    func utf8BOMAndTurkish() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>Haberler</title>
          <item><title>\u{15E}ehir \u{131}\u{15F}\u{131}klar\u{131} \u{1F31F}</title><link>https://example.com/t</link></item>
        </channel></rss>
        """
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(xml.utf8))
        let result = try #require(RSSParser(feedId: feedId).parse(data: data))

        #expect(result.items.first?.title == "\u{15E}ehir \u{131}\u{15F}\u{131}klar\u{131} \u{1F31F}")
    }

    @Test("Decodes UTF-16 feeds")
    func utf16Encoding() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-16"?>
        <rss version="2.0"><channel><title>Wide</title>
          <item><title>\u{4E16}\u{754C}</title><link>https://example.com/w</link></item>
        </channel></rss>
        """
        let data = try #require(xml.data(using: .utf16))
        let result = try #require(RSSParser(feedId: feedId).parse(data: data))

        #expect(result.items.first?.title == "\u{4E16}\u{754C}")
    }
}
