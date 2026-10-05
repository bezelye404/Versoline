import Foundation

extension FeedStore {

    /// The current library and reading preferences as one backup file.
    func backupData() throws -> Data {
        let library = StorageData(feeds: feeds, items: items, folders: folders, tombstones: tombstones)
        return try LibraryBackup.make(library: library, settings: SyncSettings.current())
    }

    /// Replaces the library with the one in a backup. The library being replaced is kept as `data.json.before-restore`
    /// next to it, so a restore can itself be undone by hand.
    func restoreBackup(_ envelope: LibraryBackup.Envelope) {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil

        let fileURL = saveURL.appendingPathComponent("data.json")
        let keepURL = saveURL.appendingPathComponent("data.json.before-restore")
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try? fm.removeItem(at: keepURL)
            try? fm.copyItem(at: fileURL, to: keepURL)
        }

        // Written through the normal save path and read back through the normal load path, so a restored library goes
        // through the same repairs and cleanups as any other.
        Self.performSave(data: envelope.library, to: saveURL)
        loadFailed = false
        feeds = []
        items = [:]
        folders = []
        tombstones = []
        invalidateItemCaches()
        load()
        envelope.settings?.applyToUserDefaults()
        updateSmartCategoryCaches()
        refreshStories()
        AppLogger.shared.log("Restored a backup from \(envelope.createdAt.formatted(date: .abbreviated, time: .shortened))", level: .info, category: .storage)
    }

    /// Unread articles published more than `days` days ago. Articles without a date are never counted.
    func unreadItems(olderThanDays days: Int, now: Date = Date()) -> [FeedItem] {
        guard days > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return items.values.flatMap { $0 }.filter { !$0.isRead && ($0.pubDate.map { $0 < cutoff } ?? false) }
    }

    /// Marks unread articles older than `days` days as read; returns how many.
    @discardableResult
    func markOlderThanAsRead(days: Int, now: Date = Date()) -> Int {
        let old = unreadItems(olderThanDays: days, now: now)
        guard !old.isEmpty else { return 0 }
        var byFeed: [UUID: Set<UUID>] = [:]
        for item in old { byFeed[item.feedId, default: []].insert(item.id) }
        var links: [String] = []
        for (feedId, ids) in byFeed {
            guard var feedItems = items[feedId] else { continue }
            for index in feedItems.indices where ids.contains(feedItems[index].id) {
                feedItems[index].isRead = true
                links.append(feedItems[index].link)
            }
            items[feedId] = feedItems
        }
        invalidateItemCaches()
        updateCachedCounts()
        save(immediate: false, updateCounts: false)
        // Nearby sync takes small batches.
        var start = 0
        while start < links.count {
            SyncCoordinator.shared.notifyReadArticles(links: Array(links[start..<min(start + 500, links.count)]))
            start += 500
        }
        AppLogger.shared.log("Marked \(links.count) unread articles older than \(days) days as read", level: .info, category: .storage)
        return links.count
    }

    /// The Settings option "Mark unread articles older than ... as read automatically".
    func applyAutomaticReadMarking() {
        let days = UserDefaults.standard.integer(forKey: AppSettingsKeys.markOldAsReadDays)
        if days > 0 { markOlderThanAsRead(days: days) }
    }
}
