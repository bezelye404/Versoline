import Testing
import Foundation
@testable import Versoline

@Suite("FeedStore Persistence Tests")
@MainActor
struct FeedStorePersistenceTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func files(in dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path)
    }

    @Test("Starts empty and keeps saving enabled when no database exists")
    func firstLaunch() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = FeedStore(storageDirectory: dir, readerCache: ReaderModeExtractor(cacheDirectory: dir.appendingPathComponent("cache")))

        #expect(!store.loadFailed)
        #expect(store.startupRecoveryNotice == nil)
        #expect(store.feeds.isEmpty)
    }

    @Test("Corrupt database is preserved and never overwritten")
    func corruptDatabaseIsNotOverwritten() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let corrupt = Data("{ not valid json".utf8)
        let dataURL = dir.appendingPathComponent("data.json")
        try corrupt.write(to: dataURL)

        let store = FeedStore(storageDirectory: dir, readerCache: ReaderModeExtractor(cacheDirectory: dir.appendingPathComponent("cache")))

        #expect(store.loadFailed)
        #expect(store.startupRecoveryNotice != nil)
        #expect(try files(in: dir).contains { $0.hasPrefix("data.json.corrupt-") })

        store.save(immediate: true)
        store.flushPendingSave()

        #expect(try Data(contentsOf: dataURL) == corrupt)
    }

    @Test("Successful load writes a data.json.bak copy")
    func backupAfterSuccessfulLoad() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let valid = Data(#"{"feeds":[],"items":[],"folders":[]}"#.utf8)
        try valid.write(to: dir.appendingPathComponent("data.json"))

        let store = FeedStore(storageDirectory: dir, readerCache: ReaderModeExtractor(cacheDirectory: dir.appendingPathComponent("cache")))

        #expect(!store.loadFailed)
        #expect(try Data(contentsOf: dir.appendingPathComponent("data.json.bak")) == valid)
    }

    @Test("Saved library round-trips through a fresh store")
    func roundTrip() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let folder = Folder(name: "News")
        let feed = Feed(title: "Blog", url: "https://example.com/feed", folderId: folder.id, isPinned: true)
        let newer = FeedItem(feedId: feed.id, title: "Newer", link: "https://example.com/2",
                             pubDate: Date(timeIntervalSince1970: 1_800_000_000), isRead: true, isBookmarked: true)
        let older = FeedItem(feedId: feed.id, title: "Older", link: "https://example.com/1",
                             pubDate: Date(timeIntervalSince1970: 1_700_000_000))

        let writer = FeedStore(storageDirectory: dir, readerCache: ReaderModeExtractor(cacheDirectory: dir.appendingPathComponent("cache")))
        writer.folders = [folder]
        writer.feeds = [feed]
        writer.items = [feed.id: [older, newer]]
        writer.save(immediate: true)

        let reader = FeedStore(storageDirectory: dir, readerCache: ReaderModeExtractor(cacheDirectory: dir.appendingPathComponent("cache")))

        #expect(!reader.loadFailed)
        #expect(reader.folders.map(\.id) == [folder.id])
        #expect(reader.feeds.map(\.id) == [feed.id])
        #expect(reader.feeds.first?.isPinned == true)
        #expect(reader.feeds.first?.folderId == folder.id)
        let loaded = try #require(reader.items[feed.id])
        #expect(loaded.map(\.title) == ["Newer", "Older"])
        #expect(loaded.first?.isRead == true)
        #expect(loaded.first?.isBookmarked == true)
    }

    @Test("Per-feed item cap keeps every bookmarked item")
    func itemCapKeepsBookmarks() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let feed = Feed(title: "Busy", url: "https://example.com/busy")
        let total = FeedStore.maxItemsPerFeed + 30
        var all = (0..<total).map { i in
            FeedItem(feedId: feed.id, title: "Item \(i)", link: "https://example.com/\(i)",
                     pubDate: Date(timeIntervalSince1970: Double(1_700_000_000 + i)))
        }
        // The oldest item is bookmarked and would otherwise be cut.
        all[0].isBookmarked = true

        let writer = FeedStore(storageDirectory: dir, readerCache: ReaderModeExtractor(cacheDirectory: dir.appendingPathComponent("cache")))
        writer.feeds = [feed]
        writer.items = [feed.id: all]
        writer.save(immediate: true)

        let reader = FeedStore(storageDirectory: dir, readerCache: ReaderModeExtractor(cacheDirectory: dir.appendingPathComponent("cache")))
        let loaded = try #require(reader.items[feed.id])

        #expect(loaded.count == FeedStore.maxItemsPerFeed + 1)
        #expect(loaded.contains { $0.link == "https://example.com/0" && $0.isBookmarked })
    }
}
