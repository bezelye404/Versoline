import Foundation

// MARK: - HTML to article blocks
//
// Turns article HTML (a feed's content or a fetched page's main content) into `ArticleDocument`.
// The HTML is parsed into a DOM with Foundation's `XMLDocument` (libxml2, tidy mode), so real nesting is
// understood instead of regex-matching tags. While walking the tree it drops what is not article text:
// scripts, forms, navigation, share bars, ads, breadcrumbs, link-only lists and "follow us" lines.
// First-party Foundation only; no third-party HTML library.

enum ArticleParser {

    /// - Parameters:
    ///   - html: article HTML or a whole page.
    ///   - baseURL: used to resolve relative links and image addresses.
    ///   - title: when given, a heading that repeats it is dropped (the reader shows the title itself).
    static func parse(html: String, baseURL: URL?, title: String? = nil) -> ArticleDocument {
        guard let body = bodyElement(from: html) else { return ArticleDocument(blocks: []) }
        var builder = Builder(baseURL: baseURL)
        builder.collect(body.children ?? [])
        return builder.finish(title: title)
    }

    // MARK: - Parsing

    fileprivate static func bodyElement(from html: String) -> XMLElement? {
        guard !html.isEmpty,
              let data = withUTF8Declaration(html).data(using: .utf8),
              let document = try? XMLDocument(data: data, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let root = document.rootElement() else { return nil }
        return root.elements(forName: "body").first ?? root
    }

    /// libxml2 assumes a legacy encoding when none is declared, which garbles Turkish text.
    private static func withUTF8Declaration(_ html: String) -> String {
        let meta = "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">"
        let prepared = renamingHTML5Elements(html)
        if let head = prepared.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            var copy = prepared
            copy.insert(contentsOf: meta, at: head.upperBound)
            return copy
        }
        return meta + prepared
    }

    // libxml2 speaks HTML 4: it drops unknown tags (and their class/id) and keeps only their content, which would
    // lose exactly the hints used to recognise page furniture. HTML5 sectioning elements are therefore renamed to
    // <div data-tag="..."> in one linear pass and the original name is read back by `name(of:)`.
    private static let html5Elements = "article|aside|footer|header|main|nav|section|figure|figcaption|picture|details|summary|time|mark"
    private static let html5Open = try? NSRegularExpression(pattern: "<(\(html5Elements))(?=[\\s>/])", options: [.caseInsensitive])
    private static let html5Close = try? NSRegularExpression(pattern: "</(\(html5Elements))\\s*>", options: [.caseInsensitive])

    private static func renamingHTML5Elements(_ html: String) -> String {
        guard let open = html5Open, let close = html5Close else { return html }
        var result = html
        var range = NSRange(result.startIndex..., in: result)
        result = open.stringByReplacingMatches(in: result, range: range, withTemplate: "<div data-tag=\"$1\"")
        range = NSRange(result.startIndex..., in: result)
        return close.stringByReplacingMatches(in: result, range: range, withTemplate: "</div>")
    }

    /// Element name as written in the source: renamed HTML5 elements report their original name.
    fileprivate static func name(of element: XMLElement) -> String {
        if let original = element.attribute(forName: "data-tag")?.stringValue { return original.lowercased() }
        return element.name?.lowercased() ?? ""
    }

    // MARK: - Element classes

    private static let inlineTags: Set<String> = [
        "a", "abbr", "acronym", "b", "bdi", "bdo", "big", "br", "cite", "code", "data", "del", "dfn", "em", "font", "i",
        "ins", "kbd", "label", "mark", "q", "s", "samp", "small", "span", "strike", "strong", "sub", "sup", "time", "tt",
        "u", "var", "wbr",
    ]

    private static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "dd", "details", "div", "dl", "dt", "fieldset", "figcaption", "figure",
        "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "img", "li", "main", "nav", "ol", "p", "picture",
        "pre", "section", "summary", "table", "tbody", "td", "th", "thead", "tr", "ul",
    ]

    private static let discardedTags: Set<String> = [
        "script", "style", "noscript", "iframe", "svg", "canvas", "form", "button", "input", "select", "textarea", "nav",
        "footer", "header", "aside", "template", "dialog", "object", "embed", "audio", "video", "map", "menu", "head",
        "link", "meta", "title",
    ]

    /// Words in class/id names that mark page furniture. Matched as whole words ("ad-slot" yes, "download" no).
    private static let furnitureWords: Set<String> = [
        "ad", "ads", "adv", "advert", "advertisement", "adsbygoogle", "banner", "breadcrumb", "breadcrumbs", "comment",
        "comments", "cookie", "cookies", "consent", "footer", "menu", "nav", "navbar", "navigation", "newsletter",
        "pagination", "popup", "modal", "promo", "related", "share", "sharing", "social", "sidebar", "sponsor", "sponsored",
        "subscribe", "subscription", "toolbar", "widget", "follow", "reklam", "yorum", "paylas", "etiket", "tags",
    ]

    /// Short lines that are site chrome, not article text (Turkish and English).
    private static let boilerplatePhrases: [String] = [
        "google'da takip", "google haberler'de takip", "bizi takip edin", "abone ol", "haberi paylaş", "yorum yap",
        "ilgili haberler", "ilgili içerik", "diğer haberler", "reklam", "devamını oku", "çerez",
        "whatsapp kanal", "all rights reserved", "advertisement", "sponsored", "read more", "subscribe to our", "follow us",
        "sign up for", "newsletter", "cookie",
        "atlayın ve okumaya devam", "haberin sonu", "en çok okunanlar", "yayın tarihi", "okuma süresi", "google'da tercih",
        "anında haberdar", "oluşturulma tarihi", "haber girişi", "bildirdiği yer",
    ]

    /// Copyright and republication notices: long, so they are matched on their own.
    private static let legalPhrases: [String] = [
        "internet sitesinde yayınlanan", "tüm hakları saklıdır", "all rights reserved", "telif hakk",
    ]

    /// Whole-line labels of buttons and signatures. Matched exactly because they are common words inside real sentences.
    private static let chromeLines: Set<String> = ["kaydet", "paylaş", "yazdır", "yorumlar", "yorum", "reklam", "tweet", "|", "-", "•"]

    // MARK: - Builder

    fileprivate struct Style {
        var bold = false
        var italic = false
        var code = false
        var link: URL?
    }

    fileprivate struct Builder {
        let baseURL: URL?
        var blocks: [ArticleBlock] = []
        var imageCount = 0

        static let maxBlocks = 800
        static let maxImages = 30
        static let maxTableRows = 60
        static let maxTableColumns = 8

        // MARK: Walking

        /// Block-level structure: inline content between block elements becomes an anonymous paragraph.
        mutating func collect(_ nodes: [XMLNode]) {
            var buffer = AttributedString()
            for node in nodes {
                guard let element = node as? XMLElement else {
                    if node.kind == .text { ArticleParser.appendText(node.stringValue ?? "", style: Style(), to: &buffer) }
                    continue
                }
                let name = ArticleParser.name(of: element)
                if ArticleParser.isDiscarded(element, name: name) { continue }

                if ArticleParser.inlineTags.contains(name) && !ArticleParser.containsBlock(element) {
                    appendInline(element, name: name, style: Style(), to: &buffer)
                } else {
                    emitParagraph(buffer)
                    buffer = AttributedString()
                    handleBlock(element, name: name)
                }
            }
            emitParagraph(buffer)
        }

        private mutating func handleBlock(_ element: XMLElement, name: String) {
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let text = ArticleParser.trimmed(inlineText(of: element))
                if !text.characters.isEmpty {
                    blocks.append(.heading(level: Int(name.dropFirst()) ?? 2, text: text))
                }
            case "ul", "ol":
                handleList(element, ordered: name == "ol")
            case "blockquote":
                var inner = Builder(baseURL: baseURL)
                inner.collect(element.children ?? [])
                let text = ArticleParser.joined(inner.blocks.map(\.attributedText).filter { !$0.characters.isEmpty })
                if !text.characters.isEmpty { blocks.append(.quote(text)) }
            case "pre":
                let code = (element.stringValue ?? "").trimmingCharacters(in: .newlines)
                if !code.trimmingCharacters(in: .whitespaces).isEmpty { blocks.append(.code(code)) }
            case "hr":
                if case .rule? = blocks.last { return }
                if !blocks.isEmpty { blocks.append(.rule) }
            case "img":
                handleImage(element, caption: nil)
            case "picture":
                if let image = ArticleParser.firstDescendant(of: element, named: "img") { handleImage(image, caption: nil) }
            case "figure":
                if let image = ArticleParser.firstDescendant(of: element, named: "img") {
                    let caption = ArticleParser.firstDescendant(of: element, named: "figcaption")
                        .map { ArticleParser.trimmed(inlineText(of: $0)) }
                        .map { String($0.characters) }
                    handleImage(image, caption: caption?.isEmpty == true ? nil : caption)
                } else {
                    collect(element.children ?? [])
                }
            case "table":
                handleTable(element)
            default:
                collect(element.children ?? [])
            }
        }

        // MARK: Inline

        private func inlineText(of element: XMLElement, skippingLists: Bool = false) -> AttributedString {
            var buffer = AttributedString()
            appendChildren(of: element, style: Style(), skippingLists: skippingLists, to: &buffer)
            return buffer
        }

        private func appendChildren(of element: XMLElement, style: Style, skippingLists: Bool, to buffer: inout AttributedString) {
            for node in element.children ?? [] {
                guard let child = node as? XMLElement else {
                    if node.kind == .text { ArticleParser.appendText(node.stringValue ?? "", style: style, to: &buffer) }
                    continue
                }
                let name = ArticleParser.name(of: child)
                if ArticleParser.isDiscarded(child, name: name) { continue }
                if skippingLists && (name == "ul" || name == "ol") { continue }
                appendInline(child, name: name, style: style, to: &buffer, skippingLists: skippingLists)
            }
        }

        private func appendInline(_ element: XMLElement, name: String, style: Style, to buffer: inout AttributedString, skippingLists: Bool = false) {
            switch name {
            case "br":
                buffer.append(AttributedString("\n"))
                return
            case "img":
                return
            default:
                break
            }
            var next = style
            switch name {
            case "strong", "b": next.bold = true
            case "em", "i", "cite", "dfn", "var": next.italic = true
            case "code", "kbd", "samp", "tt": next.code = true
            case "a":
                if let href = element.attribute(forName: "href")?.stringValue, let url = ArticleParser.resolve(href, base: baseURL) {
                    next.link = url
                }
            default: break
            }
            let isBlock = ArticleParser.blockTags.contains(name)
            if isBlock { ArticleParser.appendText(" ", style: style, to: &buffer) }
            appendChildren(of: element, style: next, skippingLists: skippingLists, to: &buffer)
            if isBlock { ArticleParser.appendText(" ", style: style, to: &buffer) }
        }

        // MARK: Blocks

        private mutating func emitParagraph(_ buffer: AttributedString) {
            let text = ArticleParser.trimmed(buffer)
            guard !text.characters.isEmpty else { return }
            blocks.append(.paragraph(text))
        }

        private mutating func handleList(_ list: XMLElement, ordered: Bool) {
            var items: [AttributedString] = []
            var nested: [(XMLElement, Bool)] = []
            for child in list.elements(forName: "li") {
                let text = ArticleParser.trimmed(inlineText(of: child, skippingLists: true))
                if !text.characters.isEmpty { items.append(text) }
                for sub in (child.children ?? []).compactMap({ $0 as? XMLElement }) {
                    let subName = ArticleParser.name(of: sub)
                    if subName == "ul" || subName == "ol" { nested.append((sub, subName == "ol")) }
                }
            }
            // Menu entries mixed into a list with real text: drop the link-only short ones when there are several.
            items.removeAll { ArticleParser.isBoilerplateLine($0) }
            let menuEntries = items.filter { ArticleParser.isLinkOnlyLabel($0) }
            if menuEntries.count >= 3 { items.removeAll { ArticleParser.isLinkOnlyLabel($0) } }
            if !items.isEmpty && !ArticleParser.isNavigationList(items) {
                blocks.append(.list(ordered: ordered, items: items))
            }
            for (sub, isOrdered) in nested { handleList(sub, ordered: isOrdered) }
        }

        private mutating func handleImage(_ element: XMLElement, caption: String?) {
            guard imageCount < Builder.maxImages, let url = ArticleParser.imageURL(of: element, base: baseURL) else { return }
            if case .image(let last, _, _)? = blocks.last, last == url { return }
            let alt = element.attribute(forName: "alt")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            imageCount += 1
            blocks.append(.image(url: url, alt: alt, caption: caption))
        }

        private mutating func handleTable(_ table: XMLElement) {
            // Layout tables wrap real content: walk through them. Data tables become one line per row.
            if ArticleParser.containsAny(table, of: ["p", "div", "h1", "h2", "h3", "h4", "ul", "ol", "blockquote"]) {
                collect(table.children ?? [])
                return
            }
            var rows: [[AttributedString]] = []
            var hasHeader = false
            for row in ArticleParser.descendants(of: table, named: "tr") where rows.count < Builder.maxTableRows {
                let cellElements = ((row.children ?? []).compactMap { $0 as? XMLElement })
                    .filter { ["td", "th"].contains(ArticleParser.name(of: $0)) }
                let cells = cellElements.prefix(Builder.maxTableColumns).map { ArticleParser.trimmed(inlineText(of: $0)) }
                guard cells.contains(where: { !$0.characters.isEmpty }) else { continue }
                if rows.isEmpty, cellElements.allSatisfy({ ArticleParser.name(of: $0) == "th" }) { hasHeader = true }
                rows.append(Array(cells))
            }
            guard !rows.isEmpty else { return }
            // A single row or column is a list of values, not a table.
            if rows.count == 1 || rows.allSatisfy({ $0.count == 1 }) {
                for row in rows { for cell in row where !cell.characters.isEmpty { blocks.append(.paragraph(cell)) } }
            } else {
                // Short rows are padded so the grid lines up.
                let width = rows.map(\.count).max() ?? 0
                blocks.append(.table(rows: rows.map { $0 + Array(repeating: AttributedString(), count: width - $0.count) }, hasHeader: hasHeader))
            }
        }

        // MARK: Final pass

        func finish(title: String?) -> ArticleDocument {
            let normalizedTitle = title.map(ArticleParser.fold)
            var result: [ArticleBlock] = []
            for block in blocks {
                switch block {
                case .paragraph(let text):
                    if ArticleParser.isChrome(text) { continue }
                case .heading(let level, let text):
                    // The page's own title heading: the reader draws the title itself.
                    if level == 1, result.allSatisfy({ if case .image = $0 { true } else { false } }) { continue }
                    if let normalizedTitle, ArticleParser.fold(String(text.characters)) == normalizedTitle { continue }
                    if ArticleParser.isChrome(text) { continue }
                case .quote(let text):
                    if ArticleParser.isChrome(text) { continue }
                default:
                    break
                }
                if result.last == block { continue }
                result.append(block)
                if result.count >= Builder.maxBlocks { break }
            }
            // A page ends with chrome rather than with a rule or a lone heading.
            while let last = result.last {
                switch last {
                case .rule, .heading: result.removeLast()
                default: return ArticleDocument(blocks: result)
                }
            }
            return ArticleDocument(blocks: result)
        }
    }

    // MARK: - Text helpers

    fileprivate static func appendText(_ raw: String, style: Style, to buffer: inout AttributedString) {
        var text = collapse(raw)
        guard !text.isEmpty else { return }
        if text.hasPrefix(" "), buffer.characters.last.map({ $0 == " " || $0 == "\n" }) ?? true { text.removeFirst() }
        guard !text.isEmpty else { return }
        var run = AttributedString(text)
        var intent = InlinePresentationIntent()
        if style.bold { intent.insert(.stronglyEmphasized) }
        if style.italic { intent.insert(.emphasized) }
        if style.code { intent.insert(.code) }
        if !intent.isEmpty { run.inlinePresentationIntent = intent }
        if let link = style.link { run.link = link }
        buffer.append(run)
    }

    /// Runs of whitespace (including no-break spaces) become one space.
    fileprivate static func collapse(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var lastWasSpace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace || scalar == "\u{00A0}" || scalar == "\u{200B}" {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else {
                result.unicodeScalars.append(scalar)
                lastWasSpace = false
            }
        }
        return result
    }

    fileprivate static func trimmed(_ text: AttributedString) -> AttributedString {
        var result = text
        while let first = result.characters.first, first.isWhitespace { result.characters.removeFirst() }
        while let last = result.characters.last, last.isWhitespace { result.characters.removeLast() }
        return result
    }

    fileprivate static func joined(_ parts: [AttributedString]) -> AttributedString {
        var result = AttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 { result.append(AttributedString("\n\n")) }
            result.append(part)
        }
        return result
    }

    fileprivate static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ı", with: "i")   // dotless i is not a diacritic variant of i
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Page furniture rules

    fileprivate static func isDiscarded(_ element: XMLElement, name: String) -> Bool {
        if discardedTags.contains(name) { return true }
        if name == "article" || name == "main" || name == "body" { return false }
        if element.attribute(forName: "hidden") != nil {
            // React/Next.js streams finished server-rendered content inside <div hidden id="S:1b"> and a script
            // moves it into place afterwards, so that content is the page, not hidden furniture.
            let id = element.attribute(forName: "id")?.stringValue ?? ""
            let isStreamedContent = id.hasPrefix("S:") || id.hasPrefix("B:")
            if !isStreamedContent { return true }
        }
        if element.attribute(forName: "aria-hidden")?.stringValue == "true" { return true }
        if let style = element.attribute(forName: "style")?.stringValue?.lowercased(),
           style.contains("display:none") || style.contains("display: none") { return true }
        let words = labelWords(of: element)
        guard !words.isEmpty else { return false }
        return words.contains { furnitureWords.contains(String($0)) }
    }

    /// Short, link-dominated text or a known chrome phrase: not part of the story.
    fileprivate static func isChrome(_ text: AttributedString) -> Bool {
        let count = text.characters.count
        guard count > 0 else { return false }
        if count < 140 {
            var linked = 0
            for run in text.runs where run.link != nil { linked += text[run.range].characters.count }
            if Double(linked) / Double(count) > 0.6 { return true }
        }
        return isBoilerplateLine(text)
    }

    /// Known chrome wording, bare site names and button labels (no link test).
    fileprivate static func isBoilerplateLine(_ text: AttributedString) -> Bool {
        let length = text.characters.count
        guard length < 400 else { return false }
        let lower = String(text.characters).lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")   // also folds non-breaking spaces
        if legalPhrases.contains(where: { lower.contains($0) }) { return true }
        guard length < 140 else { return false }
        if chromeLines.contains(lower) { return true }
        if lower.hasPrefix("yazan,") || lower.hasPrefix("unvan,") { return true }   // BBC-style byline fields
        // A bare site name or address ("Odatv.com") closing a story.
        if !lower.contains(" "), lower.count <= 24, lower.contains("."), lower.hasSuffix(".com") || lower.hasSuffix(".com.tr") || lower.hasSuffix(".org") { return true }
        return boilerplatePhrases.contains { lower.contains($0) }
    }

    fileprivate static func isLinkOnlyLabel(_ item: AttributedString) -> Bool {
        let count = item.characters.count
        guard count > 0, count < 40 else { return false }
        var linked = 0
        for run in item.runs where run.link != nil { linked += item[run.range].characters.count }
        return Double(linked) / Double(count) > 0.9
    }

    /// Lists made of short links are menus, tag clouds and "related" boxes.
    fileprivate static func isNavigationList(_ items: [AttributedString]) -> Bool {
        var linked = 0
        var total = 0
        for item in items {
            total += item.characters.count
            for run in item.runs where run.link != nil { linked += item[run.range].characters.count }
        }
        guard total > 0 else { return true }
        let average = total / items.count
        if Double(linked) / Double(total) > 0.7 && average < 90 { return true }

        // Pickers and menus without links in the markup (city or category selectors): many one- or two-word
        // entries, none of them a sentence.
        let words = items.map { $0.characters.split(whereSeparator: { $0.isWhitespace }).count }
        if items.count >= 8 && average <= 24 && words.allSatisfy({ $0 <= 3 }) { return true }

        // A lone one- or two-word item is a label ("SICAK", "Paylaş"), not article content.
        return items.count == 1 && words[0] <= 2
    }

    // MARK: - DOM helpers

    fileprivate static func containsBlock(_ element: XMLElement) -> Bool {
        containsAny(element, of: blockTags)
    }

    fileprivate static func containsAny(_ element: XMLElement, of names: Set<String>) -> Bool {
        for case let child as XMLElement in element.children ?? [] {
            if names.contains(ArticleParser.name(of: child)) || containsAny(child, of: names) { return true }
        }
        return false
    }

    fileprivate static func firstDescendant(of element: XMLElement, named target: String) -> XMLElement? {
        for case let child as XMLElement in element.children ?? [] {
            if ArticleParser.name(of: child) == target { return child }
            if let found = firstDescendant(of: child, named: target) { return found }
        }
        return nil
    }

    fileprivate static func descendants(of element: XMLElement, named target: String) -> [XMLElement] {
        var found: [XMLElement] = []
        for case let child as XMLElement in element.children ?? [] {
            if ArticleParser.name(of: child) == target { found.append(child) }
            found += descendants(of: child, named: target)
        }
        return found
    }

    fileprivate static func resolve(_ raw: String, base: URL?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.lowercased().hasPrefix("javascript:") else { return nil }
        guard let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    /// Best image address of an `<img>`: the largest `srcset` candidate up to 1200 px, else the (lazy-load) src.
    fileprivate static func imageURL(of element: XMLElement, base: URL?) -> URL? {
        func number(_ name: String) -> Int? {
            element.attribute(forName: name)?.stringValue.flatMap { Int($0.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)) }
        }
        if let width = number("width"), width <= 10 { return nil }
        if let height = number("height"), height <= 10 { return nil }

        // Several short statements: one long expression here is too slow for the type checker on older Xcode.
        let className: String = element.attribute(forName: "class")?.stringValue ?? ""
        let idName: String = element.attribute(forName: "id")?.stringValue ?? ""
        let altText: String = element.attribute(forName: "alt")?.stringValue ?? ""
        let labels: String = [className, idName, altText].joined(separator: " ").lowercased()
        let words: [String] = labels.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let skippedWords: Set<String> = ["emoji", "pixel", "avatar"]
        for word in words where furnitureWords.contains(word) || skippedWords.contains(word) { return nil }

        var raw: String?
        for key in ["srcset", "data-srcset"] {
            if let set = element.attribute(forName: key)?.stringValue, let best = bestSource(inSrcset: set) { raw = best; break }
        }
        if raw == nil {
            for key in ["src", "data-src", "data-original", "data-lazy-src", "data-lazy"] {
                if let value = element.attribute(forName: key)?.stringValue, !value.isEmpty, !value.hasPrefix("data:") { raw = value; break }
            }
        }
        guard let raw, let url = resolve(raw, base: base) else { return nil }
        let lower = url.absoluteString.lowercased()
        if lower.hasSuffix(".svg") || lower.contains("pixel") || lower.contains("1x1") || lower.contains("spacer") { return nil }
        // Promo badges and banners that sit inside article markup ("follow us on Google News" and similar).
        if ["googlenews", "google-g", "preferred-source", "topbanner", "badge", "haberarasi"].contains(where: { lower.contains($0) }) { return nil }
        return url
    }

    private static func bestSource(inSrcset srcset: String) -> String? {
        var best: (url: String, width: Int)?
        for candidate in srcset.split(separator: ",") {
            let parts = candidate.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
            guard let url = parts.first, !url.hasPrefix("data:") else { continue }
            let width = parts.dropFirst().first.flatMap { Int($0.dropLast()) } ?? 0
            if width <= 1200, width >= (best?.width ?? -1) { best = (url, width) }
            else if best == nil { best = (url, width) }
        }
        return best?.url
    }
}

private extension ArticleBlock {
    /// Text of blocks that carry text, as attributed text (used to flatten a blockquote).
    var attributedText: AttributedString {
        switch self {
        case .heading(_, let text), .paragraph(let text), .quote(let text):
            return text
        case .list(_, let items):
            return ArticleParser.joinedItems(items)
        case .code(let code):
            return AttributedString(code)
        case .table(let rows, _):
            return ArticleParser.joinedItems(rows.map { row in row.reduce(into: AttributedString()) { $0 += ($0.characters.isEmpty ? AttributedString() : AttributedString(" · ")) + $1 } })
        case .image, .rule:
            return AttributedString()
        }
    }
}

extension ArticleParser {
    fileprivate static func joinedItems(_ items: [AttributedString]) -> AttributedString {
        var result = AttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            result.append(AttributedString("• "))
            result.append(item)
        }
        return result
    }
}


// MARK: - Finding the article in a whole page
//
// Readability-style scoring on the DOM: every paragraph-like block credits its container (fully) and the
// container's parent (half), weighted by link density and class/id hints; the best container, plus siblings
// that read like article text, is the article. Furniture inside it is removed later by `parse`.

extension ArticleParser {

    private static let positiveWords: Set<String> = [
        "article", "articlebody", "body", "content", "entry", "post", "story", "text", "detail", "main", "haber", "icerik", "news",
    ]
    private static let negativeWords: Set<String> = [
        "tags", "author", "byline", "meta", "date", "masthead", "outbrain", "taboola", "hero", "gallery", "carousel", "slider",
        "video", "podcast", "listing", "list",
    ]

    /// The HTML of the page's main article, or nil when nothing article-like is found.
    static func mainContentHTML(from html: String) -> String? {
        if let body = bodyElement(from: html), let content = bestContainerHTML(in: body) { return content }
        return jsonLDArticleHTML(from: html)
    }

    /// Lower-case words of an element's class and id names. Kept as plain statements: one long `??` and `+`
    /// expression is too slow for the type checker on older Xcode versions.
    fileprivate static func labelWords(of element: XMLElement) -> [Substring] {
        let className: String = element.attribute(forName: "class")?.stringValue ?? ""
        let idName: String = element.attribute(forName: "id")?.stringValue ?? ""
        let labels: String = [className, idName].joined(separator: " ").lowercased()
        return labels.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }

    private static func classWeight(of element: XMLElement) -> Double {
        var weight = 0.0
        if name(of: element) == "article" { weight += 10 }
        if element.attribute(forName: "itemprop")?.stringValue?.lowercased() == "articlebody" { weight += 40 }
        let words = labelWords(of: element)
        if words.contains(where: { positiveWords.contains(String($0)) }) { weight += 25 }
        if words.contains(where: { negativeWords.contains(String($0)) }) { weight -= 20 }
        return weight
    }

    private static func ownTextLength(of element: XMLElement) -> Int {
        var count = 0
        for node in element.children ?? [] where node.kind == .text {
            count += (node.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count
        }
        return count
    }

    private static func linkDensity(of element: XMLElement) -> Double {
        let total = (element.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count
        guard total > 0 else { return 1 }
        let linked = descendants(of: element, named: "a").reduce(0) { $0 + ($1.stringValue ?? "").count }
        return min(1, Double(linked) / Double(total))
    }

    private static func bestContainerHTML(in body: XMLElement) -> String? {
        var scores: [ObjectIdentifier: Double] = [:]
        var nodes: [ObjectIdentifier: XMLElement] = [:]

        func credit(_ element: XMLElement, _ amount: Double) {
            let key = ObjectIdentifier(element)
            if scores[key] == nil {
                scores[key] = classWeight(of: element)
                nodes[key] = element
            }
            scores[key]! += amount
        }

        func visit(_ element: XMLElement) {
            let elementName = name(of: element)
            if isDiscarded(element, name: elementName) { return }
            let paragraphLike = elementName == "p" || elementName == "pre" || elementName == "blockquote"
            let length = paragraphLike ? (element.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count : ownTextLength(of: element)
            if length >= (paragraphLike ? 25 : 80) {
                let commas = (element.stringValue ?? "").reduce(0) { $0 + (($1 == "," || $1 == "،") ? 1 : 0) }
                let score = (1 + Double(commas) + Double(min(length / 100, 3))) * (1 - linkDensity(of: element))
                if paragraphLike {
                    if let parent = element.parent as? XMLElement, name(of: parent) != "body" {
                        credit(parent, score)
                        if let grand = parent.parent as? XMLElement, name(of: grand) != "body" { credit(grand, score / 2) }
                    }
                } else {
                    credit(element, score)
                    if let parent = element.parent as? XMLElement, name(of: parent) != "body" { credit(parent, score / 2) }
                }
            }
            for case let child as XMLElement in element.children ?? [] { visit(child) }
        }
        visit(body)

        var best: (XMLElement, Double)?
        for (key, raw) in scores {
            guard let element = nodes[key] else { continue }
            let adjusted = raw * (1 - linkDensity(of: element))
            if adjusted > (best?.1 ?? 0) { best = (element, adjusted) }
        }
        guard let (winner, bestScore) = best else { return nil }

        // Merge siblings that look like more of the same article (split bodies, inline figures).
        var pieces: [XMLElement] = [winner]
        if let parent = winner.parent as? XMLElement {
            pieces = []
            for case let sibling as XMLElement in parent.children ?? [] {
                if sibling === winner { pieces.append(sibling); continue }
                let siblingName = name(of: sibling)
                if isDiscarded(sibling, name: siblingName) { continue }
                let siblingScore = (scores[ObjectIdentifier(sibling)] ?? 0) * (1 - linkDensity(of: sibling))
                let text = (sibling.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if siblingScore >= bestScore * 0.2 || (siblingName == "p" && text.count >= 80 && linkDensity(of: sibling) < 0.25) {
                    pieces.append(sibling)
                }
            }
        }

        let result = pieces.map(\.xmlString).joined(separator: "\n")
        let textLength = pieces.reduce(0) { $0 + ($1.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count }
        return textLength >= 250 ? result : nil
    }

    // MARK: - Structured data fallback

    private static let jsonLDScript = try? NSRegularExpression(
        pattern: #"<script[^>]*ld\+json[^>]*>([\s\S]*?)</script>"#, options: [.caseInsensitive]
    )

    /// Many news sites publish the full text as `articleBody` in JSON-LD; used when the markup yields nothing.
    private static func jsonLDArticleHTML(from html: String) -> String? {
        guard let regex = jsonLDScript else { return nil }
        let ns = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let json = ns.substring(with: match.range(at: 1))
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let body = articleBody(in: object), body.count >= 250 else { continue }
            let paragraphs = body.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return paragraphs.map { "<p>\(escapeHTML($0))</p>" }.joined(separator: "\n")
        }
        return nil
    }

    private static func articleBody(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let body = dictionary["articleBody"] as? String { return body }
            for value in dictionary.values { if let found = articleBody(in: value) { return found } }
        } else if let array = object as? [Any] {
            for value in array { if let found = articleBody(in: value) { return found } }
        }
        return nil
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
