import Foundation

extension FeedStore {

    /// Whether lists fold the same story from several feeds into one row (Settings, on by default).
    static var groupsSimilarStories: Bool {
        UserDefaults.standard.object(forKey: AppSettingsKeys.groupSimilarStories) as? Bool ?? true
    }

    /// Rebuilds the stories in the background. Cheap enough to call after every refresh: only items from the last
    /// two days are compared, and a newer call cancels one that is still running.
    func refreshStories() {
        storyTask?.cancel()
        let all = items.values.flatMap { $0 }
        var configured = StoryClusterer.Settings()
        configured.preferredFeeds = Set(feeds.filter(\.isPinned).map(\.id))
        let settings = configured   // a `let`: a closure that crosses actors cannot capture a mutable variable
        // The comparison runs off the main actor on plain values; only the result comes back to the store.
        storyTask = Task { @MainActor [weak self] in
            let found = await Task.detached(priority: .utility) {
                StoryClusterer.stories(in: all, settings: settings)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.applyStories(found)
        }
    }

    func applyStories(_ found: [StoryClusterer.Story]) {
        var refs: [UUID: StoryRef] = [:]
        refs.reserveCapacity(found.reduce(0) { $0 + $1.size })
        for (index, story) in found.enumerated() {
            for id in story.memberIDs {
                refs[id] = StoryRef(story: index, sources: story.feedCount, isLead: id == story.leadID)
            }
        }
        stories = found
        if refs != storyRefs { storyRefs = refs }
        MemoryRelief.trim()
    }

    /// Number of feeds that told the story this item belongs to, or nil when it stands alone.
    func storySourceCount(for item: FeedItem) -> Int? {
        storyRefs[item.id].map(\.sources)
    }

    /// The other items of this item's story, newest first.
    func otherItemsInStory(of item: FeedItem) -> [FeedItem] {
        guard let ref = storyRefs[item.id], stories.indices.contains(ref.story) else { return [] }
        let wanted = Set(stories[ref.story].memberIDs).subtracting([item.id])
        guard !wanted.isEmpty else { return [] }
        return items.values.flatMap { $0 }.filter { wanted.contains($0.id) }.sortedNewestFirst()
    }

    /// One row per story: of the items of a story that are in `list`, only the best one stays (the lead if it is
    /// there, otherwise the newest). `keeping` is never hidden, so the article being read stays in its list.
    func collapsingStories(in list: [FeedItem], keeping selectedID: UUID?) -> [FeedItem] {
        guard !storyRefs.isEmpty else { return list }
        var shown: [Int: UUID] = [:]   // story -> item that represents it in this list
        for item in list {
            guard let ref = storyRefs[item.id] else { continue }
            if ref.isLead { shown[ref.story] = item.id }
            else if shown[ref.story] == nil { shown[ref.story] = item.id }
        }
        return list.filter { item in
            guard let ref = storyRefs[item.id] else { return true }
            return item.id == selectedID || shown[ref.story] == item.id
        }
    }

    /// Lead items of the stories the most feeds are telling right now (at least three feeds, last 24 hours).
    func topStoryItems(now: Date = Date()) -> [FeedItem] {
        let cutoff = now.addingTimeInterval(-24 * 3600)
        var leads: [(FeedItem, Int)] = []
        let byID = Dictionary(uniqueKeysWithValues: items.values.flatMap { $0 }.map { ($0.id, $0) })
        for story in stories where story.feedCount >= 3 {
            guard let lead = byID[story.leadID] else { continue }
            let newest = story.memberIDs.compactMap { byID[$0]?.pubDate }.max() ?? .distantPast
            if newest >= cutoff { leads.append((lead, story.feedCount)) }
        }
        return leads.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : ($0.0.pubDate ?? .distantPast) > ($1.0.pubDate ?? .distantPast) }.map(\.0)
    }

    func topStoryCount() -> Int {
        stories.reduce(0) { $0 + ($1.feedCount >= 3 ? 1 : 0) }
    }

    /// Reading a story's lead reads the story: the other feeds' versions of it are marked read too.
    func markStoryAsRead(of item: FeedItem) {
        guard Self.groupsSimilarStories else { return }
        for other in otherItemsInStory(of: item) where !other.isRead { markAsRead(other, includingStory: false) }
    }
}
