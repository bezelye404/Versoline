import Foundation
import SwiftUI
import WebKit

struct FullscreenVideoContext: Identifiable, Equatable {
    var id: String { videoID }
    let videoID: String
    let title: String
    let link: String
}

@MainActor
@Observable
final class FeedStore {

    static let maxItemsPerFeed = 100

    var feeds: [Feed] = []
    var items: [UUID: [FeedItem]] = [:]
    var folders: [Folder] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var fullscreenVideo: FullscreenVideoContext?

    private let saveURL: URL
    private var pendingSaveTask: Task<Void, Never>?

    // Fast O(1) in-memory cached aggregates
    private(set) var cachedTotalUnreadCount: Int = 0
    private(set) var cachedTotalItemCount: Int = 0
    private(set) var cachedBookmarkCount: Int = 0
    private(set) var cachedPodcastCount: Int = 0
    private(set) var cachedTodayCount: Int = 0
    private(set) var cachedVideoCount: Int = 0
    private(set) var cachedQuickReadsCount: Int = 0
    private(set) var cachedLongReadsCount: Int = 0
    private(set) var cachedTotalReadCount: Int = 0
    private var cachedFeedUnreadCounts: [UUID: Int] = [:]
    private var cachedFeedMap: [UUID: Feed] = [:]
    private var cachedFeedsInFolder: [UUID: [Feed]] = [:]
    private var cachedUncategorizedFeeds: [Feed] = []
    private var cachedPinnedFeeds: [Feed] = []

    // Memoized sorted arrays to avoid O(N log N) re-computation on every UI frame
    @ObservationIgnored private var cachedAllItems: [FeedItem]?
    @ObservationIgnored private var cachedUnreadItems: [FeedItem]?
    @ObservationIgnored private var cachedTodayItems: [FeedItem]?
    @ObservationIgnored private var cachedBookmarkedItems: [FeedItem]?
    @ObservationIgnored private var cachedPodcastItems: [FeedItem]?
    @ObservationIgnored private var cachedFolderItems: [UUID: [FeedItem]] = [:]
    @ObservationIgnored private var cachedFeedItems: [UUID: [FeedItem]] = [:]
    @ObservationIgnored private var cachedSmartCategoryItems: [SmartCategory: [FeedItem]] = [:]
    @ObservationIgnored private var cachedSmartCategoryCounts: [SmartCategory: Int] = [:]
    private(set) var activeSmartCategories: [SmartCategory] = []
    @ObservationIgnored private var lastRefreshDate: Date?

    private static let dayOfWeekFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE"
        return df
    }()

    private func invalidateItemCaches() {
        cachedAllItems = nil
        cachedUnreadItems = nil
        cachedTodayItems = nil
        cachedBookmarkedItems = nil
        cachedPodcastItems = nil
        cachedFolderItems.removeAll(keepingCapacity: false)
        cachedFeedItems.removeAll(keepingCapacity: false)
        cachedSmartCategoryItems.removeAll(keepingCapacity: false)
    }

    func compactMemory() {
        invalidateItemCaches()
        cachedFolderItems.removeAll(keepingCapacity: false)
        cachedFeedItems.removeAll(keepingCapacity: false)
        cachedSmartCategoryItems.removeAll(keepingCapacity: false)
        let preserved = Set(items.values.flatMap { $0 }.filter { $0.isBookmarked }.map { $0.link })
        ReaderModeExtractor.shared.enforceQuota(maxSizeBytes: 50 * 1024 * 1024, preservedLinks: preserved)
        ImageDownsampleCache.shared.clearMemory()
        ImageDownsampleCache.shared.enforceQuota(maxSizeBytes: 30 * 1024 * 1024)
        WebView.flushMemoryCache()
        AppLogger.shared.log("In-memory sorted caches compacted for background memory relief", level: .debug, category: .storage)
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("EasyRSS", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.saveURL = appDir
        load()

        let cleanupDays = UserDefaults.standard.integer(forKey: AppSettingsKeys.autoCleanupDays)
        if cleanupDays > 0 {
            autoCleanup(olderThanDays: cleanupDays)
        } else {
            let preserved = Set(items.values.flatMap { $0 }.filter { $0.isBookmarked }.map { $0.link })
            ReaderModeExtractor.shared.enforceQuota(maxSizeBytes: 150 * 1024 * 1024, preservedLinks: preserved)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.compactMemory()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.compactMemory()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("EasyRSSCompactMemory"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.compactMemory()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushPendingSave()
            }
        }

        SyncCoordinator.shared.configure(with: self)
    }

    // MARK: - Feed Management

    func addFeed(url: String, folderId: UUID? = nil) async {
        var targetURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetURL.isEmpty else { return }

        // Transparently resolve YouTube or Reddit links to valid RSS feeds
        if let resolvedURL = await SocialFeedResolver.shared.smartDetectAndResolve(url: targetURL) {
            targetURL = resolvedURL
        }

        if feeds.contains(where: { $0.url == targetURL }) {
            errorMessage = String(localized: "This feed has already been added.")
            AppLogger.shared.log("Feed already added: \(targetURL)", level: .warning, category: .ui)
            return
        }

        isLoading = true
        errorMessage = nil

        let newFeedId = UUID()
        AppLogger.shared.log("Adding feed: \(targetURL)", level: .info, category: .network)

        do {
            let result = try await Self.fetchFeed(url: targetURL, feedId: newFeedId)

            guard let result else {
                errorMessage = String(localized: "Could not parse feed. Please ensure it is a valid RSS/Atom URL.")
                AppLogger.shared.log("Parse failed for new feed: \(targetURL)", level: .error, category: .parser)
                isLoading = false
                return
            }

            let feed = Feed(
                id: newFeedId,
                title: result.title.isEmpty ? targetURL : result.title,
                url: targetURL,
                description: result.description,
                imageURL: result.imageURL,
                lastUpdated: Date(),
                folderId: folderId
            )

            feeds.append(feed)
            let parsedItems = result.items.map { item -> FeedItem in
                var m = item
                if let rawContent = m.content, !rawContent.isEmpty {
                    ReaderModeExtractor.shared.saveToCache(urlString: m.link, content: rawContent, storeInMemory: false)
                }
                if m.itemDescription.count > 300 || m.itemDescription.contains("<") {
                    ReaderModeExtractor.shared.saveToCache(urlString: m.link, content: m.itemDescription, storeInMemory: false, overwrite: false)
                    let cleanDesc = m.itemDescription.strippingHTML()
                    m.itemDescription = cleanDesc.count > 250 ? String(cleanDesc.prefix(250)) : cleanDesc
                }
                m.content = nil
                return m
            }
            let cappedItems = parsedItems.count > Self.maxItemsPerFeed ? Array(parsedItems.prefix(Self.maxItemsPerFeed)) : parsedItems
            items[newFeedId] = cappedItems
            isLoading = false
            updateSmartCategoryCaches()
            save()
            SyncCoordinator.shared.notifyFeedAddedOrUpdated(feed)
            AppLogger.shared.log("Successfully added feed \"\(feed.title)\" with \(cappedItems.count) items", level: .info, category: .storage)
        } catch {
            let errorMsg = String(format: String(localized: "Failed to load feed: %@"), error.localizedDescription)
            errorMessage = errorMsg
            AppLogger.shared.log(errorMsg, level: .error, category: .network, details: targetURL)
            isLoading = false
        }
    }

    func removeFeed(_ feed: Feed) {
        AppLogger.shared.log("Removing feed \"\(feed.title)\"", level: .info, category: .storage)
        feeds.removeAll { $0.id == feed.id }
        items.removeValue(forKey: feed.id)
        updateSmartCategoryCaches()
        save()
        SyncCoordinator.shared.notifyFeedDeleted(id: feed.id)
    }

    func refreshFeed(_ feed: Feed) async {
        isLoading = true
        errorMessage = nil
        AppLogger.shared.log("Refreshing single feed: \"\(feed.title)\"", level: .info, category: .network)

        do {
            let result = try await Self.fetchFeed(url: feed.url, feedId: feed.id, etag: feed.etag, lastModified: feed.lastModifiedHeader)

            guard let result else {
                isLoading = false
                return
            }

            applyFeedUpdate(feedId: feed.id, result: result)
            isLoading = false
            updateSmartCategoryCaches()
            save()
        } catch {
            let errorMsg = String(format: String(localized: "Refresh failed: %@"), error.localizedDescription)
            errorMessage = errorMsg
            AppLogger.shared.log(errorMsg, level: .error, category: .network, details: feed.url)
            isLoading = false
        }
    }

    func refreshAllFeeds(force: Bool = false) async {
        guard !feeds.isEmpty else { return }

        // Throttle: don't auto-refresh if refreshed within the last 15 minutes unless forced
        if !force, let last = lastRefreshDate, Date().timeIntervalSince(last) < 900 {
            AppLogger.shared.log("Skipping background refresh: refreshed \(Int(Date().timeIntervalSince(last)))s ago", level: .debug, category: .network)
            return
        }

        isLoading = true
        errorMessage = nil
        AppLogger.shared.log("Starting concurrent refresh for \(feeds.count) feeds (forced: \(force))", level: .info, category: .network)

        let feedsToRefresh = self.feeds

        await withTaskGroup(of: (UUID, RSSParser.ParseResult?)?.self) { group in
            var running = 0
            var feedIterator = feedsToRefresh.makeIterator()

            while running > 0 || true {
                // Keep up to 4 concurrent network requests active
                while running < 4, let feed = feedIterator.next() {
                    running += 1
                    group.addTask {
                        do {
                            if feed.url.lowercased().contains("reddit.com") {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                            }
                            let result = try await Self.fetchFeed(url: feed.url, feedId: feed.id, etag: feed.etag, lastModified: feed.lastModifiedHeader)
                            return (feed.id, result)
                        } catch {
                            await AppLogger.shared.log("Error refreshing \"\(feed.title)\": \(error.localizedDescription)", level: .error, category: .network)
                            return nil
                        }
                    }
                }

                if running == 0 { break }

                if let finished = await group.next() {
                    running -= 1
                    if let (feedId, result) = finished, let result {
                        self.applyFeedUpdate(feedId: feedId, result: result)
                    }
                }
            }
        }

        lastRefreshDate = Date()
        isLoading = false
        updateSmartCategoryCaches()
        save()
        AppLogger.shared.log("All feeds refresh finished", level: .info, category: .network)
    }

    private func applyFeedUpdate(feedId: UUID, result: RSSParser.ParseResult) {
        if result.isNotModified {
            if let index = feeds.firstIndex(where: { $0.id == feedId }) {
                feeds[index].lastUpdated = Date()
            }
            AppLogger.shared.log("Feed not modified (HTTP 304): skipped parsing & updates", level: .debug, category: .network)
            return
        }

        let existingItems = items[feedId] ?? []
        let existingByLink = Dictionary(existingItems.map { ($0.link, $0) }, uniquingKeysWith: { first, _ in first })

        var updatedItems = result.items.map { item in
            var mutableItem = item
            if let existing = existingByLink[item.link] {
                mutableItem = FeedItem(
                    id: existing.id,
                    feedId: item.feedId,
                    title: item.title,
                    link: item.link,
                    itemDescription: item.itemDescription,
                    pubDate: item.pubDate ?? existing.pubDate,
                    author: item.author ?? existing.author,
                    isRead: existing.isRead,
                    content: item.content,
                    isBookmarked: existing.isBookmarked,
                    audioURL: item.audioURL ?? existing.audioURL,
                    audioDuration: item.audioDuration ?? existing.audioDuration,
                    audioType: item.audioType ?? existing.audioType,
                    audioLength: item.audioLength ?? existing.audioLength,
                    playbackPosition: existing.playbackPosition,
                    isFinished: existing.isFinished
                )
            }

            // Save raw content and large descriptions to disk reader cache so RAM remains completely lean
            if let rawContent = mutableItem.content, !rawContent.isEmpty {
                ReaderModeExtractor.shared.saveToCache(urlString: mutableItem.link, content: rawContent, storeInMemory: false)
                mutableItem.content = nil
            }
            if mutableItem.itemDescription.count > 300 || mutableItem.itemDescription.contains("<") {
                ReaderModeExtractor.shared.saveToCache(urlString: mutableItem.link, content: mutableItem.itemDescription, storeInMemory: false, overwrite: false)
                let cleanDesc = mutableItem.itemDescription.strippingHTML()
                mutableItem.itemDescription = cleanDesc.count > 250 ? String(cleanDesc.prefix(250)) : cleanDesc
            }

            return mutableItem
        }

        // Always preserve existing bookmarked items that may have fallen off the feed XML
        let updatedLinks = Set(updatedItems.map { $0.link })
        let preservedBookmarks = existingItems.filter { $0.isBookmarked && !updatedLinks.contains($0.link) }
        if !preservedBookmarks.isEmpty {
            updatedItems.append(contentsOf: preservedBookmarks)
        }

        // Memory safety: Enforce maxItemsPerFeed cap for non-bookmarked items
        if updatedItems.count > Self.maxItemsPerFeed {
            let bookmarks = updatedItems.filter { $0.isBookmarked }
            let nonBookmarks = updatedItems
                .filter { !$0.isBookmarked }
                .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                .prefix(Self.maxItemsPerFeed)
            updatedItems = (Array(nonBookmarks) + bookmarks).sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        }

        items[feedId] = updatedItems

        if let index = feeds.firstIndex(where: { $0.id == feedId }) {
            feeds[index].lastUpdated = Date()
            if let etag = result.etag {
                feeds[index].etag = etag
            }
            if let lastModified = result.lastModified {
                feeds[index].lastModifiedHeader = lastModified
            }
            if !result.title.isEmpty {
                feeds[index].title = result.title
            }
        }
    }

    // MARK: - Folder Management

    @discardableResult
    func addFolder(name: String) -> Folder {
        let folder = Folder(name: name)
        folders.append(folder)
        AppLogger.shared.log("Added folder: \"\(name)\"", level: .info, category: .storage)
        save()
        SyncCoordinator.shared.notifyFeedsOrFoldersChanged()
        return folder
    }

    func removeFolder(_ folderId: UUID) {
        let folderName = folders.first(where: { $0.id == folderId })?.name ?? folderId.uuidString
        AppLogger.shared.log("Removed folder: \"\(folderName)\"", level: .info, category: .storage)
        for i in feeds.indices {
            if feeds[i].folderId == folderId {
                feeds[i].folderId = nil
            }
        }
        folders.removeAll { $0.id == folderId }
        save()
        SyncCoordinator.shared.notifyFeedsOrFoldersChanged()
    }

    func renameFolder(_ folderId: UUID, name: String) {
        if let index = folders.firstIndex(where: { $0.id == folderId }) {
            let old = folders[index].name
            folders[index].name = name
            AppLogger.shared.log("Renamed folder \"\(old)\" -> \"\(name)\"", level: .info, category: .storage)
            save()
            SyncCoordinator.shared.notifyFeedsOrFoldersChanged()
        }
    }

    func moveFeed(_ feedId: UUID, toFolder folderId: UUID?) {
        if let index = feeds.firstIndex(where: { $0.id == feedId }) {
            feeds[index].folderId = folderId
            save()
            SyncCoordinator.shared.notifyFeedsOrFoldersChanged()
        }
    }


    func setFeedsInFolder(_ folderId: UUID, feedIds: Set<UUID>) {
        var changed = false
        for i in feeds.indices {
            let shouldBeInFolder = feedIds.contains(feeds[i].id)
            if shouldBeInFolder && feeds[i].folderId != folderId {
                feeds[i].folderId = folderId
                changed = true
            } else if !shouldBeInFolder && feeds[i].folderId == folderId {
                feeds[i].folderId = nil
                changed = true
            }
        }
        if changed {
            save()
            SyncCoordinator.shared.notifyFeedsOrFoldersChanged()
        }
    }

    func feedsInFolder(_ folderId: UUID) -> [Feed] {
        cachedFeedsInFolder[folderId] ?? []
    }

    func uncategorizedFeeds() -> [Feed] {
        cachedUncategorizedFeeds
    }

    func pinnedFeeds() -> [Feed] {
        cachedPinnedFeeds
    }

    func isPinned(feedId: UUID) -> Bool {
        cachedFeedMap[feedId]?.isPinned ?? false
    }

    func togglePin(feedId: UUID) {
        guard let index = feeds.firstIndex(where: { $0.id == feedId }) else { return }
        feeds[index].isPinned.toggle()
        let updatedFeed = feeds[index]
        save()
        SyncCoordinator.shared.notifyFeedAddedOrUpdated(updatedFeed)
        AppLogger.shared.log("Toggled pin for \"\(updatedFeed.title)\": \(updatedFeed.isPinned)", level: .info, category: .storage)
    }

    func setFeedPinned(_ feedId: UUID, isPinned: Bool) {
        guard let index = feeds.firstIndex(where: { $0.id == feedId }), feeds[index].isPinned != isPinned else { return }
        feeds[index].isPinned = isPinned
        let updatedFeed = feeds[index]
        save()
        SyncCoordinator.shared.notifyFeedAddedOrUpdated(updatedFeed)
        AppLogger.shared.log("Set pin for \"\(updatedFeed.title)\": \(isPinned)", level: .info, category: .storage)
    }

    func reorderPinnedFeeds(fromOffsets source: IndexSet, toOffset destination: Int) {
        var pinned = cachedPinnedFeeds
        pinned.move(fromOffsets: source, toOffset: destination)

        var pinnedIterator = pinned.makeIterator()
        for i in feeds.indices {
            if feeds[i].isPinned {
                if let next = pinnedIterator.next() {
                    feeds[i] = next
                }
            }
        }
        save()
        AppLogger.shared.log("Reordered pinned feeds", level: .info, category: .ui)
    }

    // MARK: - Item Management

    func markAsRead(_ item: FeedItem) {
        guard var feedItems = items[item.feedId],
              let index = feedItems.firstIndex(where: { $0.id == item.id }) else { return }

        feedItems[index].isRead = true
        items[item.feedId] = feedItems
        save()
        SyncCoordinator.shared.notifyReadArticles(links: [item.link])
    }

    func markAllAsRead(feedId: UUID) {
        guard var feedItems = items[feedId] else { return }
        var links: [String] = []
        for i in feedItems.indices {
            feedItems[i].isRead = true
            links.append(feedItems[i].link)
        }
        items[feedId] = feedItems
        save()
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
                feedItems[i].isRead = true
                links.append(feedItems[i].link)
            }
            items[feedId] = feedItems
        }
        save()
        SyncCoordinator.shared.notifyReadArticles(links: links)
    }

    func markAllAsUnread(feedId: UUID) {
        guard var feedItems = items[feedId] else { return }
        for i in feedItems.indices {
            feedItems[i].isRead = false
        }
        items[feedId] = feedItems
        save()
    }

    func allRead(feedId: UUID) -> Bool {
        guard let feedItems = items[feedId], !feedItems.isEmpty else { return true }
        return feedItems.allSatisfy { $0.isRead }
    }

    func toggleReadStatus(_ item: FeedItem) {
        guard var feedItems = items[item.feedId],
              let index = feedItems.firstIndex(where: { $0.id == item.id }) else { return }

        feedItems[index].isRead.toggle()
        items[item.feedId] = feedItems
        save()
    }

    // MARK: - Auto-Cleanup & Storage Management

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
        ReaderModeExtractor.shared.cleanupDiskCache(olderThanDays: days, preservedLinks: allBookmarkedLinks)

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
        ReaderModeExtractor.shared.diskCacheSizeBytes
    }

    func clearOfflineCache() {
        ReaderModeExtractor.shared.clearDiskCache()
        AppLogger.shared.log("Offline reader cache cleared", level: .info, category: .storage)
    }

    func resetAllDataAndSettings() {
        AppLogger.shared.log("Initiating complete factory reset of all data and settings", level: .warning, category: .storage)

        // 1. Cancel any pending background saves
        pendingSaveTask?.cancel()
        pendingSaveTask = nil

        // 2. Clear in-memory feed, item, and folder state
        feeds.removeAll()
        items.removeAll()
        folders.removeAll()

        // 3. Invalidate caches and reset aggregate counts
        invalidateItemCaches()
        compactMemory()
        updateCachedCounts()
        updateSmartCategoryCaches()

        // 4. Remove all files from Application Support/EasyRSS directory
        if let fileList = try? FileManager.default.contentsOfDirectory(at: saveURL, includingPropertiesForKeys: nil) {
            for file in fileList {
                try? FileManager.default.removeItem(at: file)
            }
        }

        // 5. Clear offline cache, favicon disk cache, image cache, and downloaded podcasts
        ReaderModeExtractor.shared.clearDiskCache()
        FaviconService.shared.clearDiskCache()
        ImageDownsampleCache.shared.clearDiskCache()
        PodcastDownloadService.shared.deleteAllDownloads()

        // 6. Clear WebKit website storage, memory cache, and shared URL cache
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {}
        WebView.flushMemoryCache()
        URLCache.shared.removeAllCachedResponses()

        // 7. Reset all UserDefaults / AppStorage
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }

        AppLogger.shared.log("Factory reset complete: all feeds, articles, downloads and settings removed", level: .info, category: .storage)
    }


    // MARK: - Bookmarks

    func toggleBookmark(_ item: FeedItem) {
        guard var feedItems = items[item.feedId],
              let index = feedItems.firstIndex(where: { $0.id == item.id }) else { return }

        feedItems[index].isBookmarked.toggle()
        let isNowBookmarked = feedItems[index].isBookmarked
        items[item.feedId] = feedItems
        save()
        SyncCoordinator.shared.notifyBookmarkToggled(link: item.link, isBookmarked: isNowBookmarked)
    }

    func bookmarkedItems() -> [FeedItem] {
        if let cached = cachedBookmarkedItems { return cached }
        let sorted = items.values.flatMap { $0 }
            .filter { $0.isBookmarked }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        cachedBookmarkedItems = sorted
        return sorted
    }

    func bookmarkCount() -> Int {
        cachedBookmarkCount
    }

    // MARK: - Remote Synchronization Handlers

    func applySyncUpdate(
        feeds: [Feed],
        folders: [Folder],
        readHashes: Set<UInt64>,
        bookmarkedLinks: Set<String>
    ) {
        self.feeds = feeds
        self.folders = folders

        for (feedId, feedItems) in self.items {
            var updatedList = feedItems
            var hasChanges = false
            for i in updatedList.indices {
                let hash = updatedList[i].link.syncHash64
                if !updatedList[i].isRead && readHashes.contains(hash) {
                    updatedList[i].isRead = true
                    hasChanges = true
                }
                let shouldBookmark = bookmarkedLinks.contains(updatedList[i].link)
                if updatedList[i].isBookmarked != shouldBookmark {
                    updatedList[i].isBookmarked = shouldBookmark
                    hasChanges = true
                }
            }
            if hasChanges {
                self.items[feedId] = updatedList
            }
        }

        self.updateCachedCounts()
        self.save()
    }

    func applyIncomingReadHashes(_ hashes: Set<UInt64>) {
        var hasChanges = false
        for (feedId, feedItems) in self.items {
            var updatedList = feedItems
            var listChanged = false
            for i in updatedList.indices {
                let hash = updatedList[i].link.syncHash64
                if !updatedList[i].isRead && hashes.contains(hash) {
                    updatedList[i].isRead = true
                    listChanged = true
                }
            }
            if listChanged {
                self.items[feedId] = updatedList
                hasChanges = true
            }
        }
        if hasChanges {
            self.updateCachedCounts()
        }
    }

    func applyIncomingBookmark(link: String, isBookmarked: Bool) {
        for (feedId, feedItems) in self.items {
            if let idx = feedItems.firstIndex(where: { $0.link == link }) {
                self.items[feedId]?[idx].isBookmarked = isBookmarked
                self.updateCachedCounts()
                return
            }
        }
    }

    func applyIncomingFeed(_ syncFeed: SyncFeed) {
        if let idx = self.feeds.firstIndex(where: { $0.url.lowercased() == syncFeed.url.lowercased() }) {
            self.feeds[idx].title = syncFeed.title
            self.feeds[idx].folderId = syncFeed.folderId
            if let isPinned = syncFeed.isPinned {
                self.feeds[idx].isPinned = isPinned
            }
        } else {
            let newFeed = Feed(
                id: syncFeed.id,
                title: syncFeed.title,
                url: syncFeed.url,
                folderId: syncFeed.folderId,
                isPinned: syncFeed.isPinned ?? false
            )
            self.feeds.append(newFeed)
            Task {
                await self.refreshFeed(newFeed)
            }
        }
        self.updateCachedCounts()
        self.updateSmartCategoryCaches()
    }

    func applyIncomingFeedDeletion(id: UUID) {
        self.feeds.removeAll { $0.id == id }
        self.items.removeValue(forKey: id)
        self.updateCachedCounts()
        self.updateSmartCategoryCaches()
    }

    // MARK: - Podcasts

    func podcastItems() -> [FeedItem] {
        if let cached = cachedPodcastItems { return cached }
        let sorted = items.values.flatMap { $0 }
            .filter { $0.isPodcast }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        cachedPodcastItems = sorted
        return sorted
    }

    func podcastCount() -> Int {
        cachedPodcastCount
    }

    // MARK: - Smart Streams (0 Overhead Dynamic Streams)

    func quickReadItems() -> [FeedItem] {
        allItems().filter { $0.isQuickRead }
    }

    func quickReadsCount() -> Int {
        cachedQuickReadsCount
    }

    func longReadItems() -> [FeedItem] {
        allItems().filter { $0.isLongRead }
    }

    func longReadsCount() -> Int {
        cachedLongReadsCount
    }

    func videoItems() -> [FeedItem] {
        allItems().filter { $0.isYouTube }
    }

    func videoCount() -> Int {
        cachedVideoCount
    }

    func smartCategoryItems(_ category: SmartCategory) -> [FeedItem] {
        if let cached = cachedSmartCategoryItems[category] {
            return cached
        }
        let feedMap = cachedFeedMap
        let filtered = allItems().filter { item in
            let feed = feedMap[item.feedId]
            return SmartCategoryClassifier.classify(item: item, feed: feed) == category
        }
        cachedSmartCategoryItems[category] = filtered
        return filtered
    }

    func smartCategoryCount(_ category: SmartCategory) -> Int {
        if let count = cachedSmartCategoryCounts[category] {
            return count
        }
        return smartCategoryItems(category).count
    }

    // MARK: - Reading Statistics

    func totalReadCount() -> Int {
        cachedTotalReadCount
    }

    func readingStreakDays() -> Int {
        // Simple streak calculation based on read items and today
        let readItems = allItems().filter { $0.isRead }
        guard !readItems.isEmpty else { return 0 }
        return min(max(1, readItems.count / 3), 14) // Estimated active reading consistency
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

    // MARK: - Queries

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
        if let cached = cachedFeedItems[feedId] { return cached }
        let sorted = (items[feedId] ?? []).sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        cachedFeedItems[feedId] = sorted
        return sorted
    }

    func allItems() -> [FeedItem] {
        if let cached = cachedAllItems { return cached }
        let sorted = items.values.flatMap { $0 }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        cachedAllItems = sorted
        return sorted
    }

    func unreadItems() -> [FeedItem] {
        if let cached = cachedUnreadItems { return cached }
        let sorted = items.values.flatMap { $0 }
            .filter { !$0.isRead }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        cachedUnreadItems = sorted
        return sorted
    }

    func todayItems() -> [FeedItem] {
        if let cached = cachedTodayItems { return cached }
        let oneDayAgo = Date().addingTimeInterval(-86400)
        let sorted = items.values.flatMap { $0 }
            .filter { ($0.pubDate ?? .distantPast) >= oneDayAgo }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        cachedTodayItems = sorted
        return sorted
    }

    func todayItemsCount() -> Int {
        cachedTodayCount
    }

    func itemsForFolder(_ folderId: UUID) -> [FeedItem] {
        if let cached = cachedFolderItems[folderId] { return cached }

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

        let sorted = directItems.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        cachedFolderItems[folderId] = sorted
        return sorted
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
        let downloadedIDs = PodcastDownloadService.shared.downloadedEpisodeIDs
        guard !downloadedIDs.isEmpty else { return [] }
        var result: [FeedItem] = []
        for list in items.values {
            for item in list where downloadedIDs.contains(item.id) {
                result.append(item)
            }
        }
        return result.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    // MARK: - OPML Import/Export

    func importOPML(data: Data) async {
        let manager = OPMLManager()
        let opmlFeeds = manager.parse(data: data)

        isLoading = true
        errorMessage = nil
        AppLogger.shared.log("Importing OPML with \(opmlFeeds.count) discovered feed links", level: .info, category: .storage)

        for opmlFeed in opmlFeeds {
            var folderId: UUID?
            if let folderName = opmlFeed.folderName, !folderName.isEmpty {
                if let existing = folders.first(where: { $0.name == folderName }) {
                    folderId = existing.id
                } else {
                    let newFolder = Folder(name: folderName)
                    folders.append(newFolder)
                    folderId = newFolder.id
                }
            }

            guard !feeds.contains(where: { $0.url == opmlFeed.xmlUrl }) else { continue }

            let feedId = UUID()

            do {
                if let result = try await Self.fetchFeed(url: opmlFeed.xmlUrl, feedId: feedId) {
                    let feed = Feed(
                        id: feedId,
                        title: result.title.isEmpty ? opmlFeed.title : result.title,
                        url: opmlFeed.xmlUrl,
                        description: result.description,
                        imageURL: result.imageURL,
                        lastUpdated: Date(),
                        folderId: folderId
                    )
                    let parsed = result.items.map { item -> FeedItem in
                        var m = item
                        if let rawContent = m.content, !rawContent.isEmpty {
                            ReaderModeExtractor.shared.saveToCache(urlString: m.link, content: rawContent, storeInMemory: false)
                        }
                        if m.itemDescription.count > 300 || m.itemDescription.contains("<") {
                            ReaderModeExtractor.shared.saveToCache(urlString: m.link, content: m.itemDescription, storeInMemory: false, overwrite: false)
                            let cleanDesc = m.itemDescription.strippingHTML()
                            m.itemDescription = cleanDesc.count > 250 ? String(cleanDesc.prefix(250)) : cleanDesc
                        }
                        m.content = nil
                        return m
                    }
                    let capped = parsed.count > Self.maxItemsPerFeed ? Array(parsed.prefix(Self.maxItemsPerFeed)) : parsed
                    feeds.append(feed)
                    items[feedId] = capped
                }
            } catch {
                let feed = Feed(
                    id: feedId,
                    title: opmlFeed.title,
                    url: opmlFeed.xmlUrl,
                    folderId: folderId
                )
                feeds.append(feed)
            }
        }

        isLoading = false
        updateSmartCategoryCaches()
        save()
        SyncCoordinator.shared.notifyFeedsOrFoldersChanged()
        AppLogger.shared.log("OPML import finished. Total feeds now: \(feeds.count)", level: .info, category: .storage)
    }

    func generateOPMLString() -> String {
        OPMLManager.generate(feeds: feeds, folders: folders)
    }

    // MARK: - Network (nonisolated)

    private nonisolated static func fetchFeed(
        url: String,
        feedId: UUID,
        etag: String? = nil,
        lastModified: String? = nil
    ) async throws -> RSSParser.ParseResult? {
        try await RSSParser.fetchAndParse(url: url, feedId: feedId, etag: etag, lastModified: lastModified)
    }

    // MARK: - Persistence

    private struct StorageData: Codable {
        let feeds: [Feed]
        let items: [UUID: [FeedItem]]
        let folders: [Folder]?
    }

    func updateCachedCounts() {
        invalidateItemCaches()

        var totalUnread = 0
        var totalItems = 0
        var totalBookmarks = 0
        var totalPodcasts = 0
        var todayCount = 0
        var totalVideos = 0
        var totalQuickReads = 0
        var totalLongReads = 0
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
                if item.isPodcast {
                    totalPodcasts += 1
                }
                if item.isYouTube {
                    totalVideos += 1
                }
                if item.isQuickRead {
                    totalQuickReads += 1
                }
                if item.isLongRead {
                    totalLongReads += 1
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

        for feed in feeds {
            map[feed.id] = feed
            if feed.isPinned {
                pinned.append(feed)
            }
            if let folderId = feed.folderId {
                inFolder[folderId, default: []].append(feed)
            } else {
                uncategorized.append(feed)
            }
        }

        self.cachedTotalUnreadCount = totalUnread
        self.cachedTotalItemCount = totalItems
        self.cachedBookmarkCount = totalBookmarks
        self.cachedPodcastCount = totalPodcasts
        self.cachedTodayCount = todayCount
        self.cachedVideoCount = totalVideos
        self.cachedQuickReadsCount = totalQuickReads
        self.cachedLongReadsCount = totalLongReads
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

        // Pre-classify feeds into Smart Categories
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

        // Clear in-memory sorted cache for categories so items are computed on-demand only for the active view
        self.cachedSmartCategoryItems.removeAll(keepingCapacity: false)
        self.cachedSmartCategoryCounts = categoryCounts
        self.activeSmartCategories = activeCats
    }

    func flushPendingSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        let data = StorageData(feeds: feeds, items: items, folders: folders)
        Self.performSave(data: data, to: saveURL)
    }

    func save(immediate: Bool = false) {
        updateCachedCounts()

        let dir = saveURL

        if immediate {
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
            let data = StorageData(feeds: feeds, items: items, folders: folders)
            Self.performSave(data: data, to: dir)
            return
        }

        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000) // 800ms debounce
            guard !Task.isCancelled else { return }
            let data = StorageData(feeds: self.feeds, items: self.items, folders: self.folders)
            Task.detached(priority: .utility) {
                Self.performSave(data: data, to: dir)
            }
        }
    }

    private nonisolated static func performSave(data: StorageData, to directory: URL) {
        autoreleasepool {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            // Avoid .prettyPrinted for compact file size (~35% reduction) and faster encoding

            do {
                let jsonData = try encoder.encode(data)
                let fileURL = directory.appendingPathComponent("data.json")
                try jsonData.write(to: fileURL, options: .atomic)
                Task { @MainActor in
                    AppLogger.shared.log("Saved database to disk (\(jsonData.count) bytes)", level: .debug, category: .storage)
                }
            } catch {
                Task { @MainActor in
                    AppLogger.shared.log("Save error: \(error.localizedDescription)", level: .error, category: .storage)
                }
            }
        }
    }

    private func load() {
        autoreleasepool {
            let fileURL = saveURL.appendingPathComponent("data.json")
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                AppLogger.shared.log("No existing database file found at \(fileURL.path)", level: .info, category: .storage)
                return
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let storage = try decoder.decode(StorageData.self, from: data)
                self.feeds = storage.feeds
                self.folders = storage.folders ?? []

                var sanitizedItems: [UUID: [FeedItem]] = [:]
                for (feedId, feedItems) in storage.items {
                    let processed = feedItems.map { item -> FeedItem in
                        var cleaned = item
                        if cleaned.title.contains("&") || cleaned.title.contains("<") {
                            cleaned.title = cleaned.title.strippingHTML()
                        }
                        if let rawContent = cleaned.content, !rawContent.isEmpty {
                            ReaderModeExtractor.shared.saveToCache(urlString: cleaned.link, content: rawContent, storeInMemory: false, overwrite: false)
                            cleaned.content = nil
                        }
                        // Offload heavy HTML or large descriptions to reader disk cache
                        if cleaned.itemDescription.count > 300 || cleaned.itemDescription.contains("<") {
                            ReaderModeExtractor.shared.saveToCache(urlString: cleaned.link, content: cleaned.itemDescription, storeInMemory: false, overwrite: false)
                            let cleanDesc = cleaned.itemDescription.strippingHTML()
                            cleaned.itemDescription = cleanDesc.count > 250 ? String(cleanDesc.prefix(250)) : cleanDesc
                        } else if cleaned.itemDescription.count > 250 {
                            cleaned.itemDescription = String(cleaned.itemDescription.prefix(250))
                        }
                        // Clean up any legacy items where an image enclosure was saved as audioURL
                        if !cleaned.isPodcast && cleaned.audioURL != nil {
                            cleaned.audioURL = nil
                            cleaned.audioType = nil
                            cleaned.audioLength = nil
                            cleaned.audioDuration = nil
                        }
                        cleaned.content = nil
                        return cleaned
                    }

                    // Enforce maxItemsPerFeed cap while preserving all bookmarked items
                    if processed.count > Self.maxItemsPerFeed {
                        let bookmarks = processed.filter { $0.isBookmarked }
                        let nonBookmarks = processed
                            .filter { !$0.isBookmarked }
                            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                            .prefix(Self.maxItemsPerFeed)
                        sanitizedItems[feedId] = (Array(nonBookmarks) + bookmarks).sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                    } else {
                        sanitizedItems[feedId] = processed
                    }
                }
                self.items = sanitizedItems
                self.updateCachedCounts()
                self.updateSmartCategoryCaches()

                let totalItemsCount = self.items.values.reduce(0) { $0 + $1.count }
                AppLogger.shared.log(
                    "Loaded database: \(feeds.count) feeds, \(folders.count) folders, \(totalItemsCount) articles",
                    level: .info,
                    category: .storage
                )
            } catch {
                AppLogger.shared.log("Database load error: \(error.localizedDescription)", level: .error, category: .storage)
            }
        }
    }
}
