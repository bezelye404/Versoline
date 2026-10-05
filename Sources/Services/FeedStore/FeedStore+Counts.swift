import Foundation

extension FeedStore {

    func updateCachedCounts() {
        var totalUnread = 0
        var totalItems = 0
        var totalBookmarks = 0
        var todayCount = 0
        var streamCounts: [ItemStream: Int] = [:]
        var totalRead = 0
        var unreadPerFeed: [UUID: Int] = [:]
        let oneDayAgo = Date().addingTimeInterval(-86400)

        for (feedId, list) in items {
            var feedUnread = 0
            totalItems += list.count
            for item in list {
                if !item.isRead {
                    feedUnread += 1
                    totalUnread += 1
                } else {
                    totalRead += 1
                }
                if item.isBookmarked {
                    totalBookmarks += 1
                }
                for stream in ItemStream.allCases where stream.matches(item) {
                    streamCounts[stream, default: 0] += 1
                }
                if (item.pubDate ?? .distantPast) >= oneDayAgo {
                    todayCount += 1
                }
            }
            unreadPerFeed[feedId] = feedUnread
        }

        var map: [UUID: Feed] = [:]
        var inFolder: [UUID: [Feed]] = [:]
        var uncategorized: [Feed] = []
        var pinned: [Feed] = []

        // A feed whose folder does not exist (deleted on another Mac, or not synced yet) counts as uncategorized.
        let folderIds = Set(folders.map(\.id))
        for feed in feeds {
            map[feed.id] = feed
            if feed.isPinned {
                pinned.append(feed)
            }
            if let folderId = feed.folderId, folderIds.contains(folderId) {
                inFolder[folderId, default: []].append(feed)
            } else {
                uncategorized.append(feed)
            }
        }

        self.cachedTotalUnreadCount = totalUnread
        self.cachedTotalItemCount = totalItems
        self.cachedBookmarkCount = totalBookmarks
        self.cachedTodayCount = todayCount
        self.cachedStreamCounts = streamCounts
        self.cachedTotalReadCount = totalRead
        self.cachedFeedUnreadCounts = unreadPerFeed
        self.cachedFeedMap = map
        self.cachedFeedsInFolder = inFolder
        self.cachedUncategorizedFeeds = uncategorized
        self.cachedPinnedFeeds = pinned
    }

    func updateSmartCategoryCaches() {
        let map = self.cachedFeedMap.isEmpty ? Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) }) : self.cachedFeedMap

        // Compute counts per category without retaining full duplicate FeedItem arrays in RAM
        var categoryCounts: [SmartCategory: Int] = [:]
        for (feedId, list) in items {
            let feed = map[feedId]
            for item in list {
                if let cat = SmartCategoryClassifier.classify(item: item, feed: feed) {
                    categoryCounts[cat, default: 0] += 1
                }
            }
        }

        // Classify each feed once, not once per article
        var feedsPerCategory: [SmartCategory: [Feed]] = [:]
        for feed in feeds {
            if let cat = SmartCategoryClassifier.classify(feed: feed) {
                feedsPerCategory[cat, default: []].append(feed)
            }
        }

        var activeCats: [SmartCategory] = []
        for cat in SmartCategory.allCases {
            let itemsCount = categoryCounts[cat] ?? 0
            let feedsCount = feedsPerCategory[cat]?.count ?? 0
            if itemsCount > 0 || feedsCount > 0 {
                activeCats.append(cat)
            }
        }

        self.cachedSmartCategoryCounts = categoryCounts
        self.activeSmartCategories = activeCats
    }
}
