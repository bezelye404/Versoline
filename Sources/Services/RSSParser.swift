import Foundation

final class RSSParser: NSObject, XMLParserDelegate, @unchecked Sendable {

    private var feedId: UUID
    private var items: [FeedItem] = []
    private var feedTitle: String = ""
    private var feedDescription: String = ""
    private var feedImageURL: String?

    // Parse state
    private var currentElement: String = ""
    private var currentTitle: String = ""
    private var currentLink: String = ""
    private var currentDescription: String = ""
    private var currentPubDate: String = ""
    private var currentAuthor: String = ""
    private var currentContent: String = ""
    private var isInsideItem: Bool = false
    private var isInsideChannel: Bool = false
    private var isInsideImage: Bool = false

    // Podcast support
    private var currentAudioURL: String?
    private var currentAudioDuration: String = ""
    private var currentAudioType: String?
    private var currentAudioLength: Int64?

    // Atom support
    private var isAtomFeed: Bool = false

    // URLSession with custom User-Agent, timeout, and zero URLCache overhead
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": "EasyRSS/1.0 (Macintosh; Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)"
        ]
        return URLSession(configuration: config)
    }()

    init(feedId: UUID) {
        self.feedId = feedId
        super.init()
    }

    struct ParseResult: Sendable {
        let title: String
        let description: String
        let imageURL: String?
        let items: [FeedItem]
        var etag: String? = nil
        var lastModified: String? = nil
        var isNotModified: Bool = false
    }

    func parse(data: Data) -> ParseResult? {
        autoreleasepool {
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.shouldResolveExternalEntities = false

            guard parser.parse() else {
                return nil
            }

            return ParseResult(
                title: feedTitle,
                description: feedDescription,
                imageURL: feedImageURL,
                items: items
            )
        }
    }

    static func fetchAndParse(
        url: String,
        feedId: UUID,
        etag: String? = nil,
        lastModified: String? = nil
    ) async throws -> ParseResult? {
        guard let feedURL = URL(string: url) else {
            await AppLogger.shared.log("Invalid feed URL: \(url)", level: .error, category: .network)
            throw URLError(.badURL)
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        await AppLogger.shared.log("Fetching feed: \(feedURL.host ?? url)", level: .info, category: .network, details: url)

        var request = URLRequest(url: feedURL)
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        if feedURL.host?.lowercased().contains("reddit.com") == true {
            request.setValue("EasyRSS/1.0 (macOS; com.bezelye.EasyRSS; build 1) (by /u/EasyRSSApp)", forHTTPHeaderField: "User-Agent")
        } else {
            request.setValue("EasyRSS/1.0 (Macintosh; Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
        }

        let (data, response) = try await session.data(for: request)

        var responseETag: String?
        var responseLastModified: String?

        if let httpResponse = response as? HTTPURLResponse {
            let elapsed = String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - startTime)

            if httpResponse.statusCode == 304 {
                await AppLogger.shared.log(
                    "HTTP 304 Not Modified (\(elapsed)) from \(feedURL.host ?? url) - 0 bytes downloaded/parsed",
                    level: .info,
                    category: .network
                )
                return ParseResult(
                    title: "",
                    description: "",
                    imageURL: nil,
                    items: [],
                    etag: etag,
                    lastModified: lastModified,
                    isNotModified: true
                )
            }

            if httpResponse.statusCode == 429 {
                let reset = httpResponse.value(forHTTPHeaderField: "x-ratelimit-reset") ?? ""
                let resetInfo = reset.isEmpty ? "" : " (Reset: \(reset)s)"
                let limitMsg = String(localized: "Rate limit reached (HTTP 429). Please wait a moment before trying again.") + resetInfo
                await AppLogger.shared.log(
                    "Rate limit 429 returned for \(url). \(limitMsg)",
                    level: .warning,
                    category: .network
                )
                throw NSError(domain: "EasyRSSNetwork", code: 429, userInfo: [NSLocalizedDescriptionKey: limitMsg])
            }

            responseETag = httpResponse.value(forHTTPHeaderField: "ETag") ?? httpResponse.value(forHTTPHeaderField: "Etag")
            responseLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

            if (200...299).contains(httpResponse.statusCode) {
                await AppLogger.shared.log(
                    "HTTP \(httpResponse.statusCode) (\(data.count) bytes, \(elapsed)) from \(feedURL.host ?? url)",
                    level: .info,
                    category: .network
                )
            } else {
                await AppLogger.shared.log(
                    "HTTP \(httpResponse.statusCode) returned for \(url)",
                    level: .warning,
                    category: .network,
                    details: "Status code: \(httpResponse.statusCode)"
                )
            }
        }

        let parseStart = CFAbsoluteTimeGetCurrent()
        let parser = RSSParser(feedId: feedId)
        let result = parser.parse(data: data)
        let parseElapsed = String(format: "%.3fs", CFAbsoluteTimeGetCurrent() - parseStart)

        if let result {
            await AppLogger.shared.log(
                "Parsed \"\(result.title)\" - \(result.items.count) items in \(parseElapsed)",
                level: .info,
                category: .parser,
                details: "Feed ID: \(feedId)"
            )
            return ParseResult(
                title: result.title,
                description: result.description,
                imageURL: result.imageURL,
                items: result.items,
                etag: responseETag ?? etag,
                lastModified: responseLastModified ?? lastModified,
                isNotModified: false
            )
        } else {
            await AppLogger.shared.log(
                "Failed to parse XML from \(url)",
                level: .error,
                category: .parser,
                details: "Data size: \(data.count) bytes"
            )
            return nil
        }
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let lower = elementName.lowercased()
        currentElement = lower

        switch lower {
        case "feed":
            isAtomFeed = true
            isInsideChannel = true

        case "channel":
            isInsideChannel = true

        case "item", "entry":
            isInsideItem = true
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentPubDate = ""
            currentAuthor = ""
            currentContent = ""
            currentAudioURL = nil
            currentAudioDuration = ""
            currentAudioType = nil
            currentAudioLength = nil

        case "image":
            if !isInsideItem {
                isInsideImage = true
            }

        case "enclosure":
            if isInsideItem {
                if let url = attributeDict["url"] {
                    let type = attributeDict["type"]?.lowercased() ?? ""
                    let cleanURL = url.components(separatedBy: "?").first?.lowercased() ?? url.lowercased()
                    let isAudioType = type.contains("audio")
                    let isAudioExtension = cleanURL.hasSuffix(".mp3") || cleanURL.hasSuffix(".m4a") ||
                                           cleanURL.hasSuffix(".aac") || cleanURL.hasSuffix(".wav") ||
                                           cleanURL.hasSuffix(".ogg") || cleanURL.hasSuffix(".oga") ||
                                           cleanURL.hasSuffix(".flac") || cleanURL.hasSuffix(".opus") ||
                                           cleanURL.hasSuffix(".m4b")
                    let isImageOrDoc = type.contains("image") || type.contains("video") || type.contains("text") ||
                                       cleanURL.hasSuffix(".jpg") || cleanURL.hasSuffix(".jpeg") ||
                                       cleanURL.hasSuffix(".png") || cleanURL.hasSuffix(".webp") ||
                                       cleanURL.hasSuffix(".gif")

                    if (isAudioType || isAudioExtension) && !isImageOrDoc {
                        currentAudioURL = url
                        currentAudioType = attributeDict["type"]
                        if let lengthStr = attributeDict["length"], let length = Int64(lengthStr) {
                            currentAudioLength = length
                        }
                    }
                }
            }

        case "link":
            if isAtomFeed {
                if let href = attributeDict["href"] {
                    let rel = (attributeDict["rel"] ?? "alternate").lowercased()
                    let type = attributeDict["type"]?.lowercased() ?? ""
                    let cleanHref = href.components(separatedBy: "?").first?.lowercased() ?? href.lowercased()
                    let isAudioExtension = cleanHref.hasSuffix(".mp3") || cleanHref.hasSuffix(".m4a") ||
                                           cleanHref.hasSuffix(".aac") || cleanHref.hasSuffix(".wav") ||
                                           cleanHref.hasSuffix(".ogg") || cleanHref.hasSuffix(".oga") ||
                                           cleanHref.hasSuffix(".flac") || cleanHref.hasSuffix(".opus") ||
                                           cleanHref.hasSuffix(".m4b")
                    let isImageOrDoc = type.contains("image") || type.contains("video") || type.contains("text") ||
                                       cleanHref.hasSuffix(".jpg") || cleanHref.hasSuffix(".jpeg") ||
                                       cleanHref.hasSuffix(".png") || cleanHref.hasSuffix(".webp") ||
                                       cleanHref.hasSuffix(".gif")

                    if rel == "enclosure" || type.contains("audio") {
                        if isInsideItem && (type.contains("audio") || isAudioExtension) && !isImageOrDoc {
                            currentAudioURL = href
                            currentAudioType = attributeDict["type"]
                            if let lengthStr = attributeDict["length"], let length = Int64(lengthStr) {
                                currentAudioLength = length
                            }
                        }
                    } else if rel == "alternate" || rel.isEmpty {
                        if isInsideItem {
                            currentLink = href
                        }
                    }
                }
            }

        case "itunes:image":
            if let href = attributeDict["href"] {
                if !isInsideItem && feedImageURL == nil {
                    feedImageURL = href
                }
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string

        switch currentElement {
        case "title":
            if isInsideItem {
                currentTitle += trimmed
            } else if isInsideChannel && !isInsideImage {
                feedTitle += trimmed
            }

        case "link":
            if !isAtomFeed {
                if isInsideItem {
                    currentLink += trimmed
                }
            }

        case "description", "subtitle", "summary", "media:description":
            if isInsideItem {
                currentDescription += trimmed
            } else if isInsideChannel {
                feedDescription += trimmed
            }

        case "pubdate", "published", "updated", "dc:date":
            if isInsideItem {
                currentPubDate += trimmed
            }

        case "author", "dc:creator", "name":
            if isInsideItem {
                currentAuthor += trimmed
            }

        case "content:encoded", "content":
            if isInsideItem {
                currentContent += trimmed
            }

        case "url":
            if isInsideImage && !isInsideItem {
                feedImageURL = (feedImageURL ?? "") + trimmed
            }

        case "itunes:duration", "duration":
            if isInsideItem {
                currentAudioDuration += trimmed
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) ?? String(data: CDATABlock, encoding: .isoLatin1) {
            self.parser(parser, foundCharacters: string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let lower = elementName.lowercased()
        switch lower {
        case "item", "entry":
            let cleanTitle = currentTitle.strippingHTML()
            let cleanAuthor = currentAuthor.strippingHTML()
            let cleanDesc = currentDescription.decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanContent = currentContent.decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines)
            let precomputedSnippet = cleanDesc.strippingHTML()
            let itemLink = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)

            // Offload rich HTML to disk cache immediately for Reader Mode only if substantive full content exists.
            // Do NOT save short teaser descriptions (cleanDesc) as they poison the cache with 150-char snippets.
            if !cleanContent.isEmpty && cleanContent.count > 600 && !itemLink.isEmpty {
                Task { @MainActor in
                    ReaderModeExtractor.shared.saveToCache(urlString: itemLink, content: cleanContent, storeInMemory: false)
                }
            }

            let item = FeedItem(
                feedId: feedId,
                title: cleanTitle.isEmpty ? itemLink : cleanTitle,
                link: itemLink,
                itemDescription: precomputedSnippet,
                pubDate: parseDate(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)),
                author: cleanAuthor.isEmpty ? nil : cleanAuthor,
                isRead: false,
                content: nil,
                snippet: precomputedSnippet,
                audioURL: currentAudioURL,
                audioDuration: currentAudioDuration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : currentAudioDuration.trimmingCharacters(in: .whitespacesAndNewlines),
                audioType: currentAudioType,
                audioLength: currentAudioLength
            )
            items.append(item)
            isInsideItem = false

        case "channel", "feed":
            feedTitle = feedTitle.strippingHTML()
            feedDescription = feedDescription.strippingHTML()
            isInsideChannel = false

        case "image":
            isInsideImage = false

        default:
            break
        }

        currentElement = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        let line = parser.lineNumber
        let col = parser.columnNumber
        let errDesc = parseError.localizedDescription
        Task { @MainActor in
            AppLogger.shared.log(
                "XMLParser warning/error at line \(line), col \(col): \(errDesc)",
                level: .warning,
                category: .parser
            )
        }
    }

    // MARK: - Date Parsing (Cached & High Performance)

    private static let rfc822Formatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yy HH:mm:ss Z",
        ]
        return formats.map { format in
            let df = DateFormatter()
            df.dateFormat = format
            df.locale = Locale(identifier: "en_US_POSIX")
            return df
        }
    }()

    private static let isoDateCustomFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd",
        ]
        return formats.map { format in
            let df = DateFormatter()
            df.dateFormat = format
            return df
        }
    }()

    private nonisolated(unsafe) static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let isoFormatterStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseDate(_ string: String) -> Date? {
        if string.isEmpty { return nil }

        // Fast-path heuristic: inspect leading character
        let startsWithNumber = string.first?.isNumber == true

        if startsWithNumber {
            if let date = Self.isoFormatterWithFractional.date(from: string) { return date }
            if let date = Self.isoFormatterStandard.date(from: string) { return date }
            for df in Self.isoDateCustomFormatters {
                if let date = df.date(from: string) { return date }
            }
            // Fallback to RFC822 if numeric day starts e.g. "06 Sep 2026"
            for df in Self.rfc822Formatters {
                if let date = df.date(from: string) { return date }
            }
        } else {
            for df in Self.rfc822Formatters {
                if let date = df.date(from: string) { return date }
            }
            if let date = Self.isoFormatterWithFractional.date(from: string) { return date }
            if let date = Self.isoFormatterStandard.date(from: string) { return date }
        }

        return nil
    }
}
