import Foundation

// MARK: - Enums

enum RedditSort: String, CaseIterable, Identifiable, Sendable {
    case hot = "hot"
    case new = "new"
    case top = "top"
    case rising = "rising"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hot: return String(localized: "Hot")
        case .new: return String(localized: "New")
        case .top: return String(localized: "Top")
        case .rising: return String(localized: "Rising")
        }
    }
}

enum RedditTimeFilter: String, CaseIterable, Identifiable, Sendable {
    case day = "day"
    case week = "week"
    case month = "month"
    case year = "year"
    case all = "all"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return String(localized: "Today")
        case .week: return String(localized: "This Week")
        case .month: return String(localized: "This Month")
        case .year: return String(localized: "This Year")
        case .all: return String(localized: "All Time")
        }
    }
}

enum RedditUserFeedType: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case submitted = "submitted"
    case comments = "comments"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "All Activity")
        case .submitted: return String(localized: "Submitted Posts Only")
        case .comments: return String(localized: "Comments Only")
        }
    }
}

enum SocialFeedError: LocalizedError {
    case invalidInput
    case channelNotFound
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return String(localized: "Please enter a valid channel handle, name, or Reddit identifier.")
        case .channelNotFound:
            return String(localized: "YouTube channel could not be found. Please check the channel name or handle.")
        case .networkError(let details):
            return String(format: String(localized: "Network error: %@"), details)
        }
    }
}

// MARK: - SocialFeedResolver

@MainActor
final class SocialFeedResolver {

    static let shared = SocialFeedResolver()

    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - YouTube Resolution

    struct YouTubeChannelResult: Sendable {
        let rssURL: String
        let channelId: String
        let title: String?
    }

    /// Resolves any YouTube input (@handle, channel name, channel URL, channel ID, playlist ID) to a valid RSS URL.
    nonisolated func resolveYouTube(input: String) async throws -> YouTubeChannelResult {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw SocialFeedError.invalidInput }

        // 1. Direct channel ID (starts with UC and around 24 chars)
        if raw.hasPrefix("UC") && raw.count >= 20 && !raw.contains("/") && !raw.contains(" ") {
            let rss = "https://www.youtube.com/feeds/videos.xml?channel_id=\(raw)"
            return YouTubeChannelResult(rssURL: rss, channelId: raw, title: nil)
        }

        // 2. Direct playlist ID (starts with PL)
        if raw.hasPrefix("PL") && !raw.contains("/") && !raw.contains(" ") {
            let rss = "https://www.youtube.com/feeds/videos.xml?playlist_id=\(raw)"
            return YouTubeChannelResult(rssURL: rss, channelId: raw, title: nil)
        }

        // 3. Already a YouTube RSS link
        if raw.contains("youtube.com/feeds/videos.xml") {
            return YouTubeChannelResult(rssURL: raw, channelId: "", title: nil)
        }

        // 4. Extract playlist parameter from URL
        if let url = URL(string: raw), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let playlistId = components.queryItems?.first(where: { $0.name == "list" })?.value, !playlistId.isEmpty {
                let rss = "https://www.youtube.com/feeds/videos.xml?playlist_id=\(playlistId)"
                return YouTubeChannelResult(rssURL: rss, channelId: playlistId, title: nil)
            }
            if let channelId = components.queryItems?.first(where: { $0.name == "channel_id" })?.value, !channelId.isEmpty {
                let rss = "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)"
                return YouTubeChannelResult(rssURL: rss, channelId: channelId, title: nil)
            }
        }

        // 5. Channel URL with /channel/UC...
        if let range = raw.range(of: "/channel/(UC[a-zA-Z0-9_-]+)", options: .regularExpression) {
            let match = String(raw[range]).replacingOccurrences(of: "/channel/", with: "")
            let rss = "https://www.youtube.com/feeds/videos.xml?channel_id=\(match)"
            return YouTubeChannelResult(rssURL: rss, channelId: match, title: nil)
        }

        // 6. Handle or Channel Page Lookup (@handle or youtube.com/@handle or channel name)
        let handleURLString: String
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            handleURLString = raw
        } else if raw.hasPrefix("@") {
            handleURLString = "https://www.youtube.com/\(raw)"
        } else {
            // Assume handle or custom name
            handleURLString = "https://www.youtube.com/@\(raw)"
        }

        guard let targetURL = URL(string: handleURLString) else {
            throw SocialFeedError.invalidInput
        }

        var request = URLRequest(url: targetURL)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await Self.session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                let html = String(decoding: data, as: UTF8.self)

                // Pattern 1: <link rel="alternate" type="application/rss+xml" title="RSS" href="https://www.youtube.com/feeds/videos.xml?channel_id=UC...">
                if let rssMatch = html.range(of: #"https://www.youtube.com/feeds/videos.xml\?channel_id=([a-zA-Z0-9_-]+)"#, options: .regularExpression) {
                    let fullRSS = String(html[rssMatch])
                    let channelId = fullRSS.replacingOccurrences(of: "https://www.youtube.com/feeds/videos.xml?channel_id=", with: "")
                    let title = Self.extractTitle(from: html)
                    return YouTubeChannelResult(rssURL: fullRSS, channelId: channelId, title: title)
                }

                // Pattern 2: "channelId":"UC..."
                if let idMatch = html.range(of: #""channelId":"(UC[a-zA-Z0-9_-]+)""#, options: .regularExpression) {
                    let token = String(html[idMatch])
                    let channelId = token.replacingOccurrences(of: #""channelId":""#, with: "").replacingOccurrences(of: #"""#, with: "")
                    let rss = "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)"
                    let title = Self.extractTitle(from: html)
                    return YouTubeChannelResult(rssURL: rss, channelId: channelId, title: title)
                }

                // Pattern 3: itemprop="channelId" content="UC..."
                if let metaMatch = html.range(of: #"itemprop="channelId"\s+content="(UC[a-zA-Z0-9_-]+)""#, options: .regularExpression) {
                    let token = String(html[metaMatch])
                    if let contentRange = token.range(of: #"content="(UC[a-zA-Z0-9_-]+)""#, options: .regularExpression) {
                        let channelId = String(token[contentRange])
                            .replacingOccurrences(of: #"content=""#, with: "")
                            .replacingOccurrences(of: #"""#, with: "")
                        let rss = "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)"
                        let title = Self.extractTitle(from: html)
                        return YouTubeChannelResult(rssURL: rss, channelId: channelId, title: title)
                    }
                }
            }

            // Fallback: search YouTube channel results
            if let searchResult = await Self.searchYouTube(query: raw) {
                return searchResult
            }

            throw SocialFeedError.channelNotFound
        } catch let err as SocialFeedError {
            if let searchResult = await Self.searchYouTube(query: raw) {
                return searchResult
            }
            throw err
        } catch {
            if let searchResult = await Self.searchYouTube(query: raw) {
                return searchResult
            }
            throw SocialFeedError.networkError(error.localizedDescription)
        }
    }

    private nonisolated static func searchYouTube(query: String) async -> YouTubeChannelResult? {
        let cleanQuery = query
            .replacingOccurrences(of: "@", with: "")
            .replacingOccurrences(of: "https://www.youtube.com/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty,
              let encoded = cleanQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)&sp=EgIQAg%253D%253D") else {
            return nil
        }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        let html = String(decoding: data, as: UTF8.self)

        if let idMatch = html.range(of: #""channelId":"(UC[a-zA-Z0-9_-]+)""#, options: .regularExpression) {
            let token = String(html[idMatch])
            let channelId = token.replacingOccurrences(of: #""channelId":""#, with: "").replacingOccurrences(of: #"""#, with: "")
            let rss = "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)"

            var title: String? = nil
            if let titleMatch = html.range(of: #""title":\{"simpleText":"([^"]+)""#, options: .regularExpression) {
                let tToken = String(html[titleMatch])
                title = tToken.replacingOccurrences(of: #""title":{"simpleText":""#, with: "").replacingOccurrences(of: #"""#, with: "")
            }
            return YouTubeChannelResult(rssURL: rss, channelId: channelId, title: title)
        }
        return nil
    }

    private nonisolated static func extractTitle(from html: String) -> String? {
        if let titleRange = html.range(of: #"<title>(.*?)</title>"#, options: .regularExpression) {
            let full = String(html[titleRange])
                .replacingOccurrences(of: "<title>", with: "")
                .replacingOccurrences(of: "</title>", with: "")
                .replacingOccurrences(of: " - YouTube", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return full.isEmpty ? nil : full
        }
        return nil
    }

    // MARK: - Reddit URL Generation

    nonisolated func buildRedditSubredditURL(
        subreddit: String,
        sort: RedditSort = .hot,
        timeFilter: RedditTimeFilter? = nil
    ) -> String {
        var clean = subreddit.trimmingCharacters(in: .whitespacesAndNewlines)
        clean = clean.replacingOccurrences(of: "https://", with: "")
        clean = clean.replacingOccurrences(of: "http://", with: "")
        clean = clean.replacingOccurrences(of: "www.reddit.com", with: "")
        clean = clean.replacingOccurrences(of: "reddit.com", with: "")
        clean = clean.replacingOccurrences(of: "old.reddit.com", with: "")

        if clean.hasPrefix("/r/") {
            clean = String(clean.dropFirst(3))
        } else if clean.hasPrefix("r/") {
            clean = String(clean.dropFirst(2))
        } else if clean.hasPrefix("/") {
            clean = String(clean.dropFirst(1))
        }

        // Remove any trailing slashes or subpaths
        if let slashIndex = clean.firstIndex(of: "/") {
            clean = String(clean[..<slashIndex])
        }

        guard !clean.isEmpty else { return "" }

        switch sort {
        case .hot:
            return "https://www.reddit.com/r/\(clean)/.rss"
        case .new:
            return "https://www.reddit.com/r/\(clean)/new/.rss"
        case .rising:
            return "https://www.reddit.com/r/\(clean)/rising/.rss"
        case .top:
            if let timeFilter {
                return "https://www.reddit.com/r/\(clean)/top/.rss?t=\(timeFilter.rawValue)"
            } else {
                return "https://www.reddit.com/r/\(clean)/top/.rss"
            }
        }
    }

    nonisolated func buildRedditUserURL(
        username: String,
        type: RedditUserFeedType = .all
    ) -> String {
        var clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
        clean = clean.replacingOccurrences(of: "https://", with: "")
        clean = clean.replacingOccurrences(of: "http://", with: "")
        clean = clean.replacingOccurrences(of: "www.reddit.com", with: "")
        clean = clean.replacingOccurrences(of: "reddit.com", with: "")
        clean = clean.replacingOccurrences(of: "old.reddit.com", with: "")

        if clean.hasPrefix("/user/") {
            clean = String(clean.dropFirst(6))
        } else if clean.hasPrefix("user/") {
            clean = String(clean.dropFirst(5))
        } else if clean.hasPrefix("/u/") {
            clean = String(clean.dropFirst(3))
        } else if clean.hasPrefix("u/") {
            clean = String(clean.dropFirst(2))
        } else if clean.hasPrefix("/") {
            clean = String(clean.dropFirst(1))
        }

        if let slashIndex = clean.firstIndex(of: "/") {
            clean = String(clean[..<slashIndex])
        }

        guard !clean.isEmpty else { return "" }

        switch type {
        case .all:
            return "https://www.reddit.com/user/\(clean)/.rss"
        case .submitted:
            return "https://www.reddit.com/user/\(clean)/submitted/.rss"
        case .comments:
            return "https://www.reddit.com/user/\(clean)/comments/.rss"
        }
    }

    // MARK: - Smart Detect and Resolve

    /// Detects if an arbitrary URL is a YouTube or Reddit link, and transparently converts it to an RSS URL.
    nonisolated func smartDetectAndResolve(url: String) async -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), let host = parsed.host?.lowercased() else {
            return nil
        }

        // Reddit detection
        if host.contains("reddit.com") {
            if trimmed.hasSuffix(".rss") {
                return trimmed
            }
            let path = parsed.path
            if path.contains("/r/") || path.contains("/user/") || path.contains("/u/") {
                var cleanPath = path
                if cleanPath.hasSuffix("/") {
                    cleanPath.removeLast()
                }
                return "https://www.reddit.com\(cleanPath)/.rss"
            }
        }

        // YouTube detection
        if host.contains("youtube.com") || host.contains("youtu.be") {
            if trimmed.contains("feeds/videos.xml") {
                return trimmed
            }
            if let result = try? await resolveYouTube(input: trimmed) {
                return result.rssURL
            }
        }

        return nil
    }
}
