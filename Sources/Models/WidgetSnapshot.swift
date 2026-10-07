import Foundation

/// What the app hands to the widget: the unread count and a few headlines, as one small JSON file in the app
/// group container. The widget never talks to the network and never reads the library itself.
/// This file is compiled into both the app and the widget extension, so it must not use any other app type.
struct WidgetSnapshot: Codable, Equatable {

    struct Headline: Codable, Equatable, Identifiable {
        let title: String
        let feedTitle: String
        let link: String
        let date: Date?
        let isTopStory: Bool

        var id: String { link }
    }

    static let maxHeadlines = 8
    static let urlScheme = "versoline"
    private static let fileName = "widget-snapshot.json"

    /// When the content last changed; unchanged content is not rewritten, so this is not "last checked".
    var generatedAt: Date
    var unreadCount: Int
    var headlines: [Headline]
    /// The app's color palette (`AppColorPalette` raw value) when the snapshot was written.
    var palette: String

    init(generatedAt: Date, unreadCount: Int, headlines: [Headline], palette: String = "slate") {
        self.generatedAt = generatedAt
        self.unreadCount = unreadCount
        self.headlines = headlines
        self.palette = palette
    }

    /// Files written by an earlier version have no palette; they still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        unreadCount = try container.decode(Int.self, forKey: .unreadCount)
        headlines = try container.decode([Headline].self, forKey: .headlines)
        palette = try container.decodeIfPresent(String.self, forKey: .palette) ?? "slate"
    }

    static let placeholder = WidgetSnapshot(
        generatedAt: Date(),
        unreadCount: 12,
        headlines: [
            Headline(title: "A story told by several of your feeds", feedTitle: "Your feeds", link: "https://example.com/1", date: Date(), isTopStory: true),
            Headline(title: "Another headline from a feed you follow", feedTitle: "Your feeds", link: "https://example.com/2", date: Date(), isTopStory: false),
            Headline(title: "A third headline waiting to be read", feedTitle: "Your feeds", link: "https://example.com/3", date: Date(), isTopStory: false),
        ]
    )

    // MARK: Storage

    /// The folder the app writes to and the widget reads from. It sits in the user's real Library, next to (not
    /// inside) the app's sandbox container, and both targets are allowed to reach it by a sandbox entitlement named
    /// after it. An app group would do the same, but macOS asks about group containers every time an ad hoc signed
    /// app opens one. The folder's name comes from each target's Info.plist (it differs for the dev build).
    static var sharedDirectory: URL? {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "WidgetDataDirectory") as? String,
              let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir
        else { return nil }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Library/Application Support/\(name)", isDirectory: true)
    }

    static func fileURL(directory: URL? = nil) -> URL? {
        (directory ?? sharedDirectory)?.appendingPathComponent(fileName)
    }

    /// Deletes the snapshot file; true when there was one.
    @discardableResult
    static func remove(directory: URL? = nil) -> Bool {
        guard let url = fileURL(directory: directory), FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    static func load(directory: URL? = nil) -> WidgetSnapshot? {
        guard let url = fileURL(directory: directory), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Writes the snapshot and reports whether the file changed (`generatedAt` is ignored when comparing).
    @discardableResult
    func write(directory: URL? = nil) -> Bool {
        guard let url = Self.fileURL(directory: directory) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing = Self.load(directory: directory), existing.sameContent(as: self) { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    func sameContent(as other: WidgetSnapshot) -> Bool {
        unreadCount == other.unreadCount && headlines == other.headlines && palette == other.palette
    }

    // MARK: Links

    /// The link a headline opens: the app, showing that article.
    static func openURL(forArticleLink link: String) -> URL? {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "link", value: link)]
        return components.url
    }

    /// The article link inside a `versoline://open?link=...` URL.
    static func articleLink(from url: URL) -> String? {
        guard url.scheme == urlScheme, url.host == "open",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        return items.first(where: { $0.name == "link" })?.value
    }
}
