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
    }

    // MARK: - Feed Management

    func addFeed(url: String, folderId: UUID? = nil) async {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        if feeds.contains(where: { $0.url == trimmedURL }) {
            errorMessage = "Bu feed zaten eklenmiş."
            return
        }

        isLoading = true
        errorMessage = nil

        let newFeedId = UUID()

        do {
            let result = try await Self.fetchFeed(url: trimmedURL, feedId: newFeedId)

            guard let result else {
                errorMessage = "Feed parse edilemedi. Geçerli bir RSS/Atom URL'si olduğundan emin olun."
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
        } catch {
            errorMessage = "Feed yüklenemedi: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func removeFeed(_ feed: Feed) {
        feeds.removeAll { $0.id == feed.id }
        items.removeValue(forKey: feed.id)
        save()
    }

    func refreshFeed(_ feed: Feed) async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await Self.fetchFeed(url: feed.url, feedId: feed.id)

            guard let result else {
                isLoading = false
                return
            }

            // Preserve read and bookmark status
            let existingItems = items[feed.id] ?? []
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

            items[feed.id] = updatedItems

            if let index = feeds.firstIndex(where: { $0.id == feed.id }) {
                feeds[index].lastUpdated = Date()
                if !result.title.isEmpty {
                    feeds[index].title = result.title
                }
            }

            isLoading = false
            save()
        } catch {
            errorMessage = "Yenileme başarısız: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func refreshAllFeeds() async {
        for feed in feeds {
            await refreshFeed(feed)
        }
    }

    // MARK: - Folder Management

    func addFolder(name: String) {
        let folder = Folder(name: name)
        folders.append(folder)
        save()
    }

    func removeFolder(_ folderId: UUID) {
        // Move feeds out of folder first
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
            folders[index].name = name
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
        items.values.flatMap { $0 }.filter { $0.isBookmarked }.count
    }

    // MARK: - Queries

    func feed(for id: UUID) -> Feed? {
        feeds.first { $0.id == id }
    }

    func unreadCount(for feedId: UUID) -> Int {
        items[feedId]?.filter { !$0.isRead }.count ?? 0
    }

    func totalUnreadCount() -> Int {
        items.values.flatMap { $0 }.filter { !$0.isRead }.count
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
        return items.values.flatMap { $0 }.filter { ($0.pubDate ?? .distantPast) >= oneDayAgo }.count
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

        for opmlFeed in opmlFeeds {
            // Find or create folder
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

            // Skip if feed already exists
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
                // Add feed entry even if fetch fails
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
        } catch {
            print("Kaydetme hatası: \(error)")
        }
    }

    private func load() {
        let fileURL = saveURL.appendingPathComponent("data.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let storage = try decoder.decode(StorageData.self, from: data)
            self.feeds = storage.feeds
            self.items = storage.items
            self.folders = storage.folders ?? []
        } catch {
            print("Yükleme hatası: \(error)")
        }
    }
}
