import Foundation
import WidgetKit

/// Keeps the widget's snapshot file in step with the library. Called when the counts change, after a short pause,
/// and only writes (and asks WidgetKit to redraw) when what the widget would show has changed.
@MainActor
enum WidgetUpdater {

    /// Builds the snapshot from plain values. Top stories first, then the newest unread articles.
    static func makeSnapshot(
        items: some Sequence<FeedItem>,
        feedTitles: [UUID: String],
        topStoryIDs: Set<UUID>,
        unreadCount: Int,
        mutedKeywords: [String],
        limit: Int = WidgetSnapshot.maxHeadlines,
        now: Date = Date()
    ) -> WidgetSnapshot {
        let candidates = items.filter { item in
            guard !item.isRead, !item.isPodcast, !item.isYouTube else { return false }
            let text = (item.title + " " + item.snippet).lowercased()
            return !mutedKeywords.contains { text.contains($0) }
        }
        let ranked = candidates.sorted { lhs, rhs in
            let lhsTop = topStoryIDs.contains(lhs.id), rhsTop = topStoryIDs.contains(rhs.id)
            if lhsTop != rhsTop { return lhsTop }
            return (lhs.pubDate ?? .distantPast) > (rhs.pubDate ?? .distantPast)
        }
        let headlines = ranked.prefix(limit).map { item in
            WidgetSnapshot.Headline(
                title: item.title,
                feedTitle: feedTitles[item.feedId] ?? "",
                link: item.link,
                // Whole seconds, as stored in the file, so an unchanged headline compares equal after a round trip.
                date: item.pubDate.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) },
                isTopStory: topStoryIDs.contains(item.id)
            )
        }
        return WidgetSnapshot(generatedAt: now, unreadCount: unreadCount, headlines: Array(headlines))
    }

    static func update(store: FeedStore) {
        let muted = (UserDefaults.standard.string(forKey: AppSettingsKeys.mutedKeywords) ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let top = Set(store.topStoryItems().map(\.id))
        let titles = Dictionary(store.feeds.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let snapshot = makeSnapshot(
            items: store.items.values.joined(),
            feedTitles: titles,
            topStoryIDs: top,
            unreadCount: store.totalUnreadCount(),
            mutedKeywords: muted
        )
        if snapshot.write() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
