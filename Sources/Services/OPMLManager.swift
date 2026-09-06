import Foundation

final class OPMLManager: NSObject, XMLParserDelegate, @unchecked Sendable {

    struct OPMLFeed {
        let title: String
        let xmlUrl: String
        let folderName: String?
    }

    private var feeds: [OPMLFeed] = []
    private var currentFolder: String?
    private var outlineNesting: Int = 0

    // MARK: - Parse OPML

    func parse(data: Data) -> [OPMLFeed] {
        feeds = []
        currentFolder = nil
        outlineNesting = 0

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        parser.parse()

        return feeds
    }

    // MARK: - Generate OPML

    static func generate(feeds: [Feed], folders: [Folder]) -> String {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<opml version=\"2.0\">")
        lines.append("<head><title>easyRSS Subscriptions</title></head>")
        lines.append("<body>")

        // Feeds grouped by folder
        for folder in folders {
            let folderFeeds = feeds.filter { $0.folderId == folder.id }
            guard !folderFeeds.isEmpty else { continue }

            lines.append("  <outline text=\"\(escapeXML(folder.name))\" title=\"\(escapeXML(folder.name))\">")
            for feed in folderFeeds {
                lines.append("    <outline type=\"rss\" text=\"\(escapeXML(feed.title))\" title=\"\(escapeXML(feed.title))\" xmlUrl=\"\(escapeXML(feed.url))\" />")
            }
            lines.append("  </outline>")
        }

        // Uncategorized feeds
        let uncategorized = feeds.filter { $0.folderId == nil }
        for feed in uncategorized {
            lines.append("  <outline type=\"rss\" text=\"\(escapeXML(feed.title))\" title=\"\(escapeXML(feed.title))\" xmlUrl=\"\(escapeXML(feed.url))\" />")
        }

        lines.append("</body>")
        lines.append("</opml>")

        return lines.joined(separator: "\n")
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }

        outlineNesting += 1

        // Case-insensitive attribute lookup
        let xmlUrl = attributeDict["xmlUrl"] ?? attributeDict["xmlurl"] ?? attributeDict["XMLURL"]

        if let xmlUrl, !xmlUrl.isEmpty {
            // This is a feed
            let title = attributeDict["text"] ?? attributeDict["title"] ?? xmlUrl
            feeds.append(OPMLFeed(title: title, xmlUrl: xmlUrl, folderName: currentFolder))
        } else if outlineNesting == 1 {
            // Top-level outline without xmlUrl → folder
            currentFolder = attributeDict["text"] ?? attributeDict["title"]
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() == "outline" else { return }

        if outlineNesting == 1 {
            currentFolder = nil
        }
        outlineNesting -= 1
    }

    // MARK: - Helpers

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
