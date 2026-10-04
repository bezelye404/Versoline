import Testing
import Foundation
@testable import Versoline

@Suite("HTMLCleaner Tests")
struct HTMLCleanerTests {

    @Test("Decodes named, decimal and hex entities")
    func entities() {
        #expect(HTMLCleaner.decodeEntities("Tom &amp; Jerry") == "Tom & Jerry")
        #expect(HTMLCleaner.decodeEntities("&ldquo;Hi&rdquo; &mdash; &hellip;") == "“Hi” — …")
        #expect(HTMLCleaner.decodeEntities("&#65;&#x42;&#X43;") == "ABC")
        #expect(HTMLCleaner.decodeEntities("&#128512;") == "\u{1F600}")
    }

    @Test("Leaves text without entities and unknown entities untouched")
    func untouched() {
        #expect(HTMLCleaner.decodeEntities("plain text") == "plain text")
        #expect(HTMLCleaner.decodeEntities("&unknown;") == "&unknown;")
    }

    @Test("Invalid code points do not crash")
    func invalidCodePoints() {
        #expect(HTMLCleaner.decodeEntities("&#1114112;") == "&#1114112;")
        #expect(HTMLCleaner.decodeEntities("&#xD800;") == "&#xD800;")
    }

    @Test("Strips tags, decodes entities and collapses whitespace")
    func stripHTML() {
        let html = "<p>Hello   <b>world</b></p>\n<p>Fish &amp; chips</p>"

        #expect(HTMLCleaner.stripHTMLAndDecode(html) == "Hello world Fish & chips")
        #expect("<i>x</i>".strippingHTML() == "x")
    }

    @Test("Removes script tags and social sharing noise")
    func boilerplate() {
        let html = "Real content <script>alert(1)</script> more content"

        let cleaned = HTMLCleaner.removeBoilerplateNoise(html)

        #expect(!cleaned.contains("alert"))
        #expect(cleaned.contains("Real content"))
        #expect(cleaned.contains("more content"))
    }

    @Test("Removes ad containers, ad links and tracking pixels but keeps article text")
    func ads() {
        let html = """
        <p>Article text</p>
        <div class="advertisement">Buy now</div>
        <a href="https://ad.doubleclick.net/x">Click</a>
        <img src="https://t.example.com/p.gif" width="1" height="1">
        <ins class="adsbygoogle">ad</ins>
        <p>More text</p>
        """

        let cleaned = HTMLCleaner.stripAdvertisementsAndBanners(html)

        #expect(cleaned.contains("Article text"))
        #expect(cleaned.contains("More text"))
        #expect(!cleaned.contains("Buy now"))
        #expect(!cleaned.contains("doubleclick"))
        #expect(!cleaned.contains("width=\"1\""))
        #expect(!cleaned.contains("adsbygoogle"))
    }

    @Test("Removes empty paragraphs")
    func emptyParagraphs() {
        let cleaned = HTMLCleaner.stripAdvertisementsAndBanners("<p>Keep</p><p>&nbsp;</p><p> </p>")

        #expect(cleaned == "<p>Keep</p>")
    }
}
