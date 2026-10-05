import Foundation

/// Tunables for `SmartMergeEngine.merge`.
enum SyncMerge {
    /// "Never edited": feeds and folders without `updatedAt` compare as this time.
    static let epoch = Date(timeIntervalSince1970: 0)
    /// Deletion records are kept this long (90 days). A Mac that stays offline longer can resurrect
    /// something that was deleted in the meantime.
    static let tombstoneLifetime: TimeInterval = 90 * 24 * 60 * 60
    static let maxTombstones = 2_000
    /// Timestamps from a peer further in the future than this are clamped (clock skew).
    static let maxClockSkew: TimeInterval = 5 * 60
}

/// The syncable part of a library: what `SmartMergeEngine.merge` reads and returns.
struct SyncLibrary: Equatable, Sendable {
    var feeds: [Feed]
    var folders: [Folder]
    var tombstones: [Tombstone]

    /// What this library looks like on the wire.
    var asRemote: SyncRemote {
        SyncRemote(
            feeds: feeds.map {
                SyncFeed(id: $0.id, title: $0.title, url: $0.url, folderId: $0.folderId,
                         isPinned: $0.isPinned, updatedAt: $0.updatedAt ?? SyncMerge.epoch)
            },
            folders: folders.map { SyncFolder(id: $0.id, name: $0.name, updatedAt: $0.updatedAt ?? SyncMerge.epoch) },
            tombstones: tombstones
        )
    }
}

/// A peer's side of a merge.
struct SyncRemote: Equatable, Sendable {
    var feeds: [SyncFeed] = []
    var folders: [SyncFolder] = []
    var tombstones: [Tombstone] = []
}

struct SyncMergeResult: Sendable {
    var library: SyncLibrary
    /// Feeds that exist now but did not before (their articles still need fetching).
    var addedFeeds: [Feed]
    /// Local feeds that were deleted by the merge (their articles must be dropped).
    var removedFeeds: [Feed]
    var changed: Bool
}

enum SmartMergeEngine {

    //
    // Every feed and folder carries `updatedAt` (last user edit) and deletions are kept as tombstones.
    // For each feed (key: lower-cased URL) and folder (key: id) the newest change wins, a deletion
    // counts as a change, and re-adding something after it was deleted brings it back. The result does
    // not depend on the order in which two devices merge (the tests check this), so any number of
    // Macs converge to the same library.

    /// Merges a peer's feeds, folders and deletions into the local library. Pure and deterministic.
    static func merge(
        local: SyncLibrary,
        remote: SyncRemote,
        now: Date = Date()
    ) -> SyncMergeResult {
        let epoch = SyncMerge.epoch
        let horizon = now.addingTimeInterval(SyncMerge.maxClockSkew)
        func clamp(_ date: Date) -> Date { min(date, horizon) }

        // Deletions: keep the latest time per (kind, key). Records past their lifetime are ignored,
        // on both sides, so a very old deletion can no longer remove anything.
        let cutoff = now.addingTimeInterval(-SyncMerge.tombstoneLifetime)
        var deletions: [Tombstone.Key: Date] = [:]
        for tombstone in local.tombstones + remote.tombstones where tombstone.deletedAt > cutoff {
            let key = Tombstone.Key(kind: tombstone.kind, key: tombstone.key)
            deletions[key] = max(deletions[key] ?? epoch, clamp(tombstone.deletedAt))
        }
        var supersededDeletions: Set<Tombstone.Key> = []

        // Folders
        let localFolders = Dictionary(local.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteFolders = Dictionary(remote.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var folderOrder = local.folders.map(\.id)
        folderOrder += remoteFolders.keys.filter { localFolders[$0] == nil }.sorted { $0.uuidString < $1.uuidString }

        var folders: [Folder] = []
        for id in folderOrder {
            let l = localFolders[id], r = remoteFolders[id]
            let localTime = l?.updatedAt ?? epoch
            let remoteTime = r.map { clamp($0.updatedAt) } ?? epoch

            var name = l?.name ?? r?.name ?? ""
            var time = localTime
            if l == nil {
                time = remoteTime
            } else if let r, remoteTime > localTime || (remoteTime == localTime && r.name > (l?.name ?? "")) {
                name = r.name
                time = remoteTime
            }

            let deletionKey = Tombstone.Key(kind: .folder, key: id.uuidString)
            if let deletedAt = deletions[deletionKey], deletedAt >= time { continue }
            if deletions[deletionKey] != nil { supersededDeletions.insert(deletionKey) }
            folders.append(Folder(id: id, name: name, keywords: l?.keywords, updatedAt: time > epoch ? time : nil))
        }
        // Feeds
        let localFeeds = Dictionary(local.feeds.map { ($0.url.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let remoteFeeds = Dictionary(remote.feeds.map { ($0.url.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var feedOrder = local.feeds.map { $0.url.lowercased() }
        var seenKeys = Set<String>()
        feedOrder = feedOrder.filter { seenKeys.insert($0).inserted }
        feedOrder += remoteFeeds.keys.filter { localFeeds[$0] == nil }.sorted()

        var feeds: [Feed] = []
        var added: [Feed] = []
        var removed: [Feed] = []
        for key in feedOrder {
            let l = localFeeds[key], r = remoteFeeds[key]
            let localTime = l?.updatedAt ?? epoch
            let remoteTime = r.map { clamp($0.updatedAt) } ?? epoch

            // Does the remote version win? Newer time wins; on a tie a fixed data-based order decides.
            var remoteWins = false
            if let l, let r {
                if remoteTime != localTime {
                    remoteWins = remoteTime > localTime
                } else {
                    remoteWins = tieBreak(pinned: r.isPinned ?? false, folder: r.folderId, title: r.title)
                        > tieBreak(pinned: l.isPinned, folder: l.folderId, title: l.title)
                }
            } else if r != nil {
                remoteWins = true
            }
            let time = remoteWins ? remoteTime : localTime

            let deletionKey = Tombstone.Key(kind: .feed, key: key)
            if let deletedAt = deletions[deletionKey], deletedAt >= time {
                if let l { removed.append(l) }
                continue
            }
            if deletions[deletionKey] != nil { supersededDeletions.insert(deletionKey) }

            var feed: Feed
            if let l {
                feed = l
                if remoteWins, let r {
                    feed.title = r.title
                    feed.folderId = r.folderId
                    feed.isPinned = r.isPinned ?? false
                    feed.updatedAt = time > epoch ? time : nil
                }
            } else if let r {
                feed = Feed(id: r.id, title: r.title, url: r.url, folderId: r.folderId,
                            isPinned: r.isPinned ?? false, updatedAt: time > epoch ? time : nil)
                added.append(feed)
            } else {
                continue
            }
            // A feed may reference a folder that is not here (yet, or any more). The reference is kept so
            // the merge loses no information and stays order-independent; the store shows such a feed
            // as uncategorized.
            feeds.append(feed)
        }

        // Tombstones that no longer matter are dropped: superseded by a newer re-add, or too old.
        var keptList: [Tombstone] = []
        for (key, deletedAt) in deletions where !supersededDeletions.contains(key) {
            keptList.append(Tombstone(kind: key.kind, key: key.key, deletedAt: deletedAt))
        }
        keptList.sort(by: Self.newestFirst)
        let kept = keptList.prefix(SyncMerge.maxTombstones)

        let library = SyncLibrary(feeds: feeds, folders: folders, tombstones: Array(kept))
        return SyncMergeResult(library: library, addedFeeds: added, removedFeeds: removed, changed: library != local)
    }

    /// Newest deletion first; equal times are ordered by kind and key so the result is deterministic.
    private static func newestFirst(_ lhs: Tombstone, _ rhs: Tombstone) -> Bool {
        if lhs.deletedAt != rhs.deletedAt { return lhs.deletedAt > rhs.deletedAt }
        let leftName = lhs.kind.rawValue + lhs.key
        let rightName = rhs.kind.rawValue + rhs.key
        return leftName < rightName
    }

    private static func tieBreak(pinned: Bool, folder: UUID?, title: String) -> String {
        "\(pinned ? 1 : 0)|\(folder?.uuidString ?? "")|\(title)"
    }

    /// Merges read hashes using monotonic union (once read, always read).
    static func mergeReadHashes(
        localHashes: Set<UInt64>,
        remoteHashes: [UInt64]
    ) -> Set<UInt64> {
        var combined = localHashes
        combined.formUnion(remoteHashes)
        return combined
    }

    /// Merges bookmarks using set union (never lose a saved bookmark).
    static func mergeBookmarks(
        localBookmarkLinks: Set<String>,
        remoteBookmarkLinks: [String]
    ) -> Set<String> {
        var combined = localBookmarkLinks
        combined.formUnion(remoteBookmarkLinks)
        return combined
    }

    /// Merges local settings with remote settings based on timestamps and field availability.
    static func mergeSettings(
        local: SyncSettings,
        remote: SyncSettings
    ) -> (merged: SyncSettings, shouldUpdateLocal: Bool, shouldUpdateRemote: Bool) {
        if local.hasSamePreferences(as: remote) {
            return (local, false, false)
        }

        if remote.updatedAt > local.updatedAt {
            var merged = remote
            merged.appColorPalette = remote.appColorPalette ?? local.appColorPalette
            merged.readerTheme = remote.readerTheme ?? local.readerTheme
            merged.readerFontFamily = remote.readerFontFamily ?? local.readerFontFamily
            merged.readerFontSize = remote.readerFontSize ?? local.readerFontSize
            merged.readerLineHeight = remote.readerLineHeight ?? local.readerLineHeight
            merged.isCompactListMode = remote.isCompactListMode ?? local.isCompactListMode
            merged.showFavicons = remote.showFavicons ?? local.showFavicons
            merged.showMenuBarIcon = remote.showMenuBarIcon ?? local.showMenuBarIcon
            merged.autoReaderMode = remote.autoReaderMode ?? local.autoReaderMode
            merged.isBionicReadingEnabled = remote.isBionicReadingEnabled ?? local.isBionicReadingEnabled
            merged.defaultReadingMode = remote.defaultReadingMode ?? local.defaultReadingMode
            merged.showReadingTimeStreams = remote.showReadingTimeStreams ?? local.showReadingTimeStreams
            merged.offlinePrecacheEnabled = remote.offlinePrecacheEnabled ?? local.offlinePrecacheEnabled
            merged.isContentBlockerEnabled = remote.isContentBlockerEnabled ?? local.isContentBlockerEnabled
            merged.preferredExternalBrowser = remote.preferredExternalBrowser ?? local.preferredExternalBrowser
            merged.enableSingleKeyShortcuts = remote.enableSingleKeyShortcuts ?? local.enableSingleKeyShortcuts
            merged.autoCleanupDays = remote.autoCleanupDays ?? local.autoCleanupDays
            merged.mutedKeywords = remote.mutedKeywords ?? local.mutedKeywords

            let shouldUpdateRemote = !merged.hasSamePreferences(as: remote)
            return (merged, true, shouldUpdateRemote)
        } else {
            var merged = local
            merged.appColorPalette = local.appColorPalette ?? remote.appColorPalette
            merged.readerTheme = local.readerTheme ?? remote.readerTheme
            merged.readerFontFamily = local.readerFontFamily ?? remote.readerFontFamily
            merged.readerFontSize = local.readerFontSize ?? remote.readerFontSize
            merged.readerLineHeight = local.readerLineHeight ?? remote.readerLineHeight
            merged.isCompactListMode = local.isCompactListMode ?? remote.isCompactListMode
            merged.showFavicons = local.showFavicons ?? remote.showFavicons
            merged.showMenuBarIcon = local.showMenuBarIcon ?? remote.showMenuBarIcon
            merged.autoReaderMode = local.autoReaderMode ?? remote.autoReaderMode
            merged.isBionicReadingEnabled = local.isBionicReadingEnabled ?? remote.isBionicReadingEnabled
            merged.defaultReadingMode = local.defaultReadingMode ?? remote.defaultReadingMode
            merged.showReadingTimeStreams = local.showReadingTimeStreams ?? remote.showReadingTimeStreams
            merged.offlinePrecacheEnabled = local.offlinePrecacheEnabled ?? remote.offlinePrecacheEnabled
            merged.isContentBlockerEnabled = local.isContentBlockerEnabled ?? remote.isContentBlockerEnabled
            merged.preferredExternalBrowser = local.preferredExternalBrowser ?? remote.preferredExternalBrowser
            merged.enableSingleKeyShortcuts = local.enableSingleKeyShortcuts ?? remote.enableSingleKeyShortcuts
            merged.autoCleanupDays = local.autoCleanupDays ?? remote.autoCleanupDays
            merged.mutedKeywords = local.mutedKeywords ?? remote.mutedKeywords

            let shouldUpdateLocal = !merged.hasSamePreferences(as: local)
            return (merged, shouldUpdateLocal, true)
        }
    }

    /// Merges feeds from an OPML document into existing feeds and folders.
    static func mergeOPMLFeeds(
        localFeeds: [Feed],
        localFolders: [Folder],
        opmlFeeds: [OPMLManager.OPMLFeed]
    ) -> (mergedFeeds: [Feed], mergedFolders: [Folder], hasChanges: Bool) {
        var mergedFeeds = localFeeds
        var mergedFolders = localFolders
        var existingUrls = Set(localFeeds.map { $0.url.lowercased() })
        var hasChanges = false

        for opml in opmlFeeds {
            let normalizedUrl = opml.xmlUrl.lowercased()
            guard !existingUrls.contains(normalizedUrl) else { continue }

            var targetFolderId: UUID?
            if let folderName = opml.folderName, !folderName.isEmpty {
                if let found = mergedFolders.first(where: { $0.name.caseInsensitiveCompare(folderName) == .orderedSame }) {
                    targetFolderId = found.id
                } else {
                    let newFolder = Folder(name: folderName)
                    mergedFolders.append(newFolder)
                    targetFolderId = newFolder.id
                    hasChanges = true
                }
            }

            let newFeed = Feed(
                title: opml.title.isEmpty ? opml.xmlUrl : opml.title,
                url: opml.xmlUrl,
                folderId: targetFolderId
            )
            mergedFeeds.append(newFeed)
            existingUrls.insert(normalizedUrl)
            hasChanges = true
        }

        return (mergedFeeds, mergedFolders, hasChanges)
    }
}
