import Testing
import Foundation
@testable import Versoline

@Suite("SmartMergeEngine Tests")
struct SmartMergeEngineTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let earlier = Date(timeIntervalSince1970: 1_700_000_000)

    private let epoch = SyncMerge.epoch
    private let day: TimeInterval = 86_400

    private func t(_ offset: TimeInterval) -> Date { now.addingTimeInterval(offset) }

    private func syncFeed(
        _ url: String, title: String = "Remote", folderId: UUID? = nil, pinned: Bool? = nil, at date: Date? = nil
    ) -> SyncFeed {
        SyncFeed(id: UUID(), title: title, url: url, folderId: folderId, isPinned: pinned, updatedAt: date ?? earlier)
    }

    private func library(feeds: [Feed] = [], folders: [Folder] = [], tombstones: [Tombstone] = []) -> SyncLibrary {
        SyncLibrary(feeds: feeds, folders: folders, tombstones: tombstones)
    }

    private func merge(_ local: SyncLibrary, _ remote: SyncRemote = SyncRemote()) -> SyncMergeResult {
        SmartMergeEngine.merge(local: local, remote: remote, now: now)
    }

    // MARK: - Feeds

    @Test("A feed only on the remote side is added with its remote values")
    func remoteOnlyFeed() {
        let remote = syncFeed("https://example.com/feed", title: "Remote Feed", pinned: true)

        let result = merge(library(), SyncRemote(feeds: [remote]))

        #expect(result.library.feeds.count == 1)
        #expect(result.library.feeds[0].id == remote.id)
        #expect(result.library.feeds[0].isPinned)
        #expect(result.addedFeeds.count == 1)
        #expect(result.changed)
    }

    @Test("A feed only on the local side is kept untouched")
    func localOnlyFeed() {
        let local = Feed(title: "Local", url: "https://example.com/local", updatedAt: earlier)

        let result = merge(library(feeds: [local]))

        #expect(result.library.feeds == [local])
        #expect(!result.changed)
    }

    @Test("Feeds match by URL ignoring case; the local id and local-only fields stay")
    func urlMatching() {
        let local = Feed(title: "Local", url: "https://Example.com/Feed", description: "kept", updatedAt: earlier)
        let remote = syncFeed("https://example.com/feed", at: earlier)

        let result = merge(library(feeds: [local]), SyncRemote(feeds: [remote]))

        #expect(result.library.feeds.count == 1)
        #expect(result.library.feeds[0].id == local.id)
        #expect(result.library.feeds[0].description == "kept")
        #expect(result.addedFeeds.isEmpty)
    }

    @Test("The newer edit wins in both directions")
    func newerEditWins() {
        let folderId = UUID()
        let folder = Folder(id: folderId, name: "F", updatedAt: earlier)
        let local = Feed(title: "T", url: "https://example.com/f", folderId: nil, isPinned: false, updatedAt: t(-100))
        let newerRemote = syncFeed("https://example.com/f", folderId: folderId, pinned: true, at: t(-10))

        let remoteWins = merge(library(feeds: [local], folders: [folder]), SyncRemote(feeds: [newerRemote]))
        #expect(remoteWins.library.feeds[0].folderId == folderId)
        #expect(remoteWins.library.feeds[0].isPinned)
        #expect(remoteWins.library.feeds[0].updatedAt == t(-10))

        let olderRemote = syncFeed("https://example.com/f", folderId: folderId, pinned: true, at: t(-1000))
        let localWins = merge(library(feeds: [local], folders: [folder]), SyncRemote(feeds: [olderRemote]))
        #expect(localWins.library.feeds[0].folderId == nil)
        #expect(!localWins.library.feeds[0].isPinned)
    }

    @Test("Unpinning and leaving a folder propagate (not just adding)")
    func removalsOfAttributesPropagate() {
        let folderId = UUID()
        let folder = Folder(id: folderId, name: "F", updatedAt: earlier)
        let local = Feed(title: "T", url: "https://example.com/f", folderId: folderId, isPinned: true, updatedAt: t(-100))
        let remote = syncFeed("https://example.com/f", folderId: nil, pinned: false, at: t(-10))

        let result = merge(library(feeds: [local], folders: [folder]), SyncRemote(feeds: [remote], folders: []))

        #expect(result.library.feeds[0].folderId == nil)
        #expect(!result.library.feeds[0].isPinned)
    }

    @Test("A deletion newer than the last edit removes the feed and reports it")
    func deletionNewerWins() {
        let local = Feed(title: "Local", url: "https://example.com/gone", updatedAt: t(-100))
        let tombstone = Tombstone.feed(url: "https://example.com/gone", at: t(-10))

        let result = merge(library(feeds: [local]), SyncRemote(tombstones: [tombstone]))

        #expect(result.library.feeds.isEmpty)
        #expect(result.removedFeeds.map(\.id) == [local.id])
        #expect(result.library.tombstones == [tombstone])
    }

    @Test("An edit newer than the deletion keeps the feed and drops the stale deletion record")
    func editNewerThanDeletion() {
        let local = Feed(title: "Local", url: "https://example.com/back", updatedAt: t(-10))
        let tombstone = Tombstone.feed(url: "https://example.com/back", at: t(-100))

        let result = merge(library(feeds: [local]), SyncRemote(tombstones: [tombstone]))

        #expect(result.library.feeds == [local])
        #expect(result.library.tombstones.isEmpty)
        #expect(result.removedFeeds.isEmpty)
    }

    @Test("Re-adding a deleted feed on another Mac brings it back everywhere")
    func readdAfterDelete() {
        let tombstone = Tombstone.feed(url: "https://example.com/again", at: t(-100))
        let readded = syncFeed("https://example.com/again", at: t(-10))

        // This Mac deleted it earlier; the peer re-added it later.
        let result = merge(library(tombstones: [tombstone]), SyncRemote(feeds: [readded]))

        #expect(result.library.feeds.map(\.url) == ["https://example.com/again"])
        #expect(result.library.tombstones.isEmpty)
        #expect(result.addedFeeds.count == 1)
    }

    @Test("A feed that was never edited loses to any deletion (legacy data)")
    func uneditedLosesToDeletion() {
        let legacy = Feed(title: "Old", url: "https://example.com/old")
        let tombstone = Tombstone.feed(url: "https://example.com/old", at: t(-10_000))

        let result = merge(library(feeds: [legacy]), SyncRemote(tombstones: [tombstone]))

        #expect(result.library.feeds.isEmpty)
    }

    @Test("A deletion for a feed this Mac never had is kept so it can be passed on, and nothing is created")
    func tombstoneForUnknownFeed() {
        let tombstone = Tombstone.feed(url: "https://example.com/never", at: t(-10))

        let result = merge(library(), SyncRemote(tombstones: [tombstone]))

        #expect(result.library.feeds.isEmpty)
        #expect(result.library.tombstones == [tombstone])
    }

    @Test("A remote deletion does not remove a remote feed that is newer than it")
    func remoteFeedNewerThanTombstone() {
        let remote = syncFeed("https://example.com/f", at: t(-10))
        let tombstone = Tombstone.feed(url: "https://example.com/f", at: t(-100))

        let result = merge(library(), SyncRemote(feeds: [remote], tombstones: [tombstone]))

        #expect(result.library.feeds.count == 1)
    }

    // MARK: - Folders

    @Test("Folders merge by id; a newer rename wins in both directions and keywords stay local")
    func folderRename() {
        let id = UUID()
        let local = Folder(id: id, name: "Old", keywords: ["swift"], updatedAt: t(-100))

        let newer = merge(library(folders: [local]), SyncRemote(folders: [SyncFolder(id: id, name: "New", updatedAt: t(-10))]))
        #expect(newer.library.folders.first?.name == "New")
        #expect(newer.library.folders.first?.keywords == ["swift"])

        let older = merge(library(folders: [local]), SyncRemote(folders: [SyncFolder(id: id, name: "Stale", updatedAt: t(-1000))]))
        #expect(older.library.folders.first?.name == "Old")
    }

    @Test("A remote-only folder is added")
    func remoteOnlyFolder() {
        let remote = SyncFolder(id: UUID(), name: "Tech", updatedAt: earlier)

        let result = merge(library(), SyncRemote(folders: [remote]))

        #expect(result.library.folders.map(\.name) == ["Tech"])
    }

    @Test("A folder deletion newer than the last rename removes the folder")
    func folderDeletion() {
        let id = UUID()
        let folder = Folder(id: id, name: "F", updatedAt: t(-100))
        let feed = Feed(title: "T", url: "https://example.com/f", folderId: id, updatedAt: t(-100))
        let tombstone = Tombstone.folder(id: id, at: t(-10))

        let result = merge(library(feeds: [feed], folders: [folder]), SyncRemote(tombstones: [tombstone]))

        #expect(result.library.folders.isEmpty)
        // The reference is kept (merging must lose no information); the store shows the feed as uncategorized.
        #expect(result.library.feeds.first?.folderId == id)
        #expect(result.library.tombstones == [tombstone])
    }

    @Test("A rename after a deletion revives the folder")
    func folderRevive() {
        let id = UUID()
        let local = Folder(id: id, name: "Back", updatedAt: t(-10))
        let tombstone = Tombstone.folder(id: id, at: t(-100))

        let result = merge(library(folders: [local]), SyncRemote(tombstones: [tombstone]))

        #expect(result.library.folders == [local])
        #expect(result.library.tombstones.isEmpty)
    }

    @Test("A feed that arrives before its folder keeps the reference, so the folder resolves it later")
    func danglingFolderIsKept() {
        let folderId = UUID()
        let remote = syncFeed("https://example.com/f", folderId: folderId, at: t(-10))

        let first = merge(library(), SyncRemote(feeds: [remote]))
        #expect(first.library.feeds.first?.folderId == folderId)

        let second = merge(first.library, SyncRemote(folders: [SyncFolder(id: folderId, name: "Late", updatedAt: t(-20))]))
        #expect(second.library.folders.map { $0.name } == ["Late"])
        #expect(second.library.feeds.first?.folderId == folderId)
    }

    // MARK: - Deletion records

    @Test("Deletion records expire after 90 days")
    func tombstoneExpiry() {
        let fresh = Tombstone.feed(url: "https://example.com/fresh", at: t(-89 * day))
        let stale = Tombstone.feed(url: "https://example.com/stale", at: t(-91 * day))

        let result = merge(library(tombstones: [fresh, stale]))

        #expect(result.library.tombstones == [fresh])
    }

    @Test("An expired deletion no longer removes a feed (documented limit)")
    func expiredDeletionDoesNotApply() {
        let local = Feed(title: "L", url: "https://example.com/f")
        let stale = Tombstone.feed(url: "https://example.com/f", at: t(-91 * day))

        let result = merge(library(feeds: [local]), SyncRemote(tombstones: [stale]))

        #expect(result.library.feeds.count == 1)
    }

    @Test("At most 2,000 deletion records are kept, newest first")
    func tombstoneCap() {
        let many = (0..<2_100).map { Tombstone.feed(url: "https://example.com/\($0)", at: t(-Double($0))) }

        let result = merge(library(tombstones: many))

        #expect(result.library.tombstones.count == SyncMerge.maxTombstones)
        #expect(result.library.tombstones.first?.key == "https://example.com/0")
    }

    @Test("Timestamps far in the future are clamped to a few minutes ahead")
    func clockSkew() {
        let far = Tombstone.feed(url: "https://example.com/f", at: t(10 * 365 * day))

        let result = merge(library(), SyncRemote(tombstones: [far]))

        #expect(result.library.tombstones.first!.deletedAt <= t(SyncMerge.maxClockSkew))
    }

    // MARK: - Convergence

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private func randomLibrary(_ rng: inout SeededGenerator, folderIds: [UUID]) -> SyncLibrary {
        let urls = (0..<4).map { "https://example.com/\($0)" }
        let times: [Date?] = [nil, t(-300), t(-200), t(-100), t(-50)]
        func time() -> Date? { times.randomElement(using: &rng)! }

        var feeds: [Feed] = []
        var tombstones: [Tombstone] = []
        for url in urls {
            switch Int.random(in: 0..<3, using: &rng) {
            case 0: break
            case 1:
                feeds.append(Feed(title: ["A", "B", "C"].randomElement(using: &rng)!, url: url,
                                  folderId: ([nil] + folderIds.map { Optional($0) }).randomElement(using: &rng)!,
                                  isPinned: Bool.random(using: &rng), updatedAt: time()))
            default:
                tombstones.append(Tombstone.feed(url: url, at: time() ?? t(-400)))
            }
        }
        var folders: [Folder] = []
        for id in folderIds {
            switch Int.random(in: 0..<3, using: &rng) {
            case 0: break
            case 1: folders.append(Folder(id: id, name: ["X", "Y"].randomElement(using: &rng)!, updatedAt: time()))
            default: tombstones.append(Tombstone.folder(id: id, at: time() ?? t(-400)))
            }
        }
        return SyncLibrary(feeds: feeds, folders: folders, tombstones: tombstones)
    }

    /// Everything that is synced, in a canonical order, so two libraries can be compared.
    private func canonical(_ lib: SyncLibrary) -> [String] {
        let feeds = lib.feeds.map { "F|\($0.url.lowercased())|\($0.title)|\($0.folderId?.uuidString ?? "-")|\($0.isPinned)|\(($0.updatedAt ?? epoch).timeIntervalSince1970)" }
        let folders = lib.folders.map { "D|\($0.id)|\($0.name)|\(($0.updatedAt ?? epoch).timeIntervalSince1970)" }
        let tombs = lib.tombstones.map { "T|\($0.kind.rawValue)|\($0.key)|\($0.deletedAt.timeIntervalSince1970)" }
        return (feeds + folders + tombs).sorted()
    }

    @Test("Two Macs end up with the same library whichever one merges first, and merging again changes nothing")
    func convergence() {
        var rng = SeededGenerator(state: 42)
        let folderIds = [UUID(), UUID(), UUID()]
        for _ in 0..<300 {
            let a = randomLibrary(&rng, folderIds: folderIds)
            let b = randomLibrary(&rng, folderIds: folderIds)

            let aThenB = merge(a, b.asRemote).library
            let bThenA = merge(b, a.asRemote).library
            #expect(canonical(aThenB) == canonical(bThenA))

            // Idempotent: merging the same peer again is a no-op.
            let again = merge(aThenB, b.asRemote).library
            #expect(canonical(again) == canonical(aThenB))
            // And the merged result is stable against either side.
            #expect(canonical(merge(aThenB, a.asRemote).library) == canonical(aThenB))
        }
    }

    @Test("Three Macs converge regardless of the order they sync in")
    func threeWayConvergence() {
        var rng = SeededGenerator(state: 7)
        let folderIds = [UUID(), UUID()]
        for _ in 0..<200 {
            let a = randomLibrary(&rng, folderIds: folderIds)
            let b = randomLibrary(&rng, folderIds: folderIds)
            let c = randomLibrary(&rng, folderIds: folderIds)

            let abc = merge(merge(a, b.asRemote).library, c.asRemote).library
            let cba = merge(merge(c, b.asRemote).library, a.asRemote).library
            let bac = merge(merge(b, a.asRemote).library, c.asRemote).library

            #expect(canonical(abc) == canonical(cba))
            #expect(canonical(abc) == canonical(bac))
        }
    }

    // MARK: - Read state and bookmarks

    @Test("Read hashes only ever grow")
    func readHashesUnion() {
        let merged = SmartMergeEngine.mergeReadHashes(localHashes: [1, 2], remoteHashes: [2, 3])

        #expect(merged == [1, 2, 3])
    }

    @Test("Bookmarks are a union and never lost")
    func bookmarkUnion() {
        let merged = SmartMergeEngine.mergeBookmarks(
            localBookmarkLinks: ["https://a.com"],
            remoteBookmarkLinks: ["https://b.com", "https://a.com"]
        )

        #expect(merged == ["https://a.com", "https://b.com"])
    }

    @Test("syncHash64 is stable and distinguishes different links")
    func syncHashIsStable() {
        // FNV-1a 64-bit of the empty string is the offset basis.
        #expect("".syncHash64 == 0xcbf29ce484222325)
        #expect("https://a.com".syncHash64 == "https://a.com".syncHash64)
        #expect("https://a.com".syncHash64 != "https://b.com".syncHash64)
    }

    // MARK: - Settings

    private func settings(updatedAt: Date, palette: String?, fontSize: Double? = nil) -> SyncSettings {
        SyncSettings(deviceId: "test", updatedAt: updatedAt, appColorPalette: palette, readerFontSize: fontSize)
    }

    @Test("Identical preferences need no update on either side")
    func settingsIdentical() {
        let a = settings(updatedAt: now, palette: "slate")
        let b = settings(updatedAt: earlier, palette: "slate")

        let result = SmartMergeEngine.mergeSettings(local: a, remote: b)

        #expect(!result.shouldUpdateLocal)
        #expect(!result.shouldUpdateRemote)
    }

    @Test("Newer remote settings win but keep local values for fields remote lacks")
    func newerRemoteWins() {
        let local = settings(updatedAt: earlier, palette: "slate", fontSize: 18)
        let remote = settings(updatedAt: now, palette: "sepia", fontSize: nil)

        let result = SmartMergeEngine.mergeSettings(local: local, remote: remote)

        #expect(result.merged.appColorPalette == "sepia")
        #expect(result.merged.readerFontSize == 18)
        #expect(result.shouldUpdateLocal)
        #expect(result.shouldUpdateRemote)
    }

    @Test("Newer local settings win and are pushed to remote")
    func newerLocalWins() {
        let local = settings(updatedAt: now, palette: "slate")
        let remote = settings(updatedAt: earlier, palette: "sepia", fontSize: 20)

        let result = SmartMergeEngine.mergeSettings(local: local, remote: remote)

        #expect(result.merged.appColorPalette == "slate")
        #expect(result.merged.readerFontSize == 20)
        #expect(result.shouldUpdateRemote)
    }

    // MARK: - OPML

    @Test("OPML merge skips existing URLs and reuses folders case-insensitively")
    func opmlMerge() {
        let folder = Folder(name: "News")
        let existing = Feed(title: "Existing", url: "https://example.com/a")
        let opml = [
            OPMLManager.OPMLFeed(title: "Dup", xmlUrl: "https://EXAMPLE.com/a", folderName: nil),
            OPMLManager.OPMLFeed(title: "New", xmlUrl: "https://example.com/b", folderName: "news"),
            OPMLManager.OPMLFeed(title: "", xmlUrl: "https://example.com/c", folderName: "Fresh"),
        ]

        let result = SmartMergeEngine.mergeOPMLFeeds(localFeeds: [existing], localFolders: [folder], opmlFeeds: opml)

        #expect(result.hasChanges)
        #expect(result.mergedFeeds.count == 3)
        #expect(result.mergedFolders.count == 2)
        let b = result.mergedFeeds.first { $0.url == "https://example.com/b" }
        #expect(b?.folderId == folder.id)
        let c = result.mergedFeeds.first { $0.url == "https://example.com/c" }
        #expect(c?.title == "https://example.com/c")
    }

    @Test("OPML merge reports no changes when everything already exists")
    func opmlNoChanges() {
        let existing = Feed(title: "Existing", url: "https://example.com/a")
        let opml = [OPMLManager.OPMLFeed(title: "Same", xmlUrl: "https://example.com/a", folderName: nil)]

        let result = SmartMergeEngine.mergeOPMLFeeds(localFeeds: [existing], localFolders: [], opmlFeeds: opml)

        #expect(!result.hasChanges)
        #expect(result.mergedFeeds.count == 1)
    }
}
