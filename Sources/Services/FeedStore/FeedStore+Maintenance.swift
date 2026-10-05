import Foundation
import WebKit

extension FeedStore {

    func autoCleanup(olderThanDays days: Int) {
        guard days > 0 else { return }
        let cutoffDate = Date().addingTimeInterval(-Double(days * 86400))
        var removedCount = 0

        for (feedId, feedItems) in items {
            let filtered = feedItems.filter { item in
                if item.isBookmarked || !item.isRead { return true }
                if let pubDate = item.pubDate, pubDate >= cutoffDate { return true }
                removedCount += 1
                return false
            }
            items[feedId] = filtered
        }

        let allBookmarkedLinks = Set(items.values.flatMap { $0 }.filter { $0.isBookmarked }.map { $0.link })
        readerCache.cleanupDiskCache(olderThanDays: days, preservedLinks: allBookmarkedLinks)

        if removedCount > 0 {
            save()
            AppLogger.shared.log("Auto-cleanup removed \(removedCount) old read articles (older than \(days) days)", level: .info, category: .storage)
        }
    }

    var databaseSizeBytes: Int64 {
        let fileURL = saveURL.appendingPathComponent("data.json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false)),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    var offlineCacheSizeBytes: Int64 {
        readerCache.diskCacheSizeBytes
    }

    func clearOfflineCache() {
        readerCache.clearDiskCache()
        AppLogger.shared.log("Offline reader cache cleared", level: .info, category: .storage)
    }

    func resetAllDataAndSettings() {
        AppLogger.shared.log("Initiating complete factory reset of all data and settings", level: .warning, category: .storage)

        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        storyTask?.cancel()
        spotlightTask?.cancel()

        feeds.removeAll()
        items.removeAll()
        folders.removeAll()
        tombstones.removeAll()
        stories = []
        storyRefs = [:]
        refreshBackoff = [:]

        invalidateItemCaches()
        compactMemory()
        updateCachedCounts()
        updateSmartCategoryCaches()

        // Everything in the support folder.
        if let fileList = try? FileManager.default.contentsOfDirectory(at: saveURL, includingPropertiesForKeys: nil) {
            for file in fileList {
                try? FileManager.default.removeItem(at: file)
            }
        }

        // Forget the nearby-sync identity and paired devices (their files were just deleted).
        SyncCoordinator.shared.resetAfterFactoryReset()
        AnnotationStore.shared.removeAll()
        ReadingPositions.shared.removeAll()
        SpotlightIndex.removeAll()

        // Caches and downloads.
        readerCache.clearDiskCache()
        FaviconService.shared.clearDiskCache()
        ImageDownsampleCache.shared.clearDiskCache()
        PodcastDownloadService.shared.deleteAllDownloads()

        // Web view storage and the shared URL cache.
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {}
        WebView.flushMemoryCache()
        URLCache.shared.removeAllCachedResponses()

        // Preferences.
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        AppLogger.shared.log("Factory reset complete: all feeds, articles, downloads and settings removed", level: .info, category: .storage)
    }
}
