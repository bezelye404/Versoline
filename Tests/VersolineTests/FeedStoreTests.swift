import Testing
import Foundation
@testable import Versoline

@Suite("FeedStore Behaviour Tests")
@MainActor
struct FeedStoreTests {

    private func makeItem(
        feedId: UUID, _ n: Int, read: Bool = false, bookmarked: Bool = false, daysAgo: Int = 0
    ) -> FeedItem {
        FeedItem(
            feedId: feedId, title: "Item \(n)", link: "https://example.com/\(feedId.uuidString)/\(n)",
            pubDate: Date().addingTimeInterval(-Double(daysAgo) * 86400),
            isRead: read, isBookmarked: bookmarked
        )
    }

    /// Store with one feed and the given items.
    private func seeded(_ build: (UUID) -> [FeedItem]) throws -> (TestStore, Feed) {
        let ts = try TestStore()
        let feed = Feed(title: "Blog", url: "https://example.com/feed")
        ts.store.feeds = [feed]
        ts.store.items = [feed.id: build(feed.id)]
        ts.store.updateCachedCounts()
        return (ts, feed)
    }

    // MARK: - Read state

    @Test("markAsRead updates item, per-feed and total unread counts once")
    func markAsRead() throws {
        let (ts, feed) = try seeded { id in (0..<3).map { makeItem(feedId: id, $0) } }
        defer { ts.cleanup() }
        let store = ts.store
        #expect(store.unreadCount(for: feed.id) == 3)

        let target = store.items[feed.id]![0]
        store.markAsRead(target)
        store.markAsRead(target) // second call is a no-op

        #expect(store.unreadCount(for: feed.id) == 2)
        #expect(store.totalUnreadCount() == 2)
        #expect(store.items[feed.id]!.first { $0.id == target.id }?.isRead == true)
    }

    @Test("toggleReadStatus flips state and keeps counts consistent")
    func toggleRead() throws {
        let (ts, feed) = try seeded { id in [makeItem(feedId: id, 0)] }
        defer { ts.cleanup() }
        let store = ts.store
        let item = store.items[feed.id]![0]

        store.toggleReadStatus(item)
        #expect(store.unreadCount(for: feed.id) == 0)
        #expect(store.totalReadCount() == 1)

        store.toggleReadStatus(store.items[feed.id]![0])
        #expect(store.unreadCount(for: feed.id) == 1)
        #expect(store.totalReadCount() == 0)
    }

    @Test("markAllAsRead and markAllAsUnread cover the whole feed")
    func markAll() throws {
        let (ts, feed) = try seeded { id in (0..<4).map { makeItem(feedId: id, $0, read: $0 == 0) } }
        defer { ts.cleanup() }
        let store = ts.store

        store.markAllAsRead(feedId: feed.id)
        #expect(store.unreadCount(for: feed.id) == 0)
        #expect(store.allRead(feedId: feed.id))

        store.markAllAsUnread(feedId: feed.id)
        #expect(store.unreadCount(for: feed.id) == 4)
        #expect(!store.allRead(feedId: feed.id))
    }

    @Test("markAllAsRead(items:) only touches the given items")
    func markSelectedAsRead() throws {
        let (ts, feed) = try seeded { id in (0..<3).map { makeItem(feedId: id, $0) } }
        defer { ts.cleanup() }
        let store = ts.store
        let chosen = Array(store.items[feed.id]!.prefix(2))

        store.markAllAsRead(items: chosen)

        #expect(store.unreadCount(for: feed.id) == 1)
    }

    // MARK: - Bookmarks

    @Test("toggleBookmark adds and removes bookmarks and the cached count")
    func bookmarks() throws {
        let (ts, feed) = try seeded { id in (0..<2).map { makeItem(feedId: id, $0) } }
        defer { ts.cleanup() }
        let store = ts.store
        let item = store.items[feed.id]![0]

        store.toggleBookmark(item)
        #expect(store.bookmarkCount() == 1)
        #expect(store.bookmarkedItems().map(\.id) == [item.id])

        store.toggleBookmark(store.items[feed.id]!.first { $0.id == item.id }!)
        #expect(store.bookmarkCount() == 0)

        // By design the active view keeps the row (with its updated flag) until the view
        // changes, so an accidental un-bookmark can be undone in place.
        #expect(store.bookmarkedItems().first?.isBookmarked == false)
        _ = store.todayItems() // switch the active view
        #expect(store.bookmarkedItems().isEmpty)
    }

    // MARK: - Auto cleanup

    @Test("autoCleanup removes old read items but keeps unread, bookmarked and recent ones")
    func autoCleanup() throws {
        let (ts, feed) = try seeded { id in [
            makeItem(feedId: id, 0, read: true, daysAgo: 60),                    // removed
            makeItem(feedId: id, 1, read: false, daysAgo: 60),                   // unread: kept
            makeItem(feedId: id, 2, read: true, bookmarked: true, daysAgo: 60),  // bookmarked: kept
            makeItem(feedId: id, 3, read: true, daysAgo: 1),                     // recent: kept
        ] }
        defer { ts.cleanup() }
        let store = ts.store

        store.autoCleanup(olderThanDays: 30)

        let titles = Set(store.items[feed.id]!.map(\.title))
        #expect(titles == ["Item 1", "Item 2", "Item 3"])
    }

    @Test("autoCleanup with zero days does nothing")
    func autoCleanupDisabled() throws {
        let (ts, feed) = try seeded { id in [makeItem(feedId: id, 0, read: true, daysAgo: 400)] }
        defer { ts.cleanup() }

        ts.store.autoCleanup(olderThanDays: 0)

        #expect(ts.store.items[feed.id]?.count == 1)
    }

    // MARK: - Folders and feeds

    @Test("Folder lifecycle: add, rename, move feed, remove")
    func folderLifecycle() throws {
        let ts = try TestStore()
        defer { ts.cleanup() }
        let store = ts.store
        let feed = Feed(title: "Blog", url: "https://example.com/feed")
        store.feeds = [feed]

        let folder = store.addFolder(name: "News")
        #expect(store.folders.map(\.name) == ["News"])

        store.renameFolder(folder.id, name: "World")
        #expect(store.folders.first?.name == "World")

        store.moveFeed(feed.id, toFolder: folder.id)
        #expect(store.feedsInFolder(folder.id).map(\.id) == [feed.id])

        store.removeFolder(folder.id)
        #expect(store.folders.isEmpty)
        #expect(store.feeds.first?.folderId == nil)
    }

    @Test("setFeedsInFolder assigns and unassigns feeds")
    func setFeedsInFolder() throws {
        let ts = try TestStore()
        defer { ts.cleanup() }
        let store = ts.store
        let a = Feed(title: "A", url: "https://example.com/a")
        let b = Feed(title: "B", url: "https://example.com/b")
        store.feeds = [a, b]
        let folder = store.addFolder(name: "F")

        store.setFeedsInFolder(folder.id, feedIds: [a.id])
        #expect(store.feedsInFolder(folder.id).map(\.id) == [a.id])

        store.setFeedsInFolder(folder.id, feedIds: [b.id])
        #expect(store.feedsInFolder(folder.id).map(\.id) == [b.id])
    }

    @Test("Pinning toggles and is reflected in pinnedFeeds")
    func pinning() throws {
        let ts = try TestStore()
        defer { ts.cleanup() }
        let store = ts.store
        let feed = Feed(title: "A", url: "https://example.com/a")
        store.feeds = [feed]

        store.togglePin(feedId: feed.id)
        #expect(store.isPinned(feedId: feed.id))
        #expect(store.pinnedFeeds().map(\.id) == [feed.id])

        store.togglePin(feedId: feed.id)
        #expect(!store.isPinned(feedId: feed.id))
    }

    @Test("Removing a feed drops its items")
    func removeFeed() throws {
        let (ts, feed) = try seeded { id in [makeItem(feedId: id, 0)] }
        defer { ts.cleanup() }

        ts.store.removeFeed(feed)

        #expect(ts.store.feeds.isEmpty)
        #expect(ts.store.items[feed.id] == nil)
    }

    // MARK: - Streams

    @Test("Streams list matching items newest first and counts agree with the lists")
    func streams() throws {
        let ts = try TestStore()
        defer { ts.cleanup() }
        let store = ts.store
        let feed = Feed(title: "Mixed", url: "https://example.com/feed")
        let now = Date()

        let podcast = FeedItem(feedId: feed.id, title: "Ep", link: "https://example.com/ep",
                               pubDate: now, audioURL: "https://cdn.example.com/ep.mp3", audioType: "audio/mpeg")
        let oldVideo = FeedItem(feedId: feed.id, title: "Old video", link: "https://www.youtube.com/watch?v=aaa",
                                pubDate: now.addingTimeInterval(-7200))
        let newVideo = FeedItem(feedId: feed.id, title: "New video", link: "https://youtu.be/bbb",
                                pubDate: now.addingTimeInterval(-60))
        let article = FeedItem(feedId: feed.id, title: "Article", link: "https://example.com/a",
                               itemDescription: "short text", pubDate: now)
        let longArticle = FeedItem(feedId: feed.id, title: "Long", link: "https://example.com/long",
                                   pubDate: now, content: String(repeating: "word ", count: 1600))

        store.feeds = [feed]
        store.items = [feed.id: [podcast, oldVideo, newVideo, article, longArticle]]
        store.updateCachedCounts()

        #expect(store.items(for: .podcasts).map(\.title) == ["Ep"])
        #expect(store.items(for: .videos).map(\.title) == ["New video", "Old video"])
        #expect(store.items(for: .longReads).map(\.title) == ["Long"])
        #expect(Set(store.items(for: .quickReads).map(\.title)).isSuperset(of: ["Article", "Old video", "New video"]))
        #expect(!store.items(for: .quickReads).contains { $0.title == "Ep" })

        for stream in ItemStream.allCases {
            #expect(store.count(for: stream) == store.items(for: stream).count)
        }
    }

    @Test("sortedNewestFirst puts undated items last")
    func sortOrder() {
        let id = UUID()
        let undated = FeedItem(feedId: id, title: "undated", link: "u")
        let old = FeedItem(feedId: id, title: "old", link: "o", pubDate: Date(timeIntervalSince1970: 100))
        let new = FeedItem(feedId: id, title: "new", link: "n", pubDate: Date(timeIntervalSince1970: 200))

        #expect([undated, old, new].sortedNewestFirst().map(\.title) == ["new", "old", "undated"])
    }
}
