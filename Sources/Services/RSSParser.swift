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
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: feedURL)
        let parser = RSSParser(feedId: feedId)
        return parser.parse(data: data)
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
            // Atom feed
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
            // Atom feeds use <link href="..." /> attribute
            if isAtomFeed {
                if let href = attributeDict["href"] {
                    let rel = attributeDict["rel"] ?? "alternate"
                    if rel == "alternate" || rel == "" {
                        if isInsideItem {
                            currentLink = href
                        }
                    }
                }
            }

        case "enclosure", "media:content":
            // Could capture media URL if needed
            break

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
        // Silently handle parse errors — many feeds have minor issues
    }

    // MARK: - Date Parsing

    private func parseDate(_ string: String) -> Date? {
        if string.isEmpty { return nil }

        let formatters: [(String, Bool)] = [
            // RSS 2.0 (RFC 822)
            ("EEE, dd MMM yyyy HH:mm:ss Z", true),
            ("EEE, dd MMM yyyy HH:mm:ss zzz", true),
            ("dd MMM yyyy HH:mm:ss Z", true),
            // Atom (ISO 8601)
            ("yyyy-MM-dd'T'HH:mm:ssZ", false),
            ("yyyy-MM-dd'T'HH:mm:ss.SSSZ", false),
            ("yyyy-MM-dd'T'HH:mm:ssXXXXX", false),
            ("yyyy-MM-dd", false),
        ]

        for (format, isEnglish) in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if isEnglish {
                formatter.locale = Locale(identifier: "en_US_POSIX")
            }
            if let date = formatter.date(from: string) {
                return date
            }
        }

        // Try ISO8601DateFormatter as fallback
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: string)
    }
}
