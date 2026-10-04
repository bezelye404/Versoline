import Testing
import Foundation
@testable import Versoline

struct FeedDiscoveryTests {

    private let base = URL(string: "https://blog.example.com/2026/post/")!

    @Test func findsTheAdvertisedFeed() {
        let html = """
        <html><head>
        <link rel="stylesheet" href="/style.css">
        <link rel="alternate" type="application/rss+xml" title="Example Blog" href="https://blog.example.com/feed/">
        </head><body></body></html>
        """
        let found = FeedDiscovery.candidates(inHTML: html, baseURL: base)
        #expect(found == [FeedDiscovery.Candidate(url: URL(string: "https://blog.example.com/feed/")!, title: "Example Blog")])
    }

    @Test func resolvesRelativeAddressesAndHandlesQuotesAndCase() {
        let html = """
        <LINK REL='alternate' TYPE='application/atom+xml' HREF='/atom.xml?x=1&amp;y=2' TITLE='Atom'>
        <link href=feed.xml type=application/rss+xml rel=alternate>
        """
        let found = FeedDiscovery.candidates(inHTML: html, baseURL: base)
        #expect(found.map(\.url.absoluteString) == [
            "https://blog.example.com/atom.xml?x=1&y=2",
            "https://blog.example.com/2026/post/feed.xml",
        ])
    }

    @Test func skipsCommentFeedsDuplicatesAndOtherLinks() {
        let html = """
        <link rel="alternate" type="application/rss+xml" title="Posts" href="/feed">
        <link rel="alternate" type="application/rss+xml" title="Comments on Posts" href="/comments/feed">
        <link rel="alternate" type="application/rss+xml" title="Posts again" href="/feed">
        <link rel="alternate" hreflang="tr" href="/tr/">
        <link rel="alternate" type="application/json" href="/wp-json/">
        <link rel="alternate" type="application/rss+xml" title="Yorumlar" href="/yorum-feed">
        <link rel="canonical" href="/post">
        """
        #expect(FeedDiscovery.candidates(inHTML: html, baseURL: base).map(\.url.path) == ["/feed"])
    }

    @Test func ignoresNonWebSchemes() {
        let html = #"<link rel="alternate" type="application/rss+xml" href="javascript:alert(1)"><link rel="alternate" type="application/rss+xml" href="ftp://x.example.com/feed">"#
        #expect(FeedDiscovery.candidates(inHTML: html, baseURL: base).isEmpty)
    }

    @Test func pagesWithoutFeedsGiveNothing() {
        #expect(FeedDiscovery.candidates(inHTML: "<html><head><title>x</title></head></html>", baseURL: base).isEmpty)
        #expect(FeedDiscovery.candidates(inHTML: "", baseURL: base).isEmpty)
    }

    @Test func recognisesFeedDocumentsAndNotPages() {
        #expect(FeedDiscovery.looksLikeFeed(Data(#"<?xml version="1.0"?><rss version="2.0"><channel>"#.utf8)))
        #expect(FeedDiscovery.looksLikeFeed(Data(#"<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">"#.utf8)))
        #expect(FeedDiscovery.looksLikeFeed(Data("<rdf:RDF xmlns:rdf=\"x\">".utf8)))
        #expect(!FeedDiscovery.looksLikeFeed(Data("<!DOCTYPE html><html><head><link rel=\"alternate\" type=\"application/rss+xml\"></head>".utf8)))
        #expect(!FeedDiscovery.looksLikeFeed(Data("<html><body>Not found, try our <rss> page</body></html>".utf8)))
        #expect(!FeedDiscovery.looksLikeFeed(Data()))
    }

    @Test func probesTheSectionOfThePageBeforeTheSiteRoot() {
        #expect(FeedDiscovery.probePaths(forPagePath: "/turkce/articles/cve8xk9kwxz5o").prefix(3) == ["/turkce/index.xml", "/turkce/feed", "/turkce/rss.xml"])
        #expect(FeedDiscovery.probePaths(forPagePath: "/turkce/articles/x").contains("/feed"))
        #expect(FeedDiscovery.probePaths(forPagePath: "").first == "/feed")
        #expect(FeedDiscovery.probePaths(forPagePath: "/").first == "/feed")
    }
}
