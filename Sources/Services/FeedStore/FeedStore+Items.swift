import Foundation

extension FeedStore {

    // MARK: - Item Management

    func markAsRead(_ item: FeedItem, includingStory: Bool = true) {
        guard var feedItems = items[item.feedId],
              let index = feedItems.firstIndex(where: { $0.id == item.id }) else { return }

        guard !feedItems[index].isRead else { return }

        feedItems[index].isRead = true
        items[item.feedId] = feedItems

        updateItemInActiveViewCache(feedItems[index])
        cachedTotalUnreadCount = max(0, cachedTotalUnreadCount - 1)
        cachedTotalReadCount += 1
        if let currentUnread = cachedFeedUnreadCounts[item.feedId] {
            cachedFeedUnreadCounts[item.feedId] = max(0, currentUnread - 1)
        }

        save(immediate: false, updateCounts: false)
        SyncCoordinator.shared.notifyReadArticles(links: [item.link])
        if includingStory { markStoryAsRead(of: item) }
    }

    func markAllAsRead(feedId: UUID) {
        guard var feedItems = items[feedId] else { return }
        var links: [String] = []
        for i in feedItems.indices {
            if !feedItems[i].isRead {
                feedItems[i].isRead = true
                links.append(feedItems[i].link)
            }
        }
        guard !links.isEmpty else { return }
        items[feedId] = feedItems
        invalidateItemCaches()
        updateCachedCounts()
        save(immediate: false, updateCounts: false)
        SyncCoordinator.shared.notifyReadArticles(links: links)
    }

    func markAllAsRead(items targetItems: [FeedItem]) {
        guard !targetItems.isEmpty else { return }
        var feedGroups: [UUID: Set<UUID>] = [:]
        for item in targetItems {
            feedGroups[item.feedId, default: []].insert(item.id)
        }
        var links: [String] = []
        for (feedId, targetIds) in feedGroups {
            guard var feedItems = items[feedId] else { continue }
            for i in feedItems.indices where targetIds.contains(feedItems[i].id) {
                if !feedItems[i].isRead {
                    feedItems[i].isRead = true
                    links.append(feedItems[i].link)
                }
            }
            items[feedId] = feedItems
        }
        invalidateItemCaches()
        updateCachedCounts()
        save(immediate: false, updateCounts: false)
        SyncCoordinator.shared.notifyReadArticles(links: links)
    }

    func markAllAsUnread(feedId: UUID) {
        guard var feedItems = items[feedId] else { return }
        for i in feedItems.indices {
            feedItems[i].isRead = false
        }
        items[feedId] = feedItems
        invalidateItemCaches()
        updateCachedCounts()
        save(immediate: false, updateCounts: false)
    }

    func allRead(feedId: UUID) -> Bool {
        guard let feedItems = items[feedId], !feedItems.isEmpty else { return true }
        return feedItems.allSatisfy { $0.isRead }
    }

    func toggleReadStatus(_ item: FeedItem) {
        guard var feedItems = items[item.feedId],
              let index = feedItems.firstIndex(where: { $0.id == item.id }) else { return }

        feedItems[index].isRead.toggle()
        let isNowRead = feedItems[index].isRead
        items[item.feedId] = feedItems

        updateItemInActiveViewCache(feedItems[index])
        if isNowRead {
            cachedTotalUnreadCount = max(0, cachedTotalUnreadCount - 1)
            cachedTotalReadCount += 1
            if let currentUnread = cachedFeedUnreadCounts[item.feedId] {
                cachedFeedUnreadCounts[item.feedId] = max(0, currentUnread - 1)
            }
            SyncCoordinator.shared.notifyReadArticles(links: [item.link])
        } else {
            cachedTotalUnreadCount += 1
            cachedTotalReadCount = max(0, cachedTotalReadCount - 1)
            if let currentUnread = cachedFeedUnreadCounts[item.feedId] {
                cachedFeedUnreadCounts[item.feedId] = currentUnread + 1
            }
        }

        save(immediate: false, updateCounts: false)
    }

    // MARK: - Bookmarks

    func toggleBookmark(_ item: FeedItem) {
        guard var feedItems = items[item.feedId],
              let index = feedItems.firstIndex(where: { $0.id == item.id }) else { return }

        feedItems[index].isBookmarked.toggle()
        let isNowBookmarked = feedItems[index].isBookmarked
        items[item.feedId] = feedItems

        updateItemInActiveViewCache(feedItems[index])
        cachedBookmarkCount = max(0, cachedBookmarkCount + (isNowBookmarked ? 1 : -1))

        save(immediate: false, updateCounts: false)
        SyncCoordinator.shared.notifyBookmarkToggled(link: item.link, isBookmarked: isNowBookmarked)
    }

    func bookmarkedItems() -> [FeedItem] {
        getActiveViewItems(key: "bookmarked") {
            items.values.flatMap { $0 }
                .filter { $0.isBookmarked }
                .sortedNewestFirst()
        }
    }

    func bookmarkCount() -> Int {
        cachedBookmarkCount
    }
}
