import Foundation
import SwiftUI

@MainActor
@Observable
final class FeedStore {

    var feeds: [Feed] = []
    var items: [UUID: [FeedItem]] = [:]
    var folders: [Folder] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private let saveURL: URL
    private var pendingSaveTask: Task<Void, Never>?

    // Fast O(1) in-memory cached aggregates
    private(set) var cachedTotalUnreadCount: Int = 0
    private(set) var cachedTotalItemCount: Int = 0
    private(set) var cachedBookmarkCount: Int = 0
    private(set) var cachedPodcastCount: Int = 0
    private var cachedFeedUnreadCounts: [UUID: Int] = [:]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("EasyRSS", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.saveURL = appDir
        load()

        let cleanupDays = UserDefaults.standard.integer(forKey: AppSettingsKeys.autoCleanupDays)
        if cleanupDays > 0 {
            autoCleanup(olderThanDays: cleanupDays)
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
            items[newFeedId] = result.items
            isLoading = false
            save()
            AppLogger.shared.log("Successfully added feed \"\(feed.title)\" with \(result.items.count) items", level: .info, category: .storage)
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
        save()
    }

    func refreshFeed(_ feed: Feed) async {
        isLoading = true
        errorMessage = nil
        AppLogger.shared.log("Refreshing single feed: \"\(feed.title)\"", level: .info, category: .network)

        do {
            let result = try await Self.fetchFeed(url: feed.url, feedId: feed.id)

            guard let result else {
                isLoading = false
                return
            }

            applyFeedUpdate(feedId: feed.id, result: result)
            isLoading = false
            save()
        } catch {
            let errorMsg = String(format: String(localized: "Refresh failed: %@"), error.localizedDescription)
            errorMessage = errorMsg
            AppLogger.shared.log(errorMsg, level: .error, category: .network, details: feed.url)
            isLoading = false
        }
    }

    func refreshAllFeeds() async {
        guard !feeds.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        AppLogger.shared.log("Starting concurrent refresh for \(feeds.count) feeds", level: .info, category: .network)

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
                            let result = try await Self.fetchFeed(url: feed.url, feedId: feed.id)
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

        isLoading = false
        save()
        AppLogger.shared.log("All feeds refresh finished", level: .info, category: .network)
    }

    private func applyFeedUpdate(feedId: UUID, result: RSSParser.ParseResult) {
        let existingItems = items[feedId] ?? []
        let readLinks = Set(existingItems.filter { $0.isRead }.map { $0.link })
        let bookmarkedLinks = Set(existingItems.filter { $0.isBookmarked }.map { $0.link })

        var updatedItems = result.items.map { item in
            var mutableItem = item
            if readLinks.contains(item.link) {
                mutableItem.isRead = true
            }
            if bookmarkedLinks.contains(item.link) {
                mutableItem.isBookmarked = true
            }

            // Offload heavy HTML content to disk reader cache so RAM remains completely lean
            if let rawContent = mutableItem.content, !rawContent.isEmpty {
                let formatted = ReaderModeExtractor.shared.formatFeedContentAsReaderHTML(
                    title: mutableItem.title,
                    author: mutableItem.author,
                    pubDate: mutableItem.pubDate,
                    htmlContent: rawContent,
                    link: mutableItem.link
                )
                ReaderModeExtractor.shared.saveToCache(urlString: mutableItem.link, content: formatted, storeInMemory: false)
                mutableItem.content = nil
            }

            return mutableItem
        }

        // Always preserve existing bookmarked items that may have fallen off the feed XML
        let updatedLinks = Set(updatedItems.map { $0.link })
        let preservedBookmarks = existingItems.filter { $0.isBookmarked && !updatedLinks.contains($0.link) }
        if !preservedBookmarks.isEmpty {
            updatedItems.append(contentsOf: preservedBookmarks)
        }

        // Memory safety: Enforce 150 most recent items cap for non-bookmarked items
        if updatedItems.count > 150 {
            let bookmarks = updatedItems.filter { $0.isBookmarked }
            let nonBookmarks = updatedItems
                .filter { !$0.isBookmarked }
                .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                .prefix(150)
            updatedItems = (Array(nonBookmarks) + bookmarks).sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        }

        items[feedId] = updatedItems

        if let index = feeds.firstIndex(where: { $0.id == feedId }) {
            feeds[index].lastUpdated = Date()
            if !result.title.isEmpty {
                feeds[index].title = result.title
            }
        }
    }

    // MARK: - Folder Management

    func addFolder(name: String) {
        let folder = Folder(name: name)
        folders.append(folder)
        AppLogger.shared.log("Added folder: \"\(name)\"", level: .info, category: .storage)
        save()
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
    }

    func renameFolder(_ folderId: UUID, name: String) {
        if let index = folders.firstIndex(where: { $0.id == folderId }) {
            let old = folders[index].name
            folders[index].name = name
            AppLogger.shared.log("Renamed folder \"\(old)\" -> \"\(name)\"", level: .info, category: .storage)
            save()
        }
    }

    func moveFeed(_ feedId: UUID, toFolder folderId: UUID?) {
        if let index = feeds.firstIndex(where: { $0.id == feedId }) {
            feeds[index].folderId = folderId
            save()
        }
    }

    func feedsInFolder(_ folderId: UUID) -> [Feed] {
        feeds.filter { $0.folderId == folderId }
    }

    func uncategorizedFeeds() -> [Feed] {
        feeds.filter { $0.folderId == nil }
    }

    // MARK: - Item Management

    func markAsRead(_ item: FeedItem) {
        guard var feedItems = items[item.feedId],
              let index = feedItems.firstIndex(where: { $0.id == item.id }) else { return }

        feedItems[index].isRead = true
        items[item.feedId] = feedItems
        save()
    }

    func markAllAsRead(feedId: UUID) {
        guard var feedItems = items[feedId] else { return }
        for i in feedItems.indices {
            feedItems[i].isRead = true
        }
        items[feedId] = feedItems
        save()
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

    func precacheArticles(limit: Int = 30) async {
        guard NetworkMonitor.shared.isConnected else { return }
        let unreadArticles = unreadItems().prefix(limit)
        AppLogger.shared.log("Pre-caching \(unreadArticles.count) unread articles for offline reading...", level: .info, category: .network)
        for item in unreadArticles {
            _ = await ReaderModeExtractor.shared.extract(
                from: item.link,
                fallbackContent: item.content ?? item.itemDescription,
                title: item.title,
                author: item.author,
                pubDate: item.pubDate
            )
        }
        AppLogger.shared.log("Offline pre-caching complete", level: .info, category: .storage)
    }

    // MARK: - Bookmarks

    func toggleBookmark(_ item: FeedItem) {
        guard var feedItems = items[item.feedId],
              let index = feedItems.firstIndex(where: { $0.id == item.id }) else { return }

        feedItems[index].isBookmarked.toggle()
        items[item.feedId] = feedItems
        save()
    }

    func bookmarkedItems() -> [FeedItem] {
        items.values.flatMap { $0 }
            .filter { $0.isBookmarked }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    func bookmarkCount() -> Int {
        cachedBookmarkCount
    }

    // MARK: - Podcasts

    func podcastItems() -> [FeedItem] {
        items.values.flatMap { $0 }
            .filter { $0.isPodcast }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    func podcastCount() -> Int {
        cachedPodcastCount
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
        feeds.first { $0.id == id }
    }

    func unreadCount(for feedId: UUID) -> Int {
        cachedFeedUnreadCounts[feedId] ?? 0
    }

    func totalUnreadCount() -> Int {
        cachedTotalUnreadCount
    }

    func itemsForFeed(_ feedId: UUID) -> [FeedItem] {
        (items[feedId] ?? []).sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    func allItems() -> [FeedItem] {
        items.values.flatMap { $0 }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    func unreadItems() -> [FeedItem] {
        items.values.flatMap { $0 }
            .filter { !$0.isRead }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    func todayItems() -> [FeedItem] {
        let oneDayAgo = Date().addingTimeInterval(-86400)
        return items.values.flatMap { $0 }
            .filter { ($0.pubDate ?? .distantPast) >= oneDayAgo }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    func todayItemsCount() -> Int {
        let oneDayAgo = Date().addingTimeInterval(-86400)
        var count = 0
        for list in items.values {
            for item in list where (item.pubDate ?? .distantPast) >= oneDayAgo {
                count += 1
            }
        }
        return count
    }

    func itemsForFolder(_ folderId: UUID) -> [FeedItem] {
        let folder = folders.first(where: { $0.id == folderId })
        let folderFeedIds = Set(feeds.filter { $0.folderId == folderId }.map { $0.id })
        var directItems: [FeedItem] = []
        for (feedId, feedItems) in items where folderFeedIds.contains(feedId) {
            directItems.append(contentsOf: feedItems)
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

        return directItems.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    func itemsCountForFolder(_ folderId: UUID) -> Int {
        let folder = folders.first(where: { $0.id == folderId })
        let folderFeedIds = Set(feeds.filter { $0.folderId == folderId }.map { $0.id })
        var directCount = 0
        for (feedId, feedItems) in items where folderFeedIds.contains(feedId) {
            directCount += feedItems.count
        }

        guard let keywords = folder?.keywords, !keywords.isEmpty else {
            return directCount
        }

        return itemsForFolder(folderId).count
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
                    feeds.append(feed)
                    items[feedId] = result.items
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
        save()
        AppLogger.shared.log("OPML import finished. Total feeds now: \(feeds.count)", level: .info, category: .storage)
    }

    func generateOPMLString() -> String {
        OPMLManager.generate(feeds: feeds, folders: folders)
    }

    // MARK: - Network (nonisolated)

    private nonisolated static func fetchFeed(url: String, feedId: UUID) async throws -> RSSParser.ParseResult? {
        try await RSSParser.fetchAndParse(url: url, feedId: feedId)
    }

    // MARK: - Persistence

    private struct StorageData: Codable {
        let feeds: [Feed]
        let items: [UUID: [FeedItem]]
        let folders: [Folder]?
    }

    func updateCachedCounts() {
        var totalUnread = 0
        var totalItems = 0
        var totalBookmarks = 0
        var totalPodcasts = 0
        var unreadPerFeed: [UUID: Int] = [:]

        for (feedId, list) in items {
            var feedUnread = 0
            totalItems += list.count
            for item in list {
                if !item.isRead {
                    feedUnread += 1
                    totalUnread += 1
                }
                if item.isBookmarked {
                    totalBookmarks += 1
                }
                if item.isPodcast {
                    totalPodcasts += 1
                }
            }
            unreadPerFeed[feedId] = feedUnread
        }

        self.cachedTotalUnreadCount = totalUnread
        self.cachedTotalItemCount = totalItems
        self.cachedBookmarkCount = totalBookmarks
        self.cachedPodcastCount = totalPodcasts
        self.cachedFeedUnreadCounts = unreadPerFeed
    }

    func flushPendingSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        let data = StorageData(feeds: feeds, items: items, folders: folders)
        Self.performSave(data: data, to: saveURL)
    }

    func save(immediate: Bool = false) {
        updateCachedCounts()

        let data = StorageData(feeds: feeds, items: items, folders: folders)
        let dir = saveURL

        if immediate {
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
            Self.performSave(data: data, to: dir)
            return
        }

        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000) // 800ms debounce
            guard !Task.isCancelled else { return }
            Task.detached(priority: .utility) {
                Self.performSave(data: data, to: dir)
            }
        }
    }

    private nonisolated static func performSave(data: StorageData, to directory: URL) {
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
                    sanitizedItems[feedId] = feedItems.map { item in
                        var cleaned = item
                        if cleaned.title.contains("&") || cleaned.title.contains("<") {
                            cleaned.title = cleaned.title.strippingHTML()
                        }
                        if cleaned.itemDescription.contains("&") {
                            cleaned.itemDescription = cleaned.itemDescription.decodingHTMLEntities()
                        }
                        if cleaned.snippet.isEmpty {
                            cleaned.snippet = cleaned.itemDescription.strippingHTML()
                        }
                        // Offload heavy HTML content to disk reader cache so RAM is never bloated
                        if let rawContent = cleaned.content, !rawContent.isEmpty {
                            let formatted = ReaderModeExtractor.shared.formatFeedContentAsReaderHTML(
                                title: cleaned.title,
                                author: cleaned.author,
                                pubDate: cleaned.pubDate,
                                htmlContent: rawContent,
                                link: cleaned.link
                            )
                            ReaderModeExtractor.shared.saveToCache(urlString: cleaned.link, content: formatted, storeInMemory: false)
                            cleaned.content = nil
                        }
                        return cleaned
                    }
                }
                self.items = sanitizedItems
                self.updateCachedCounts()

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
