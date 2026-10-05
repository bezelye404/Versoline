import Testing
import Foundation
@testable import Versoline

@MainActor
struct LibraryBackupTests {

    private func populated(_ store: FeedStore) -> (Feed, [FeedItem]) {
        let feed = Feed(title: "News", url: "https://news.example.com/rss")
        store.feeds.append(feed)
        let items = [
            FeedItem(feedId: feed.id, title: "One", link: "https://news.example.com/1", pubDate: Date(), isRead: true),
            FeedItem(feedId: feed.id, title: "Two", link: "https://news.example.com/2", pubDate: Date(), isBookmarked: true),
        ]
        store.items[feed.id] = items
        store.folders.append(Folder(name: "Daily"))
        return (feed, items)
    }

    @Test func aBackupRoundTripsTheLibrary() throws {
        let source = try TestStore(); defer { source.cleanup() }
        let (feed, items) = populated(source.store)
        let data = try source.store.backupData()

        let envelope = try LibraryBackup.read(data)
        #expect(LibraryBackup.summary(of: envelope).feeds == 1)
        #expect(LibraryBackup.summary(of: envelope).articles == 2)

        let target = try TestStore(); defer { target.cleanup() }
        target.store.restoreBackup(envelope)
        #expect(target.store.feeds.map(\.id) == [feed.id])
        #expect(target.store.folders.map(\.name) == ["Daily"])
        let restored = try #require(target.store.items[feed.id])
        #expect(Set(restored.map(\.id)) == Set(items.map(\.id)))
        #expect(restored.first { $0.title == "One" }?.isRead == true)
        #expect(restored.first { $0.title == "Two" }?.isBookmarked == true)
        #expect(target.store.totalUnreadCount() == 1)
    }

    @Test func restoringKeepsTheLibraryItReplaces() throws {
        let store = try TestStore(); defer { store.cleanup() }
        _ = populated(store.store)
        store.store.save(immediate: true)

        let other = try TestStore(); defer { other.cleanup() }
        let envelope = try LibraryBackup.read(other.store.backupData())   // an empty library
        store.store.restoreBackup(envelope)

        #expect(store.store.feeds.isEmpty)
        let kept = store.directory.appendingPathComponent("data.json.before-restore")
        #expect(FileManager.default.fileExists(atPath: kept.path))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(FeedStore.StorageData.self, from: Data(contentsOf: kept))
        #expect(old.feeds.count == 1)
    }

    @Test func filesThatAreNotBackupsAreRefused() throws {
        #expect(throws: LibraryBackup.BackupError.notABackup) { try LibraryBackup.read(Data("{\"feeds\": []}".utf8)) }
        #expect(throws: LibraryBackup.BackupError.notABackup) { try LibraryBackup.read(Data("plain text".utf8)) }
        #expect(throws: LibraryBackup.BackupError.newerVersion(99)) {
            try LibraryBackup.read(Data("{\"format\": \"versoline-backup\", \"version\": 99}".utf8))
        }
        #expect(throws: LibraryBackup.BackupError.unreadable) {
            try LibraryBackup.read(Data("{\"format\": \"versoline-backup\", \"version\": 1, \"library\": 5}".utf8))
        }
    }
}

@MainActor
struct OldUnreadArticlesTests {

    private func store(with ages: [Double]) throws -> (TestStore, [FeedItem]) {
        let ts = try TestStore()
        let feed = Feed(title: "News", url: "https://news.example.com/rss")
        ts.store.feeds.append(feed)
        let now = Date()
        let items = ages.enumerated().map { index, days in
            FeedItem(feedId: feed.id, title: "Item \(index)", link: "https://news.example.com/\(index)", pubDate: now.addingTimeInterval(-days * 86_400))
        }
        ts.store.items[feed.id] = items
        ts.store.updateCachedCounts()
        return (ts, items)
    }

    @Test func onlyUnreadArticlesOlderThanTheLimitAreMarked() throws {
        let (ts, items) = try store(with: [0.5, 2, 8, 20]); defer { ts.cleanup() }
        #expect(ts.store.unreadItems(olderThanDays: 7).count == 2)
        #expect(ts.store.markOlderThanAsRead(days: 7) == 2)
        let after = try #require(ts.store.items[items[0].feedId])
        #expect(after.filter(\.isRead).count == 2)
        #expect(after.first { $0.title == "Item 0" }?.isRead == false)
        #expect(ts.store.totalUnreadCount() == 2)
        #expect(ts.store.markOlderThanAsRead(days: 7) == 0)   // nothing left to mark
    }

    @Test func articlesWithoutADateAndZeroDaysAreLeftAlone() throws {
        let (ts, items) = try store(with: [30]); defer { ts.cleanup() }
        ts.store.items[items[0].feedId]?[0].pubDate = nil
        #expect(ts.store.markOlderThanAsRead(days: 7) == 0)
        #expect(ts.store.markOlderThanAsRead(days: 0) == 0)
    }

    @Test func theSettingMarksOldArticlesAutomatically() throws {
        let (ts, _) = try store(with: [1, 10]); defer { ts.cleanup() }
        UserDefaults.standard.set(3, forKey: AppSettingsKeys.markOldAsReadDays)
        defer { UserDefaults.standard.removeObject(forKey: AppSettingsKeys.markOldAsReadDays) }
        ts.store.applyAutomaticReadMarking()
        #expect(ts.store.totalUnreadCount() == 1)
    }
}
