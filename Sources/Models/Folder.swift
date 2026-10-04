import Foundation

struct Folder: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var keywords: [String]?
    /// Last user edit (created, renamed). Drives nearby-sync conflict resolution; see `Feed.updatedAt`.
    var updatedAt: Date?

    var isSmartFolder: Bool {
        !(keywords ?? []).isEmpty
    }

    init(id: UUID = UUID(), name: String, keywords: [String]? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.keywords = keywords
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, keywords, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.keywords = try container.decodeIfPresent([String].self, forKey: .keywords)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}
