import Foundation

/// Cross-feed item streams shown in the sidebar (podcasts, videos, reading-time streams).
/// Each stream is a predicate over `FeedItem`; `FeedStore` derives lists and counts from it.
enum ItemStream: String, CaseIterable, Sendable {
    case podcasts
    case videos
    case quickReads
    case longReads

    /// Stable key for the single active-view cache.
    var cacheKey: String {
        switch self {
        case .podcasts:   return "podcasts"
        case .videos:     return "videos"
        case .quickReads: return "quick_reads"
        case .longReads:  return "long_reads"
        }
    }

    func matches(_ item: FeedItem) -> Bool {
        switch self {
        case .podcasts:   return item.isPodcast
        case .videos:     return item.isYouTube
        case .quickReads: return item.isQuickRead
        case .longReads:  return item.isLongRead
        }
    }
}

extension Sequence where Element == FeedItem {
    /// Newest first; items without a date sort last.
    func sortedNewestFirst() -> [FeedItem] {
        sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }
}
