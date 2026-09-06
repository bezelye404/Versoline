import Foundation

struct PodcastSearchResult: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let author: String
    let feedURL: String
    let artworkURL: String?
    let genre: String?
    let trackCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "collectionId"
        case title = "collectionName"
        case author = "artistName"
        case feedURL = "feedUrl"
        case artwork100 = "artworkUrl100"
        case artwork600 = "artworkUrl600"
        case genre = "primaryGenreName"
        case trackCount
    }

    init(
        id: Int,
        title: String,
        author: String,
        feedURL: String,
        artworkURL: String? = nil,
        genre: String? = nil,
        trackCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.genre = genre
        self.trackCount = trackCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        self.feedURL = try container.decodeIfPresent(String.self, forKey: .feedURL) ?? ""
        let art600 = try container.decodeIfPresent(String.self, forKey: .artwork600)
        let art100 = try container.decodeIfPresent(String.self, forKey: .artwork100)
        self.artworkURL = art600 ?? art100
        self.genre = try container.decodeIfPresent(String.self, forKey: .genre)
        self.trackCount = try container.decodeIfPresent(Int.self, forKey: .trackCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(feedURL, forKey: .feedURL)
        try container.encodeIfPresent(artworkURL, forKey: .artwork600)
        try container.encodeIfPresent(genre, forKey: .genre)
        try container.encodeIfPresent(trackCount, forKey: .trackCount)
    }

    var formattedEpisodesCount: String? {
        guard let count = trackCount, count > 0 else { return nil }
        return String(format: String(localized: "%d episodes"), count)
    }
}

struct iTunesSearchResponse: Codable {
    let resultCount: Int
    let results: [PodcastSearchResult]
}
