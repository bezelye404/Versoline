import Foundation

struct FeedItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID   // `var` only so a load can repair duplicated identities
    let feedId: UUID
    var title: String
    var link: String
    var itemDescription: String
    var pubDate: Date?
    var author: String?
    var isRead: Bool
    var content: String?
    var isBookmarked: Bool
    var category: String?

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

    /// Reading time computed once at ingest from the full body (see `estimatedReadingMinutes`).
    var readingMinutes: Int?

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

    // MARK: - YouTube Video Metadata (Computed / 0 Byte Overhead)

    var youtubeVideoID: String? {
        guard let url = URL(string: link), let host = url.host?.lowercased() else { return nil }
        if host.contains("youtube.com") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let v = components.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                    return v
                }
                let pathComponents = url.pathComponents
                if pathComponents.count >= 3 {
                    if pathComponents[1] == "embed" || pathComponents[1] == "shorts" || pathComponents[1] == "v" {
                        return pathComponents[2]
                    }
                }
            }
        } else if host.contains("youtu.be") {
            let pathComponents = url.pathComponents
            if pathComponents.count >= 2 && !pathComponents[1].isEmpty {
                return pathComponents[1]
            }
        }
        return nil
    }

    var isYouTube: Bool {
        youtubeVideoID != nil
    }

    var youtubeThumbnailURL: URL? {
        guard let id = youtubeVideoID else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
    }

    // MARK: - Smart Streams Categorization (0 Byte Memory Overhead)

    /// Reading time in minutes. Prefers the value computed at ingest from the full article body
    /// (`readingMinutes`), because the body itself is not kept on the item and `itemDescription`
    /// is only a short snippet.
    var estimatedReadingMinutes: Int {
        readingMinutes ?? Self.estimateReadingMinutes(from: content ?? itemDescription)
    }

    /// 200 words per minute, never less than one minute.
    ///
    /// Single pass over the UTF-8 bytes with no intermediate strings: HTML tags and entities are
    /// skipped instead of stripped, so a large article body costs no extra memory. This runs for
    /// every parsed item on every refresh, which is why it avoids `strippingHTML()`.
    static func estimateReadingMinutes(from text: String) -> Int {
        var text = text
        let words = text.withUTF8 { bytes -> Int in
            var count = 0
            var inWord = false
            var i = 0
            let n = bytes.count
            while i < n {
                let b = bytes[i]
                var isWordByte = true

                if b == UInt8(ascii: "<"), i + 1 < n, Self.startsTag(bytes[i + 1]) {
                    // Skip the whole tag; it separates words like whitespace does.
                    while i < n, bytes[i] != UInt8(ascii: ">") { i += 1 }
                    isWordByte = false
                } else if b == UInt8(ascii: "&"), let end = Self.entityEnd(bytes, from: i) {
                    i = end
                    isWordByte = false
                } else if b == 0xA0, i > 0, bytes[i - 1] == 0xC2 {
                    isWordByte = false // U+00A0 no-break space
                } else if b < 0x80 {
                    isWordByte = !(Self.isASCIISpace(b) || Self.isASCIIPunctuation(b))
                }

                if isWordByte {
                    if !inWord { count += 1; inWord = true }
                } else {
                    inWord = false
                }
                i += 1
            }
            return count
        }
        return max(1, Int((Double(words) / 200.0).rounded(.up)))
    }

    private static func startsTag(_ b: UInt8) -> Bool {
        (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z")) || (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
            || b == UInt8(ascii: "/") || b == UInt8(ascii: "!")
    }

    /// Index of the `;` that closes an entity like `&nbsp;` / `&#8217;` starting at `start`, if any.
    private static func entityEnd(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
        var j = start + 1
        let limit = min(bytes.count, start + 10)
        while j < limit {
            let c = bytes[j]
            if c == UInt8(ascii: ";") { return j > start + 1 ? j : nil }
            let isAlnum = (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z")) || (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
                || (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")) || c == UInt8(ascii: "#")
            if !isAlnum { return nil }
            j += 1
        }
        return nil
    }

    private static func isASCIISpace(_ b: UInt8) -> Bool {
        b == 0x20 || (b >= 0x09 && b <= 0x0D)
    }

    private static func isASCIIPunctuation(_ b: UInt8) -> Bool {
        (b >= 0x21 && b <= 0x2F) || (b >= 0x3A && b <= 0x40) || (b >= 0x5B && b <= 0x60) || (b >= 0x7B && b <= 0x7E)
    }

    var isQuickRead: Bool {
        !isPodcast && estimatedReadingMinutes <= 3
    }

    var isLongRead: Bool {
        !isPodcast && estimatedReadingMinutes >= 7
    }

    var isMedia: Bool {
        isYouTube || isPodcast
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
        category: String? = nil,
        audioURL: String? = nil,
        audioDuration: String? = nil,
        audioType: String? = nil,
        audioLength: Int64? = nil,
        playbackPosition: Double = 0.0,
        isFinished: Bool = false,
        readingMinutes: Int? = nil
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
        self.category = category
        self.audioURL = audioURL
        self.audioDuration = audioDuration
        self.audioType = audioType
        self.audioLength = audioLength
        self.playbackPosition = playbackPosition
        self.isFinished = isFinished
        self.readingMinutes = readingMinutes
    }

    // Backward-compatible decoding and optimized single-field encoding
    enum CodingKeys: String, CodingKey {
        case id, feedId, title, link, itemDescription, pubDate, author, isRead, content, isBookmarked, snippet, category
        case audioURL, audioDuration, audioType, audioLength, playbackPosition, isFinished, readingMinutes
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
        category = try container.decodeIfPresent(String.self, forKey: .category)
        audioURL = try container.decodeIfPresent(String.self, forKey: .audioURL)
        audioDuration = try container.decodeIfPresent(String.self, forKey: .audioDuration)
        audioType = try container.decodeIfPresent(String.self, forKey: .audioType)
        audioLength = try container.decodeIfPresent(Int64.self, forKey: .audioLength)
        playbackPosition = try container.decodeIfPresent(Double.self, forKey: .playbackPosition) ?? 0.0
        isFinished = try container.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
        readingMinutes = try container.decodeIfPresent(Int.self, forKey: .readingMinutes)
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
        try container.encodeIfPresent(category, forKey: .category)
        // snippet is omitted from encoding: saves ~35% JSON disk space and avoids redundant heap strings
        try container.encodeIfPresent(audioURL, forKey: .audioURL)
        try container.encodeIfPresent(audioDuration, forKey: .audioDuration)
        try container.encodeIfPresent(audioType, forKey: .audioType)
        try container.encodeIfPresent(audioLength, forKey: .audioLength)
        try container.encode(playbackPosition, forKey: .playbackPosition)
        try container.encode(isFinished, forKey: .isFinished)
        try container.encodeIfPresent(readingMinutes, forKey: .readingMinutes)
    }
}
