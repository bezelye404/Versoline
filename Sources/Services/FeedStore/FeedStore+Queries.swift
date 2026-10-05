import Foundation

extension FeedStore {

    func items(for stream: ItemStream) -> [FeedItem] {
        getActiveViewItems(key: stream.cacheKey) {
            items.values.flatMap { $0 }
                .filter { stream.matches($0) }
                .sortedNewestFirst()
        }
    }

    func count(for stream: ItemStream) -> Int {
        cachedStreamCounts[stream, default: 0]
    }

    func smartCategoryItems(_ category: SmartCategory) -> [FeedItem] {
        getActiveViewItems(key: "smart_\(category.rawValue)") {
            let feedMap = cachedFeedMap
            return items.values.flatMap { $0 }
                .filter { item in
                    let feed = feedMap[item.feedId]
                    return SmartCategoryClassifier.classify(item: item, feed: feed) == category
                }
                .sortedNewestFirst()
        }
    }

    func smartCategoryCount(_ category: SmartCategory) -> Int {
        if let count = cachedSmartCategoryCounts[category] {
            return count
        }
        return smartCategoryItems(category).count
    }

    func totalReadCount() -> Int {
        cachedTotalReadCount
    }

    func readingStreakDays() -> Int {
        var readCount = 0
        for list in items.values {
            for item in list where item.isRead {
                readCount += 1
            }
        }
        guard readCount > 0 else { return 0 }
        return min(max(1, readCount / 3), 14) // Estimated active reading consistency
    }

    func weeklyReadHistory() -> [DailyReadingStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var stats: [DailyReadingStat] = []

        // Last 7 days
        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dayName = Self.dayOfWeekFormatter.string(from: date)

            // Count items read on or around this date
            let count = allItems().filter { item in
                guard item.isRead, let pDate = item.pubDate else { return false }
                return calendar.isDate(pDate, inSameDayAs: date)
            }.count

            stats.append(DailyReadingStat(day: dayName, date: date, count: max(count, 0)))
        }
        return stats
    }

    func updatePlaybackProgress(for itemId: UUID, feedId: UUID, position: Double, isFinished: Bool) {
        guard var feedItems = items[feedId],
              let index = feedItems.firstIndex(where: { $0.id == itemId }) else { return }

        feedItems[index].playbackPosition = position
        feedItems[index].isFinished = isFinished
        if isFinished {
            feedItems[index].isRead = true
        }
        items[feedId] = feedItems
        save()
    }

    var totalItemCount: Int {
        cachedTotalItemCount
    }

    func feed(for id: UUID) -> Feed? {
        cachedFeedMap[id] ?? feeds.first { $0.id == id }
    }

    func unreadCount(for feedId: UUID) -> Int {
        cachedFeedUnreadCounts[feedId] ?? 0
    }

    func totalUnreadCount() -> Int {
        cachedTotalUnreadCount
    }

    func itemsForFeed(_ feedId: UUID) -> [FeedItem] {
        items[feedId] ?? []
    }

    func allItems() -> [FeedItem] {
        getActiveViewItems(key: "all") {
            items.values.flatMap { $0 }
                .sortedNewestFirst()
        }
    }

    func unreadItems() -> [FeedItem] {
        getActiveViewItems(key: "unread") {
            items.values.flatMap { $0 }
                .filter { !$0.isRead }
                .sortedNewestFirst()
        }
    }

    func todayItems() -> [FeedItem] {
        getActiveViewItems(key: "today") {
            let oneDayAgo = Date().addingTimeInterval(-86400)
            return items.values.flatMap { $0 }
                .filter { ($0.pubDate ?? .distantPast) >= oneDayAgo }
                .sortedNewestFirst()
        }
    }

    func todayItemsCount() -> Int {
        cachedTodayCount
    }

    func itemsForFolder(_ folderId: UUID) -> [FeedItem] {
        getActiveViewItems(key: "folder_\(folderId)") {
            let folder = folders.first(where: { $0.id == folderId })
            let folderFeeds = cachedFeedsInFolder[folderId] ?? []
            let folderFeedIds = Set(folderFeeds.map(\.id))
            var directItems: [FeedItem] = []
            for feedId in folderFeedIds {
                if let feedItems = items[feedId] {
                    directItems.append(contentsOf: feedItems)
                }
            }

            if let keywords = folder?.keywords, !keywords.isEmpty {
                let lowerKeywords = keywords.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                var seenIDs = Set(directItems.map(\.id))
                var matchingItems: [FeedItem] = []
                for list in items.values {
                    for item in list where !seenIDs.contains(item.id) {
                        let titleLower = item.title.lowercased()
                        let descLower = item.itemDescription.lowercased()
                        if lowerKeywords.contains(where: { kw in titleLower.contains(kw) || descLower.contains(kw) }) {
                            seenIDs.insert(item.id)
                            matchingItems.append(item)
                        }
                    }
                }
                directItems.append(contentsOf: matchingItems)
            }

            return directItems.sortedNewestFirst()
        }
    }

    func itemsCountForFolder(_ folderId: UUID) -> Int {
        let folder = folders.first(where: { $0.id == folderId })
        if let keywords = folder?.keywords, !keywords.isEmpty {
            return itemsForFolder(folderId).count
        }
        let folderFeeds = cachedFeedsInFolder[folderId] ?? []
        var count = 0
        for feed in folderFeeds {
            count += items[feed.id]?.count ?? 0
        }
        return count
    }

    func updateFolderKeywords(_ folderId: UUID, keywords: [String]?) {
        if let index = folders.firstIndex(where: { $0.id == folderId }) {
            folders[index].keywords = (keywords?.isEmpty ?? true) ? nil : keywords
            save()
        }
    }

    func downloadedItemsCount() -> Int {
        let downloadedIDs = PodcastDownloadService.shared.downloadedEpisodeIDs
        guard !downloadedIDs.isEmpty else { return 0 }
        var count = 0
        for list in items.values {
            for item in list where downloadedIDs.contains(item.id) {
                count += 1
            }
        }
        return count
    }

    func downloadedItems() -> [FeedItem] {
        getActiveViewItems(key: "downloaded") {
            let downloadedIDs = PodcastDownloadService.shared.downloadedEpisodeIDs
            guard !downloadedIDs.isEmpty else { return [] }
            var result: [FeedItem] = []
            for list in items.values {
                for item in list where downloadedIDs.contains(item.id) {
                    result.append(item)
                }
            }
            return result.sortedNewestFirst()
        }
    }
}
