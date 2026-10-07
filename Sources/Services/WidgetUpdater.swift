import Foundation
import WidgetKit

/// Keeps the widget's snapshot file in step with the library. It writes (and asks WidgetKit to redraw) only when
/// what the widget would show has changed, and it works on the library in place: no copy of the articles is made.
@MainActor
enum WidgetUpdater {

    private struct Candidate {
        let item: FeedItem
        let isTop: Bool
        let date: Date
    }

    private static func ranksBefore(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        lhs.isTop != rhs.isTop ? lhs.isTop : lhs.date > rhs.date
    }

    /// Builds the snapshot in two passes over the articles, keeping only the best few. Top stories first, then the
    /// newest unread articles. A story is a top story when three or more feeds tell it and it is under a day old.
    static func makeSnapshot(
        items: some Sequence<FeedItem>,
        feedTitles: [UUID: String],
        storyRefs: [UUID: FeedStore.StoryRef],
        unreadCount: Int,
        mutedKeywords: [String],
        palette: String,
        limit: Int = WidgetSnapshot.maxHeadlines,
        now: Date = Date()
    ) -> WidgetSnapshot {
        // Pass 1: when was each widely told story last reported?
        let cutoff = now.addingTimeInterval(-24 * 3600)
        var newestInStory: [Int: Date] = [:]
        for item in items {
            guard let ref = storyRefs[item.id], ref.sources >= 3, let date = item.pubDate else { continue }
            if date > (newestInStory[ref.story] ?? .distantPast) { newestInStory[ref.story] = date }
        }

        // Pass 2: keep the `limit` best candidates; a small sorted array is enough.
        var best: [Candidate] = []
        best.reserveCapacity(limit + 1)
        for item in items where !item.isRead && !item.isPodcast && !item.isYouTube {
            let date = item.pubDate ?? .distantPast
            let isTop: Bool
            if let ref = storyRefs[item.id], ref.isLead, ref.sources >= 3, (newestInStory[ref.story] ?? .distantPast) >= cutoff {
                isTop = true
            } else {
                isTop = false
            }
            let candidate = Candidate(item: item, isTop: isTop, date: date)
            if best.count == limit, let last = best.last, !ranksBefore(candidate, last) { continue }
            if !mutedKeywords.isEmpty {
                let text = (item.title + " " + item.snippet).lowercased()
                if mutedKeywords.contains(where: { text.contains($0) }) { continue }
            }
            let index = best.firstIndex { ranksBefore(candidate, $0) } ?? best.count
            best.insert(candidate, at: index)
            if best.count > limit { best.removeLast() }
        }

        let headlines = best.map { candidate in
            WidgetSnapshot.Headline(
                title: candidate.item.title,
                feedTitle: feedTitles[candidate.item.feedId] ?? "",
                link: candidate.item.link,
                // Whole seconds, as stored in the file, so an unchanged headline compares equal after a round trip.
                date: candidate.item.pubDate.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) },
                isTopStory: candidate.isTop
            )
        }
        return WidgetSnapshot(generatedAt: now, unreadCount: unreadCount, headlines: headlines, palette: palette)
    }

    static func update(store: FeedStore) {
        // A library that failed to load looks empty; keep what the widget shows instead of writing "all caught up".
        guard !store.loadFailed else { return }
        // With sharing off the file is removed and nothing is written; the widget then asks the user to open the app.
        guard UserDefaults.standard.object(forKey: AppSettingsKeys.shareWithWidget) as? Bool ?? true else {
            if WidgetSnapshot.remove() { WidgetCenter.shared.reloadAllTimelines() }
            return
        }
        let muted = (UserDefaults.standard.string(forKey: AppSettingsKeys.mutedKeywords) ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let titles = Dictionary(store.feeds.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let palette = UserDefaults.standard.string(forKey: AppSettingsKeys.appColorPalette) ?? AppColorPalette.slate.rawValue
        let snapshot = makeSnapshot(
            items: store.items.values.joined(),
            feedTitles: titles,
            storyRefs: store.storyRefs,
            unreadCount: store.totalUnreadCount(),
            mutedKeywords: muted,
            palette: palette
        )
        if snapshot.write() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
