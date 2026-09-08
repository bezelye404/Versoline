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

    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        description: String = "",
        imageURL: String? = nil,
        lastUpdated: Date? = nil,
        folderId: UUID? = nil,
        etag: String? = nil,
        lastModifiedHeader: String? = nil
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
    }
}
