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

    // Atom support
    private var isAtomFeed: Bool = false

    // URLSession with custom User-Agent and timeout
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
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
    }

    func parse(data: Data) -> ParseResult? {
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

    static func fetchAndParse(url: String, feedId: UUID) async throws -> ParseResult? {
        guard let feedURL = URL(string: url) else {
            await AppLogger.shared.log("Invalid feed URL: \(url)", level: .error, category: .network)
            throw URLError(.badURL)
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        await AppLogger.shared.log("Fetching feed: \(feedURL.host ?? url)", level: .info, category: .network, details: url)

        let (data, response) = try await session.data(from: feedURL)

        if let httpResponse = response as? HTTPURLResponse {
            let elapsed = String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - startTime)
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
        } else {
            await AppLogger.shared.log(
                "Failed to parse XML from \(url)",
                level: .error,
                category: .parser,
                details: "Data size: \(data.count) bytes"
            )
        }

        return result
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName

        switch elementName.lowercased() {
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

        case "image":
            if !isInsideItem {
                isInsideImage = true
            }

        case "link":
            if isAtomFeed {
                if let href = attributeDict["href"] {
                    let rel = attributeDict["rel"] ?? "alternate"
                    if rel == "alternate" || rel.isEmpty {
                        if isInsideItem {
                            currentLink = href
                        }
                    }
                }
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string

        switch currentElement.lowercased() {
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

        case "description", "subtitle", "summary":
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

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName.lowercased() {
        case "item", "entry":
            let item = FeedItem(
                feedId: feedId,
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                link: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                itemDescription: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate: parseDate(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)),
                author: currentAuthor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : currentAuthor.trimmingCharacters(in: .whitespacesAndNewlines),
                isRead: false,
                content: currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            items.append(item)
            isInsideItem = false

        case "channel", "feed":
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

    private static let cachedDateFormatters: [DateFormatter] = {
        let formats: [(String, Bool)] = [
            // RSS 2.0 (RFC 822)
            ("EEE, dd MMM yyyy HH:mm:ss Z", true),
            ("EEE, dd MMM yyyy HH:mm:ss zzz", true),
            ("dd MMM yyyy HH:mm:ss Z", true),
            ("EEE, dd MMM yy HH:mm:ss Z", true),
            // Atom (ISO 8601)
            ("yyyy-MM-dd'T'HH:mm:ssZ", false),
            ("yyyy-MM-dd'T'HH:mm:ss.SSSZ", false),
            ("yyyy-MM-dd'T'HH:mm:ssXXXXX", false),
            ("yyyy-MM-dd", false),
        ]
        return formats.map { format, isEnglish in
            let df = DateFormatter()
            df.dateFormat = format
            if isEnglish {
                df.locale = Locale(identifier: "en_US_POSIX")
            }
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

        for formatter in Self.cachedDateFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }

        if let date = Self.isoFormatterWithFractional.date(from: string) {
            return date
        }
        return Self.isoFormatterStandard.date(from: string)
    }
}
