import Testing
import Foundation
@testable import Versoline

@Suite("OPMLManager Tests")
struct OPMLManagerTests {

    @Test("Generated OPML parses back to the same feeds and folders")
    func roundTrip() {
        let news = Folder(name: "News")
        let feeds = [
            Feed(title: "BBC", url: "https://example.com/bbc.xml", folderId: news.id),
            Feed(title: "Loose", url: "https://example.com/loose.xml"),
        ]

        let xml = OPMLManager.generate(feeds: feeds, folders: [news])
        let parsed = OPMLManager().parse(data: Data(xml.utf8))

        #expect(parsed.count == 2)
        let bbc = parsed.first { $0.xmlUrl == "https://example.com/bbc.xml" }
        #expect(bbc?.title == "BBC")
        #expect(bbc?.folderName == "News")
        let loose = parsed.first { $0.xmlUrl == "https://example.com/loose.xml" }
        #expect(loose?.folderName == nil)
    }

    @Test("Special characters are escaped and restored")
    func escaping() {
        let feed = Feed(title: "Fish & \"Chips\" <Daily>", url: "https://example.com/feed?a=1&b=2")

        let xml = OPMLManager.generate(feeds: [feed], folders: [])
        let parsed = OPMLManager().parse(data: Data(xml.utf8))

        #expect(parsed.first?.title == "Fish & \"Chips\" <Daily>")
        #expect(parsed.first?.xmlUrl == "https://example.com/feed?a=1&b=2")
    }

    @Test("Empty folders are not exported")
    func emptyFolderOmitted() {
        let xml = OPMLManager.generate(feeds: [], folders: [Folder(name: "Empty")])

        #expect(!xml.contains("Empty"))
    }

    @Test("Nested folders: feeds are attached to the top-level folder")
    func nestedFolders() {
        let xml = """
        <opml version="2.0"><body>
          <outline text="Tech">
            <outline text="Sub">
              <outline type="rss" text="Deep" xmlUrl="https://example.com/deep.xml"/>
            </outline>
            <outline type="rss" text="Direct" xmlUrl="https://example.com/direct.xml"/>
          </outline>
          <outline type="rss" text="Top" xmlUrl="https://example.com/top.xml"/>
        </body></opml>
        """
        let parsed = OPMLManager().parse(data: Data(xml.utf8))

        #expect(parsed.count == 3)
        #expect(parsed.first { $0.title == "Deep" }?.folderName == "Tech")
        #expect(parsed.first { $0.title == "Direct" }?.folderName == "Tech")
        #expect(parsed.first { $0.title == "Top" }?.folderName == nil)
    }

    @Test("Title falls back to the URL when text and title are missing")
    func titleFallback() {
        let xml = #"<opml><body><outline xmlUrl="https://example.com/x.xml"/></body></opml>"#

        let parsed = OPMLManager().parse(data: Data(xml.utf8))

        #expect(parsed.first?.title == "https://example.com/x.xml")
    }

    @Test("Malformed OPML does not crash and yields what was parsed so far")
    func malformed() {
        #expect(OPMLManager().parse(data: Data("not xml".utf8)).isEmpty)
        #expect(OPMLManager().parse(data: Data("<opml><body><outline".utf8)).isEmpty)
    }

    @Test("A parser instance can be reused without leaking earlier results")
    func reuse() {
        let manager = OPMLManager()
        let first = #"<opml><body><outline text="A" xmlUrl="https://a.com/f"/></body></opml>"#
        let second = #"<opml><body><outline text="B" xmlUrl="https://b.com/f"/></body></opml>"#

        _ = manager.parse(data: Data(first.utf8))
        let result = manager.parse(data: Data(second.utf8))

        #expect(result.map(\.title) == ["B"])
    }
}
