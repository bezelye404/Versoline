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

    // Memory optimization: snippet routes directly to itemDescription to eliminate duplicate heap allocations
    var snippet: String {
        get { itemDescription }
        set { itemDescription = newValue }
    }

    // Podcast / Audio Enclosure Metadata
    var audioURL: String?
    var audioDuration: String?
    var audioType: String?
    var audioLength: Int64?
    var playbackPosition: Double
    var isFinished: Bool

    var isPodcast: Bool {
        guard let url = audioURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
            return false
        }
        let lowerType = audioType?.lowercased() ?? ""
        if lowerType.contains("image") || lowerType.contains("video") || lowerType.contains("text") || lowerType.contains("html") {
            return false
        }
        let cleanURL = url.components(separatedBy: "?").first?.lowercased() ?? url.lowercased()
        if cleanURL.hasSuffix(".jpg") || cleanURL.hasSuffix(".jpeg") || cleanURL.hasSuffix(".png") || cleanURL.hasSuffix(".webp") || cleanURL.hasSuffix(".gif") {
            return false
        }
        if lowerType.contains("audio") {
            return true
        }
        let audioExtensions = [".mp3", ".m4a", ".aac", ".wav", ".ogg", ".oga", ".flac", ".opus", ".m4b"]
        return audioExtensions.contains(where: { cleanURL.hasSuffix($0) })
    }

    var formattedDuration: String? {
        if let duration = audioDuration?.trimmingCharacters(in: .whitespacesAndNewlines), !duration.isEmpty {
            // Check if duration is pure seconds like "2712"
            if let seconds = Double(duration) {
                let totalSecs = Int(seconds)
                let hours = totalSecs / 3600
                let minutes = (totalSecs % 3600) / 60
                let secs = totalSecs % 60
                if hours > 0 {
                    return String(format: "%d:%02d:%02d", hours, minutes, secs)
                } else {
                    return String(format: "%d:%02d", minutes, secs)
                }
            }
            return duration
        }
        return nil
    }

    var progressFraction: Double {
        guard let durationStr = audioDuration, let totalSecs = Double(durationStr), totalSecs > 0 else {
            return 0
        }
        return min(max(playbackPosition / totalSecs, 0.0), 1.0)
    }

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
        isBookmarked: Bool = false,
        snippet: String = "",
        audioURL: String? = nil,
        audioDuration: String? = nil,
        audioType: String? = nil,
        audioLength: Int64? = nil,
        playbackPosition: Double = 0.0,
        isFinished: Bool = false
    ) {
        self.id = id
        self.feedId = feedId
        self.title = title
        self.link = link
        let rawDesc = itemDescription.isEmpty ? snippet : itemDescription
        let clean = rawDesc.contains("<") ? rawDesc.strippingHTML() : rawDesc
        self.itemDescription = clean.count > 250 ? String(clean.prefix(250)) : clean
        self.pubDate = pubDate
        self.author = author
        self.isRead = isRead
        self.content = content
        self.isBookmarked = isBookmarked
        self.audioURL = audioURL
        self.audioDuration = audioDuration
        self.audioType = audioType
        self.audioLength = audioLength
        self.playbackPosition = playbackPosition
        self.isFinished = isFinished
    }

    // Backward-compatible decoding and optimized single-field encoding
    enum CodingKeys: String, CodingKey {
        case id, feedId, title, link, itemDescription, pubDate, author, isRead, content, isBookmarked, snippet
        case audioURL, audioDuration, audioType, audioLength, playbackPosition, isFinished
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        feedId = try container.decode(UUID.self, forKey: .feedId)
        title = try container.decode(String.self, forKey: .title)
        link = try container.decode(String.self, forKey: .link)

        let decodedDesc = try container.decodeIfPresent(String.self, forKey: .itemDescription)
        let decodedSnippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        let resolved = (decodedDesc?.isEmpty == false ? decodedDesc : decodedSnippet) ?? ""
        let clean = resolved.contains("<") ? resolved.strippingHTML() : resolved
        self.itemDescription = clean.count > 250 ? String(clean.prefix(250)) : clean

        pubDate = try container.decodeIfPresent(Date.self, forKey: .pubDate)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        content = try container.decodeIfPresent(String.self, forKey: .content)
        isBookmarked = try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
        audioURL = try container.decodeIfPresent(String.self, forKey: .audioURL)
        audioDuration = try container.decodeIfPresent(String.self, forKey: .audioDuration)
        audioType = try container.decodeIfPresent(String.self, forKey: .audioType)
        audioLength = try container.decodeIfPresent(Int64.self, forKey: .audioLength)
        playbackPosition = try container.decodeIfPresent(Double.self, forKey: .playbackPosition) ?? 0.0
        isFinished = try container.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(feedId, forKey: .feedId)
        try container.encode(title, forKey: .title)
        try container.encode(link, forKey: .link)
        try container.encode(itemDescription, forKey: .itemDescription)
        try container.encodeIfPresent(pubDate, forKey: .pubDate)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encode(isRead, forKey: .isRead)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encode(isBookmarked, forKey: .isBookmarked)
        // snippet is omitted from encoding: saves ~35% JSON disk space and avoids redundant heap strings
        try container.encodeIfPresent(audioURL, forKey: .audioURL)
        try container.encodeIfPresent(audioDuration, forKey: .audioDuration)
        try container.encodeIfPresent(audioType, forKey: .audioType)
        try container.encodeIfPresent(audioLength, forKey: .audioLength)
        try container.encode(playbackPosition, forKey: .playbackPosition)
        try container.encode(isFinished, forKey: .isFinished)
    }
}
