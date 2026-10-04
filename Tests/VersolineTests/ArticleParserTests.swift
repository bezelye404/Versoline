import Testing
import Foundation
@testable import Versoline

@Suite("Article Parser Tests")
struct ArticleParserTests {

    private let base = URL(string: "https://news.example.com/world/story-1")

    private func parse(_ html: String, title: String? = nil) -> ArticleDocument {
        ArticleParser.parse(html: html, baseURL: base, title: title)
    }

    private func texts(_ doc: ArticleDocument) -> [String] {
        doc.blocks.map(\.plainText).filter { !$0.isEmpty }
    }

    // MARK: - Structure

    @Test("Paragraphs, headings, lists, quotes and code become blocks in order")
    func structure() {
        let doc = parse("""
        <h2>Section</h2>
        <p>First paragraph with enough words to be a real paragraph of an article.</p>
        <ul><li>One thing to remember well</li><li>Another thing worth remembering</li></ul>
        <blockquote><p>A quoted sentence from somebody.</p></blockquote>
        <pre><code>let x = 1
        let y = 2</code></pre>
        """)

        #expect(doc.blocks.count == 5)
        if case .heading(let level, let text) = doc.blocks[0] { #expect(level == 2); #expect(String(text.characters) == "Section") } else { Issue.record("heading") }
        if case .list(let ordered, let items) = doc.blocks[2] { #expect(!ordered); #expect(items.count == 2) } else { Issue.record("list") }
        if case .quote(let text) = doc.blocks[3] { #expect(String(text.characters) == "A quoted sentence from somebody.") } else { Issue.record("quote") }
        if case .code(let code) = doc.blocks[4] { #expect(code.contains("let x = 1")) } else { Issue.record("code") }
    }

    @Test("Inline emphasis and links are kept as attributes")
    func inlineAttributes() throws {
        let doc = parse("<p>Plain <strong>bold</strong> and <em>italic</em> with <a href=\"/related/page\">a link</a>.</p>")

        guard case .paragraph(let text) = try #require(doc.blocks.first) else { Issue.record("paragraph"); return }
        #expect(String(text.characters) == "Plain bold and italic with a link.")
        let runs = Array(text.runs)
        #expect(runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
        #expect(runs.contains { $0.link == URL(string: "https://news.example.com/related/page") })
    }

    @Test("Whitespace is collapsed and entities are decoded; Turkish text survives")
    func whitespaceAndEntities() {
        let doc = parse("<p>  Fish &amp;\n\n   chips   &nbsp; İstanbul’da   şöyle   oldu  </p>")

        #expect(texts(doc) == ["Fish & chips İstanbul’da şöyle oldu"])
    }

    @Test("A line break inside a paragraph stays a line break")
    func lineBreak() {
        #expect(texts(parse("<p>First line<br>Second line</p>")) == ["First line\nSecond line"])
    }

    @Test("Inline text between block elements becomes its own paragraph")
    func anonymousParagraph() {
        let doc = parse("<div>Loose text<p>Real paragraph</p>More loose text</div>")

        #expect(texts(doc) == ["Loose text", "Real paragraph", "More loose text"])
    }

    // MARK: - Page furniture

    @Test("Scripts, styles, forms, navigation, footers and asides are dropped")
    func discardedTags() {
        let doc = parse("""
        <nav><a href="/">Home</a></nav>
        <script>alert(1)</script><style>p{color:red}</style>
        <form><input value="x"><button>Send</button></form>
        <p>The actual story text that matters to the reader.</p>
        <aside><p>Sidebar text that should disappear.</p></aside>
        <footer><p>© 2026 Example News</p></footer>
        """)

        #expect(texts(doc) == ["The actual story text that matters to the reader."])
    }

    @Test("Breadcrumbs, share bars, related boxes and ads are dropped by class and id")
    func furnitureByClass() {
        let doc = parse("""
        <div class="breadcrumb"><a href="/">Odatv</a> &gt; <a href="/guncel">Güncel</a></div>
        <div class="social-share"><p>Paylaş</p></div>
        <div id="ad-slot-1"><p>Sponsored content here</p></div>
        <p>Suriye İçişleri Bakanlığı açıklama yaptı ve ayrıntıları duyurdu bugün.</p>
        <section class="related-posts"><p>Başka bir haber başlığı</p></section>
        """)

        #expect(texts(doc) == ["Suriye İçişleri Bakanlığı açıklama yaptı ve ayrıntıları duyurdu bugün."])
    }

    @Test("Class words match whole words only: 'download' and 'headline' are not furniture")
    func wholeWordMatching() {
        let doc = parse("<div class=\"download-box headline\"><p>This paragraph must stay in the article.</p></div>")

        #expect(texts(doc) == ["This paragraph must stay in the article."])
    }

    @Test("A list made only of short links (menu, tags, related) is dropped; a list with real text stays")
    func navigationLists() {
        let doc = parse("""
        <ul><li><a href="/a">Odatv</a></li><li><a href="/b">Güncel</a></li></ul>
        <ul><li>Step one: prepare the ingredients carefully before cooking.</li><li>Step two: heat the pan and add the oil.</li></ul>
        """)

        #expect(doc.blocks.count == 1)
        if case .list(_, let items) = doc.blocks[0] { #expect(items.count == 2) } else { Issue.record("list expected") }
    }

    @Test("Short link-only lines and 'follow us' banners are dropped; long linked sentences stay")
    func chromeLines() {
        let doc = parse("""
        <p><a href="https://news.google.com/x">Okurlarımız dikkat... Google'da Odatv'yi takip edin</a> Takip Et</p>
        <p><a href="/tag/a">Etiket bir</a> <a href="/tag/b">Etiket iki</a></p>
        <p>Read the <a href="/full">full report published today by the ministry of finance</a> for every detail of the new budget plan.</p>
        <p>Bizi takip edin</p>
        """)

        #expect(texts(doc) == ["Read the full report published today by the ministry of finance for every detail of the new budget plan."])
    }

    @Test("Hidden elements are dropped")
    func hiddenElements() {
        let doc = parse("<p hidden>Hidden</p><p style=\"display: none\">Also hidden</p><p aria-hidden=\"true\">Screen reader hidden</p><p>Visible text of the story.</p>")

        #expect(texts(doc) == ["Visible text of the story."])
    }

    // MARK: - Images

    @Test("Images resolve relative addresses, prefer the largest srcset up to 1200 px, and keep captions")
    func images() throws {
        let doc = parse("""
        <figure><img src="/small.jpg" srcset="/a-400.jpg 400w, /a-800.jpg 800w, /a-2400.jpg 2400w" alt="A view">
        <figcaption>The view from the hill</figcaption></figure>
        <img data-src="https://cdn.example.com/lazy.png" alt="">
        """)

        #expect(doc.blocks.count == 2)
        guard case .image(let first, let alt, let caption) = doc.blocks[0] else { Issue.record("image"); return }
        #expect(first.absoluteString == "https://news.example.com/a-800.jpg")
        #expect(alt == "A view")
        #expect(caption == "The view from the hill")
        guard case .image(let second, _, _) = doc.blocks[1] else { Issue.record("lazy image"); return }
        #expect(second.absoluteString == "https://cdn.example.com/lazy.png")
    }

    @Test("Tracking pixels, data URIs, SVG icons, avatars and ad images are ignored")
    func ignoredImages() {
        let doc = parse("""
        <img src="https://t.example.com/p.gif" width="1" height="1">
        <img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=">
        <img src="/logo.svg">
        <img src="/me.jpg" class="author-avatar">
        <img src="/banner.jpg" class="ad-banner">
        <p>Only text remains.</p>
        """)

        #expect(doc.blocks.count == 1)
    }

    @Test("The same image twice in a row is kept once")
    func duplicateImages() {
        let doc = parse("<img src=\"/a.jpg\"><img src=\"/a.jpg\"><p>Text of the article body goes here.</p>")

        #expect(doc.blocks.filter { if case .image = $0 { return true } else { return false } }.count == 1)
    }

    // MARK: - Titles, tables, robustness

    @Test("A heading that repeats the article title is dropped")
    func duplicateTitle() {
        let doc = parse("<h1>Mihraç Ural'ın yardımcısı yakalandı</h1><p>Body text of the story is here for the reader.</p>", title: "MIHRAC URAL'IN YARDIMCISI YAKALANDI")

        #expect(texts(doc) == ["Body text of the story is here for the reader."])
    }

    @Test("Layout tables are walked through; data tables become one line per row")
    func tables() {
        let layout = parse("<table><tr><td><p>Story inside a layout table that is long enough.</p></td></tr></table>")
        #expect(texts(layout) == ["Story inside a layout table that is long enough."])

        let data = parse("<table><tr><th>Team</th><th>Score</th></tr><tr><td>Galatasaray</td><td>2</td></tr></table>")
        #expect(texts(data) == ["Team · Score", "Galatasaray · 2"])
    }

    @Test("A document ends with content, not with a rule or a stray heading")
    func trailingFurniture() {
        let doc = parse("<p>Story text that is the whole point of the page.</p><hr><h3>Related</h3>")

        #expect(doc.blocks.count == 1)
    }

    @Test("Garbage and empty input never crash")
    func robustness() {
        #expect(parse("").isEmpty)
        #expect(parse("   ").isEmpty)
        _ = parse("<<<>>><p<div>>>")
        _ = parse("<p>unterminated <b>bold <i>italic")
        _ = parse(String(repeating: "<div>", count: 2_000))
    }

    @Test("A large page is processed quickly")
    func performance() {
        let paragraph = "<p>" + String(repeating: "word ", count: 80) + "<a href=\"/x\">link</a></p>"
        let html = "<div class=\"content\">" + String(repeating: paragraph, count: 600) + "</div>"
        let start = Date()

        let doc = parse(html)

        #expect(!doc.isEmpty)
        #expect(Date().timeIntervalSince(start) < 2.0)
    }

    @Test("plainText and wordCount reflect the text blocks")
    func plainText() {
        let doc = parse("<h2>Title</h2><p>One two three.</p><ul><li>four</li><li>five</li></ul>")

        #expect(doc.plainText == "Title\n\nOne two three.\n\nfour\nfive")
        #expect(doc.wordCount == 6)
    }

    @Test func dropsLinklessPickersAndLabels() {
        let cities = ["Adana", "Adıyaman", "Afyonkarahisar", "Ağrı", "Aksaray", "Amasya", "Ankara", "Antalya", "Ardahan"]
            .map { "<li>\($0)</li>" }.joined()
        let html = "<body><ul><li>SICAK</li></ul><ul>\(cities)</ul><p>Afet ve Acil Durum Yönetimi Başkanlığı raporu yayımladı ve açıklamalarda bulundu.</p><ul><li>First point of the story is here</li><li>Second point of the story is here</li></ul></body>"
        let doc = ArticleParser.parse(html: html, baseURL: nil)
        #expect(doc.blocks.count == 2)
        #expect(!doc.plainText.contains("Adana"))
        #expect(!doc.plainText.contains("SICAK"))
        #expect(doc.plainText.contains("Second point"))
    }

    // MARK: - Main content

    private let sentence = "Bu cümle haberin gerçek metnidir, uzun ve düzgün yazılmıştır, virgüller içerir ve bir paragrafı doldurur. "

    @Test func picksTheArticleOverWidgetsAndMenus() {
        let paragraphs = (1...4).map { "<p>Paragraf \($0). \(sentence)</p>" }.joined()
        let html = """
        <html><body>
        <div class="top"><ul><li><a href="/a">Gündem</a></li><li><a href="/b">Spor</a></li><li><a href="/c">Ekonomi</a></li></ul></div>
        <div class="widgets"><h3>Bir bakışta</h3><p>Ara seçimlere giden ABD'de anketler ne anlatıyor?</p><img src="/podcast.jpg"></div>
        <div class="article-body">\(paragraphs)</div>
        <div class="footer-links"><a href="/x">Gizlilik</a></div>
        </body></html>
        """
        let content = ArticleParser.mainContentHTML(from: html)
        #expect(content != nil)
        let document = ArticleParser.parse(html: content ?? "", baseURL: nil)
        #expect(document.plainText.contains("Paragraf 4"))
        #expect(!document.plainText.contains("Bir bakışta"))
        #expect(!document.plainText.contains("Gündem"))
        #expect(document.blocks.allSatisfy { if case .image = $0 { return false } else { return true } })
    }

    @Test func keepsSiblingParagraphsOfTheBody() {
        let first = "<div class=\"story-text\">" + (1...3).map { "<p>Birinci \($0). \(sentence)</p>" }.joined() + "</div>"
        let html = "<html><body><div class=\"wrap\">\(first)<p>Kapanış paragrafı. \(sentence)</p></div></body></html>"
        let document = ArticleParser.parse(html: ArticleParser.mainContentHTML(from: html) ?? "", baseURL: nil)
        #expect(document.plainText.contains("Birinci 3"))
        #expect(document.plainText.contains("Kapanış paragrafı"))
    }

    @Test func fallsBackToStructuredData() {
        let body = String(repeating: "Haberin tam metni burada yer alır. ", count: 12)
        let html = "<html><head><script type=\"application/ld+json\">{\"@type\":\"NewsArticle\",\"articleBody\":\"\(body)\"}</script></head><body><div>Menü</div></body></html>"
        let content = ArticleParser.mainContentHTML(from: html)
        #expect(content?.contains("Haberin tam metni") == true)
    }

    @Test func returnsNilWhenThereIsNoArticle() {
        #expect(ArticleParser.mainContentHTML(from: "<html><body><p>Kısa.</p></body></html>") == nil)
    }

    @Test func dropsMenuEntriesInsideMixedLists() {
        let menu = ["Arama", "Anasayfa", "Gündem", "Türkiye"].map { "<li><a href=\"/\($0)\">\($0)</a></li>" }.joined()
        let html = "<body><ul>\(menu)<li>Diğer haber metni burada uzun bir cümle olarak devam ediyor ve bitiyor.</li></ul></body>"
        let document = ArticleParser.parse(html: html, baseURL: URL(string: "https://news.example.com/"))
        #expect(!document.plainText.contains("Anasayfa"))
        #expect(document.plainText.contains("Diğer haber metni"))
    }

    @Test func keepsStreamedServerRenderedContent() {
        // Next.js streams finished content into <div hidden id="S:1b"> and moves it with a script.
        let paragraphs = (1...3).map { "<p>Akış paragrafı \($0). \(sentence)</p>" }.joined()
        let html = "<html><body><div hidden id=\"S:1b\"><div class=\"prose\">\(paragraphs)</div></div><div hidden class=\"promo-popup\"><p>Gizli reklam metni burada uzun uzun yer alır ve görünmez.</p></div></body></html>"
        let document = ArticleParser.parse(html: ArticleParser.mainContentHTML(from: html) ?? "", baseURL: nil)
        #expect(document.plainText.contains("Akış paragrafı 3"))
        #expect(!document.plainText.contains("Gizli reklam"))
    }
}
