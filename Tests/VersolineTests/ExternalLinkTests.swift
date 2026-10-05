import Testing
import Foundation
@testable import Versoline

struct ExternalLinkTests {

    private func address(_ text: String) -> String? { ExternalLink.feedAddress(from: URL(string: text)!) }

    @Test func feedSchemesBecomeWebAddresses() {
        #expect(address("feed://example.com/rss") == "https://example.com/rss")
        #expect(address("feeds://example.com/rss?x=1") == "https://example.com/rss?x=1")
        #expect(address("feed:https://example.com/atom.xml") == "https://example.com/atom.xml")
        #expect(address("feed:http://example.com/atom.xml") == "http://example.com/atom.xml")
        #expect(address("FEED://Example.com/rss") == "https://Example.com/rss")
    }

    @Test func otherLinksAreNotFeeds() {
        #expect(address("https://example.com/rss") == nil)
        #expect(address("mailto:someone@example.com") == nil)
        #expect(address("feed://") == nil)
    }

    @Test func opmlFilesAreRecognised() {
        #expect(ExternalLink.kind(of: URL(fileURLWithPath: "/tmp/subscriptions.opml")) == .opml(URL(fileURLWithPath: "/tmp/subscriptions.opml")))
        #expect(ExternalLink.kind(of: URL(fileURLWithPath: "/tmp/notes.txt")) == nil)
        #expect(ExternalLink.kind(of: URL(string: "feed://example.com/rss")!) == .feed("https://example.com/rss"))
    }
}
