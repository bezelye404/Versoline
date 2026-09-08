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
    var snippet: String

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
        self.itemDescription = itemDescription
        self.pubDate = pubDate
        self.author = author
        self.isRead = isRead
        self.content = content
        self.isBookmarked = isBookmarked
        let cleanSnippet = snippet.isEmpty ? itemDescription.strippingHTML() : snippet
        self.snippet = cleanSnippet.count > 250 ? String(cleanSnippet.prefix(250)) : cleanSnippet
        self.audioURL = audioURL
        self.audioDuration = audioDuration
        self.audioType = audioType
        self.audioLength = audioLength
        self.playbackPosition = playbackPosition
        self.isFinished = isFinished
    }

    // Backward-compatible decoding
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
        itemDescription = try container.decode(String.self, forKey: .itemDescription)
        pubDate = try container.decodeIfPresent(Date.self, forKey: .pubDate)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        content = try container.decodeIfPresent(String.self, forKey: .content)
        isBookmarked = try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
        if let decodedSnippet = try container.decodeIfPresent(String.self, forKey: .snippet), !decodedSnippet.isEmpty {
            self.snippet = decodedSnippet.count > 250 ? String(decodedSnippet.prefix(250)) : decodedSnippet
        } else {
            let clean = itemDescription.strippingHTML()
            self.snippet = clean.count > 250 ? String(clean.prefix(250)) : clean
        }
        audioURL = try container.decodeIfPresent(String.self, forKey: .audioURL)
        audioDuration = try container.decodeIfPresent(String.self, forKey: .audioDuration)
        audioType = try container.decodeIfPresent(String.self, forKey: .audioType)
        audioLength = try container.decodeIfPresent(Int64.self, forKey: .audioLength)
        playbackPosition = try container.decodeIfPresent(Double.self, forKey: .playbackPosition) ?? 0.0
        isFinished = try container.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
    }
}
