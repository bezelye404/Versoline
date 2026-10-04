import Testing
import Foundation
@testable import Versoline

@Suite("Nearby Sync Tests")
@MainActor
struct NearbySyncTests {

    private func syncFeed(_ url: String, title: String = "T", folderId: UUID? = nil) -> SyncFeed {
        SyncFeed(id: UUID(), title: title, url: url, folderId: folderId, isPinned: nil, updatedAt: Date())
    }

    // MARK: - Validator

    @Test("Only plain web URLs are accepted for incoming feeds")
    func feedURLSchemes() {
        #expect(SyncEventValidator.isAcceptable(.feedAddedOrUpdated(feed: syncFeed("https://example.com/feed.xml"))))
        #expect(SyncEventValidator.isAcceptable(.feedAddedOrUpdated(feed: syncFeed("http://example.com/feed.xml"))))
        for bad in ["file:///etc/passwd", "javascript:alert(1)", "ftp://example.com/f", "not a url", "https://"] {
            #expect(!SyncEventValidator.isAcceptable(.feedAddedOrUpdated(feed: syncFeed(bad))), "should reject \(bad)")
        }
    }

    @Test("Oversized lists and strings are rejected")
    func limits() {
        #expect(!SyncEventValidator.isAcceptable(.readArticles(hashes: Array(repeating: 1, count: SyncEventValidator.maxHashes + 1))))
        #expect(SyncEventValidator.isAcceptable(.readArticles(hashes: Array(repeating: 1, count: SyncEventValidator.maxHashes))))
        let tooManyFeeds = (0...SyncEventValidator.maxFeeds).map { syncFeed("https://example.com/\($0)") }
        #expect(!SyncEventValidator.isAcceptable(.feedSnapshot(feeds: tooManyFeeds, folders: [])))
        #expect(!SyncEventValidator.isAcceptable(.feedAddedOrUpdated(feed: syncFeed("https://example.com/" + String(repeating: "a", count: 3000)))))
        #expect(!SyncEventValidator.isAcceptable(.bookmarkSnapshot(links: [String(repeating: "x", count: 5000)])))
    }

    @Test("Deletion events are range-checked")
    func deletionLimits() {
        let many = (0...SyncEventValidator.maxTombstones).map { Tombstone.feed(url: "https://e.com/\($0)", at: Date()) }
        #expect(!SyncEventValidator.isAcceptable(.tombstoneSnapshot(tombstones: many)))
        #expect(SyncEventValidator.isAcceptable(.tombstoneSnapshot(tombstones: Array(many.prefix(SyncEventValidator.maxTombstones)))))
        #expect(!SyncEventValidator.isAcceptable(.feedDeleted(url: String(repeating: "a", count: 3_000), deletedAt: Date())))
        #expect(!SyncEventValidator.isAcceptable(.folderUpdated(folder: SyncFolder(id: UUID(), name: String(repeating: "n", count: 600), updatedAt: Date()))))
    }

    @Test("Events survive a JSON round trip over the wire format")
    func wireRoundTrip() throws {
        let events: [SyncWireMessage] = [
            .event(.readArticles(hashes: [1, 2, UInt64.max])),
            .event(.bookmarkToggled(link: "https://a.com", isBookmarked: true)),
            .event(.feedSnapshot(feeds: [syncFeed("https://example.com/f")], folders: [SyncFolder(id: UUID(), name: "N", updatedAt: Date(timeIntervalSince1970: 0))])),
            .event(.bookmarkSnapshot(links: ["https://b.com"])),
            .event(.feedDeleted(url: "https://example.com/f", deletedAt: Date(timeIntervalSince1970: 5))),
            .event(.folderUpdated(folder: SyncFolder(id: UUID(), name: "N", updatedAt: Date(timeIntervalSince1970: 6)))),
            .event(.folderDeleted(id: UUID(), deletedAt: Date(timeIntervalSince1970: 7))),
            .event(.tombstoneSnapshot(tombstones: [.feed(url: "https://e.com", at: Date(timeIntervalSince1970: 8)), .folder(id: UUID(), at: Date(timeIntervalSince1970: 9))])),
            .handshake(.pairCommit(Data([1, 2, 3]))),
        ]
        for message in events {
            let decoded = try JSONDecoder().decode(SyncWireMessage.self, from: JSONEncoder().encode(message))
            #expect(decoded == message)
        }
    }

    // MARK: - Applying events to the store

    private func store() throws -> (TestStore, Feed) {
        let ts = try TestStore()
        let feed = Feed(title: "Blog", url: "https://example.com/feed")
        ts.store.feeds = [feed]
        ts.store.items = [feed.id: [
            FeedItem(feedId: feed.id, title: "A", link: "https://example.com/a", isBookmarked: true),
            FeedItem(feedId: feed.id, title: "B", link: "https://example.com/b"),
        ]]
        ts.store.updateCachedCounts()
        return (ts, feed)
    }

    @Test("A bookmark snapshot adds bookmarks and never removes existing ones")
    func bookmarkSnapshotIsUnion() throws {
        let (ts, feed) = try store()
        defer { ts.cleanup() }

        ts.store.applySyncEvent(.bookmarkSnapshot(links: ["https://example.com/b"]))

        let items = try #require(ts.store.items[feed.id])
        #expect(items.allSatisfy { $0.isBookmarked })
        #expect(ts.store.bookmarkCount() == 2)
    }

    @Test("A feed snapshot never touches local bookmarks")
    func feedSnapshotKeepsBookmarks() throws {
        let (ts, feed) = try store()
        defer { ts.cleanup() }
        let remote = syncFeed("https://other.example.com/feed.xml", title: "Remote")

        ts.store.applySyncEvent(.feedSnapshot(feeds: [remote], folders: []))

        #expect(ts.store.feeds.count == 2)
        #expect(ts.store.items[feed.id]?.first { $0.link == "https://example.com/a" }?.isBookmarked == true)
    }

    @Test("Snapshot merge unions feeds and folders and lists feeds with an unknown folder as uncategorized")
    func snapshotMerge() throws {
        let (ts, _) = try store()
        defer { ts.cleanup() }
        let folder = SyncFolder(id: UUID(), name: "Remote Folder", updatedAt: Date())
        let inFolder = syncFeed("https://a.example.com/f", folderId: folder.id)
        let dangling = syncFeed("https://b.example.com/f", folderId: UUID())

        ts.store.applySyncEvent(.feedSnapshot(feeds: [inFolder, dangling], folders: [folder]))

        #expect(ts.store.folders.map { $0.name } == ["Remote Folder"])
        #expect(ts.store.feeds.first { $0.url == inFolder.url }?.folderId == folder.id)
        // A feed whose folder is unknown is listed as uncategorized rather than disappearing.
        #expect(ts.store.uncategorizedFeeds().contains { $0.url == dangling.url })
        #expect(ts.store.feeds.count == 3)
    }

    @Test("An explicit feed update moves the feed between folders, including back to no folder")
    func feedUpdateMovesFolders() throws {
        let (ts, feed) = try store()
        defer { ts.cleanup() }
        let first = ts.store.addFolder(name: "First")
        let second = ts.store.addFolder(name: "Second")
        ts.store.moveFeed(feed.id, toFolder: first.id)

        func update(folder: UUID?, after step: Double = 1) -> SyncPeerEvent {
            .feedAddedOrUpdated(feed: SyncFeed(id: feed.id, title: feed.title, url: feed.url, folderId: folder,
                                               isPinned: false, updatedAt: Date().addingTimeInterval(10 * step)))
        }
        ts.store.applySyncEvent(update(folder: second.id))
        #expect(ts.store.feeds.first?.folderId == second.id)

        ts.store.applySyncEvent(update(folder: nil, after: 2))
        #expect(ts.store.feeds.first?.folderId == nil)

        // A folder this Mac does not have: the reference is kept, but the feed is listed as uncategorized.
        ts.store.applySyncEvent(update(folder: UUID(), after: 3))
        #expect(ts.store.uncategorizedFeeds().map { $0.url } == ["https://example.com/feed"])
    }

    @Test("Invalid events are ignored by the store")
    func invalidIgnored() throws {
        let (ts, _) = try store()
        defer { ts.cleanup() }

        ts.store.applySyncEvent(.feedAddedOrUpdated(feed: syncFeed("file:///etc/passwd")))

        #expect(ts.store.feeds.count == 1)
    }

    @Test("Incoming read states are applied, counted and saved")
    func readStatesPersist() throws {
        let (ts, feed) = try store()
        defer { ts.cleanup() }

        ts.store.applySyncEvent(.readArticles(hashes: ["https://example.com/b".syncHash64]))
        ts.store.flushPendingSave()

        #expect(ts.store.items[feed.id]?.first { $0.link == "https://example.com/b" }?.isRead == true)
        #expect(ts.store.unreadCount(for: feed.id) == 1)
        let reopened = ts.reopen()
        #expect(reopened.items[feed.id]?.first { $0.link == "https://example.com/b" }?.isRead == true)
    }

    @Test("Incoming feed deletion removes the feed and its items")
    func deletion() throws {
        let (ts, feed) = try store()
        defer { ts.cleanup() }

        ts.store.applySyncEvent(.feedDeleted(url: feed.url, deletedAt: Date().addingTimeInterval(1)))

        #expect(ts.store.feeds.isEmpty)
        #expect(ts.store.items[feed.id] == nil)
    }

    // MARK: - Snapshots

    @Test("A snapshot carries feeds, folders, read states and bookmarks in chunks and applies cleanly on another store")
    func snapshotRoundTrip() throws {
        let source = try TestStore(); let target = try TestStore()
        defer { source.cleanup(); target.cleanup() }
        let folder = source.store.addFolder(name: "News")
        let feed = Feed(title: "Blog", url: "https://example.com/feed", folderId: folder.id, isPinned: true)
        source.store.feeds = [feed]
        source.store.items = [feed.id: (0..<5).map {
            FeedItem(feedId: feed.id, title: "I\($0)", link: "https://example.com/\($0)", isRead: $0 < 3, isBookmarked: $0 == 4)
        }]
        let events = source.store.syncSnapshotEvents()

        // The target already has the same articles locally (as after a first refresh).
        let local = Feed(id: feed.id, title: "Blog", url: "https://example.com/feed")
        target.store.feeds = [local]
        target.store.items = [feed.id: (0..<5).map { FeedItem(feedId: feed.id, title: "I\($0)", link: "https://example.com/\($0)") }]
        for event in events {
            #expect(SyncEventValidator.isAcceptable(event))
            target.store.applySyncEvent(event)
        }

        #expect(target.store.folders.map(\.name) == ["News"])
        #expect(target.store.feeds.first?.folderId == folder.id)
        #expect(target.store.feeds.first?.isPinned == true)
        #expect(target.store.items[feed.id]?.filter { $0.isRead }.count == 3)
        #expect(target.store.items[feed.id]?.filter { $0.isBookmarked }.map { $0.title } == ["I4"])
    }

    @Test("Large libraries are split into messages under the validator limits")
    func chunking() throws {
        let ts = try TestStore()
        defer { ts.cleanup() }
        ts.store.feeds = (0..<450).map { Feed(title: "F\($0)", url: "https://example.com/\($0)") }
        let feedId = try #require(ts.store.feeds.first?.id)
        ts.store.items = [feedId: (0..<5_000).map { FeedItem(feedId: feedId, title: "i", link: "https://x.com/\($0)", isRead: true, isBookmarked: $0 < 250) }]

        let events = ts.store.syncSnapshotEvents()

        #expect(events.count > 3)
        for event in events {
            #expect(SyncEventValidator.isAcceptable(event))
            let size = try JSONEncoder().encode(SyncWireMessage.event(event)).count
            #expect(size < 200_000)
        }
    }

    // MARK: - Deletions and edits across two Macs

    /// Two stores that both have the same feed (same URL, different ids), like two Macs after a first sync.
    private func twoMacs() throws -> (a: TestStore, b: TestStore, urlA: Feed, urlB: Feed) {
        let a = try TestStore(); let b = try TestStore()
        let feedA = Feed(title: "Blog", url: "https://example.com/feed", updatedAt: Date(timeIntervalSinceNow: -1_000))
        let feedB = Feed(title: "Blog", url: "https://example.com/feed", updatedAt: Date(timeIntervalSinceNow: -1_000))
        a.store.feeds = [feedA]; a.store.items = [feedA.id: [FeedItem(feedId: feedA.id, title: "x", link: "https://example.com/x")]]
        b.store.feeds = [feedB]; b.store.items = [feedB.id: [FeedItem(feedId: feedB.id, title: "x", link: "https://example.com/x")]]
        return (a, b, feedA, feedB)
    }

    @Test("A feed deleted while the other Mac was offline is deleted there after the next sync")
    func offlineDeletionPropagates() throws {
        let (a, b, feedA, feedB) = try twoMacs()
        defer { a.cleanup(); b.cleanup() }

        a.store.removeFeed(feedA)                       // B is offline
        for event in a.store.syncSnapshotEvents() { b.store.applySyncEvent(event) }   // B reconnects

        #expect(b.store.feeds.isEmpty)
        #expect(b.store.items[feedB.id] == nil)
        #expect(b.store.tombstones.map { $0.key } == ["https://example.com/feed"])
        // Syncing back changes nothing on A.
        for event in b.store.syncSnapshotEvents() { a.store.applySyncEvent(event) }
        #expect(a.store.feeds.isEmpty)
    }

    @Test("Re-adding a deleted feed later wins over the older deletion on every Mac")
    func readdWins() throws {
        let (a, b, feedA, _) = try twoMacs()
        defer { a.cleanup(); b.cleanup() }
        a.store.removeFeed(feedA)
        for event in a.store.syncSnapshotEvents() { b.store.applySyncEvent(event) }
        #expect(b.store.feeds.isEmpty)

        // B re-adds the feed later (what addFeed does: newer updatedAt, no tombstone).
        b.store.tombstones.removeAll()
        b.store.feeds = [Feed(title: "Blog", url: "https://example.com/feed", updatedAt: Date().addingTimeInterval(60))]
        for event in b.store.syncSnapshotEvents() { a.store.applySyncEvent(event) }

        #expect(a.store.feeds.map { $0.url } == ["https://example.com/feed"])
        #expect(a.store.tombstones.isEmpty)
    }

    @Test("Renaming and deleting a folder, moving and unpinning a feed all reach the other Mac")
    func editsPropagate() throws {
        let a = try TestStore(); let b = try TestStore()
        defer { a.cleanup(); b.cleanup() }
        let folder = a.store.addFolder(name: "News")
        let feed = Feed(title: "Blog", url: "https://example.com/feed", folderId: folder.id, isPinned: true, updatedAt: Date(timeIntervalSinceNow: -100))
        a.store.feeds = [feed]
        for event in a.store.syncSnapshotEvents() { b.store.applySyncEvent(event) }
        #expect(b.store.folders.map { $0.name } == ["News"])
        #expect(b.store.feeds.first?.isPinned == true)

        a.store.renameFolder(folder.id, name: "World")
        a.store.setFeedPinned(feed.id, isPinned: false)
        for event in a.store.syncSnapshotEvents() { b.store.applySyncEvent(event) }
        #expect(b.store.folders.map { $0.name } == ["World"])
        #expect(b.store.feeds.first?.isPinned == false)

        a.store.removeFolder(folder.id)
        for event in a.store.syncSnapshotEvents() { b.store.applySyncEvent(event) }
        #expect(b.store.folders.isEmpty)
        // The feed now counts as uncategorized (its folder is gone), so it stays visible.
        #expect(b.store.uncategorizedFeeds().map { $0.url } == ["https://example.com/feed"])
    }

    @Test("Deletion records survive a restart and are dropped after 90 days")
    func tombstonesPersist() throws {
        let ts = try TestStore()
        defer { ts.cleanup() }
        let feed = Feed(title: "Blog", url: "https://example.com/feed")
        ts.store.feeds = [feed]
        ts.store.removeFeed(feed)
        ts.store.tombstones.append(.feed(url: "https://old.example.com/f", at: Date().addingTimeInterval(-91 * 86_400)))
        ts.store.save(immediate: true)

        let reopened = ts.reopen()

        #expect(reopened.tombstones.map { $0.key } == ["https://example.com/feed"])
    }

    @Test("A database from before deletion records existed still loads")
    func legacyDatabaseLoads() throws {
        let ts = try TestStore { dir in
            let json = #"{"feeds":[{"id":"\#(UUID().uuidString)","title":"T","url":"https://example.com/f"}],"items":[],"folders":[]}"#
            try Data(json.utf8).write(to: dir.appendingPathComponent("data.json"))
        }
        defer { ts.cleanup() }

        #expect(!ts.store.loadFailed)
        #expect(ts.store.feeds.count == 1)
        #expect(ts.store.feeds.first?.updatedAt == nil)
        #expect(ts.store.tombstones.isEmpty)
    }
}
