import Foundation

struct Feed: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var url: String
    var description: String
    var imageURL: String?
    var lastUpdated: Date?
    var folderId: UUID?
    var etag: String?
    var lastModifiedHeader: String?
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        description: String = "",
        imageURL: String? = nil,
        lastUpdated: Date? = nil,
        folderId: UUID? = nil,
        etag: String? = nil,
        lastModifiedHeader: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.description = description
        self.imageURL = imageURL
        self.lastUpdated = lastUpdated
        self.folderId = folderId
        self.etag = etag
        self.lastModifiedHeader = lastModifiedHeader
        self.isPinned = isPinned
    }

    enum CodingKeys: String, CodingKey {
        case id, title, url, description, imageURL, lastUpdated, folderId, etag, lastModifiedHeader, isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(String.self, forKey: .url)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
        folderId = try container.decodeIfPresent(UUID.self, forKey: .folderId)
        etag = try container.decodeIfPresent(String.self, forKey: .etag)
        lastModifiedHeader = try container.decodeIfPresent(String.self, forKey: .lastModifiedHeader)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}
