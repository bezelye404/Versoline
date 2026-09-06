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
    }

    // MARK: - Feed Management

    func addFeed(url: String, folderId: UUID? = nil) async {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        if feeds.contains(where: { $0.url == trimmedURL }) {
            errorMessage = String(localized: "This feed has already been added.")
            AppLogger.shared.log("Feed already added: \(trimmedURL)", level: .warning, category: .ui)
            return
        }

        isLoading = true
        errorMessage = nil

        let newFeedId = UUID()
        AppLogger.shared.log("Adding feed: \(trimmedURL)", level: .info, category: .network)

        do {
            let result = try await Self.fetchFeed(url: trimmedURL, feedId: newFeedId)

            guard let result else {
                errorMessage = String(localized: "Could not parse feed. Please ensure it is a valid RSS/Atom URL.")
                AppLogger.shared.log("Parse failed for new feed: \(trimmedURL)", level: .error, category: .parser)
                isLoading = false
                return
            }

            let feed = Feed(
                id: newFeedId,
                title: result.title.isEmpty ? trimmedURL : result.title,
                url: trimmedURL,
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
            AppLogger.shared.log(errorMsg, level: .error, category: .network, details: trimmedURL)
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

        let updatedItems = result.items.map { item in
            var mutableItem = item
            if readLinks.contains(item.link) {
                mutableItem.isRead = true
            }
            if bookmarkedLinks.contains(item.link) {
                mutableItem.isBookmarked = true
            }
            return mutableItem
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
            _ = await ReaderModeExtractor.shared.extract(from: item.link)
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
        var count = 0
        for list in items.values {
            for item in list where item.isBookmarked {
                count += 1
            }
        }
        return count
    }

    // MARK: - Queries

    var totalItemCount: Int {
        items.values.reduce(0) { $0 + $1.count }
    }

    func feed(for id: UUID) -> Feed? {
        feeds.first { $0.id == id }
    }

    func unreadCount(for feedId: UUID) -> Int {
        guard let list = items[feedId] else { return 0 }
        var count = 0
        for item in list where !item.isRead {
            count += 1
        }
        return count
    }

    func totalUnreadCount() -> Int {
        var count = 0
        for list in items.values {
            for item in list where !item.isRead {
                count += 1
            }
        }
        return count
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
        let folderFeedIds = Set(feeds.filter { $0.folderId == folderId }.map { $0.id })
        return items
            .filter { folderFeedIds.contains($0.key) }
            .values.flatMap { $0 }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
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

    private func save() {
        let data = StorageData(feeds: feeds, items: items, folders: folders)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let jsonData = try encoder.encode(data)
            let fileURL = saveURL.appendingPathComponent("data.json")
            try jsonData.write(to: fileURL, options: .atomic)
            AppLogger.shared.log("Saved database to disk (\(jsonData.count) bytes)", level: .debug, category: .storage)
        } catch {
            AppLogger.shared.log("Save error: \(error.localizedDescription)", level: .error, category: .storage)
        }
    }

    private func load() {
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
                    return cleaned
                }
            }
            self.items = sanitizedItems
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
