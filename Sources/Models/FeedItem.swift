import Foundation

struct FeedItem: Codable, Identifiable, Hashable {
    let id: UUID
    let feedId: UUID
    var title: String
    var link: String
    var itemDescription: String
    var pubDate: Date?
    var author: String?
    var isRead: Bool
    var content: String?
    var isBookmarked: Bool

    init(
        id: UUID = UUID(),
        feedId: UUID,
        title: String,
        link: String,
        itemDescription: String = "",
        pubDate: Date? = nil,
        author: String? = nil,
        isRead: Bool = false,
        content: String? = nil,
        isBookmarked: Bool = false
    ) {
        self.id = id
        self.feedId = feedId
        self.title = title
        self.link = link
        self.itemDescription = itemDescription
        self.pubDate = pubDate
        self.author = author
        self.isRead = isRead
        self.content = content
        self.isBookmarked = isBookmarked
    }

    // Backward-compatible decoding: isBookmarked may not exist in older data
    enum CodingKeys: String, CodingKey {
        case id, feedId, title, link, itemDescription, pubDate, author, isRead, content, isBookmarked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        feedId = try container.decode(UUID.self, forKey: .feedId)
        title = try container.decode(String.self, forKey: .title)
        link = try container.decode(String.self, forKey: .link)
        itemDescription = try container.decode(String.self, forKey: .itemDescription)
        pubDate = try container.decodeIfPresent(Date.self, forKey: .pubDate)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        content = try container.decodeIfPresent(String.self, forKey: .content)
        isBookmarked = try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
    }
}
