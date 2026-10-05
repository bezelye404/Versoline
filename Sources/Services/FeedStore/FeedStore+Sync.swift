import Foundation

extension FeedStore {

    var syncLibrary: SyncLibrary {
        SyncLibrary(feeds: feeds, folders: folders, tombstones: tombstones)
    }

    /// Feeds, folders and deletion records only, in small chunks. Cheap enough to send on every change.
    func syncFeedSnapshotEvents() -> [SyncPeerEvent] {
        let remote = syncLibrary.asRemote

        // Folders go with the first feed chunk so feeds never point at a folder the peer has not seen.
        let feedChunks = chunks(remote.feeds, size: SyncEventValidator.maxFeeds)
        let folderChunks = chunks(remote.folders, size: SyncEventValidator.maxFolders)
        var events: [SyncPeerEvent] = (0..<max(feedChunks.count, folderChunks.count)).map { index in
            .feedSnapshot(
                feeds: index < feedChunks.count ? feedChunks[index] : [],
                folders: index < folderChunks.count ? folderChunks[index] : []
            )
        }
        events += chunks(remote.tombstones, size: SyncEventValidator.maxTombstones).map { .tombstoneSnapshot(tombstones: $0) }
        return events
    }

    private func chunks<T>(_ array: [T], size: Int) -> [[T]] {
        stride(from: 0, to: array.count, by: size).map { Array(array[$0..<min($0 + size, array.count)]) }
    }

    /// Everything a freshly paired or reconnected device needs, in small chunks.
    /// Read states are sent as 64-bit hashes of article links, bookmarks as full links.
    func syncSnapshotEvents() -> [SyncPeerEvent] {
        var events = syncFeedSnapshotEvents()

        let readHashes = items.values.flatMap { $0 }.filter(\.isRead).map { $0.link.syncHash64 }
        for start in stride(from: 0, to: readHashes.count, by: 2_000) {
            events.append(.readArticles(hashes: Array(readHashes[start..<min(start + 2_000, readHashes.count)])))
        }

        let bookmarks = items.values.flatMap { $0 }.filter(\.isBookmarked).map(\.link)
        for start in stride(from: 0, to: bookmarks.count, by: 100) {
            events.append(.bookmarkSnapshot(links: Array(bookmarks[start..<min(start + 100, bookmarks.count)])))
        }

        return events
    }

    /// Applies an event from an authenticated peer. Settings are handled by `SyncCoordinator`.
    func applySyncEvent(_ event: SyncPeerEvent) {
        guard SyncEventValidator.isAcceptable(event) else { return }

        switch event {
        case .readArticles(let hashes):
            applyIncomingReadHashes(Set(hashes))
        case .bookmarkToggled(let link, let isBookmarked):
            applyIncomingBookmark(link: link, isBookmarked: isBookmarked)
        case .bookmarkSnapshot(let links):
            applyIncomingBookmarks(Set(links))
        case .feedAddedOrUpdated(let feed):
            mergeIncoming(SyncRemote(feeds: [feed]))
        case .feedDeleted(let url, let deletedAt):
            mergeIncoming(SyncRemote(tombstones: [.feed(url: url, at: deletedAt)]))
        case .folderUpdated(let folder):
            mergeIncoming(SyncRemote(folders: [folder]))
        case .folderDeleted(let id, let deletedAt):
            mergeIncoming(SyncRemote(tombstones: [.folder(id: id, at: deletedAt)]))
        case .feedSnapshot(let feeds, let folders):
            mergeIncoming(SyncRemote(feeds: feeds, folders: folders))
        case .tombstoneSnapshot(let tombstones):
            mergeIncoming(SyncRemote(tombstones: tombstones))
        case .settings:
            break
        }
    }

    /// Merges a peer's feeds, folders and deletions (last writer wins; see `SmartMergeEngine.merge`).
    /// Articles of deleted feeds are dropped; new feeds are fetched.
    func mergeIncoming(_ remote: SyncRemote) {
        let result = SmartMergeEngine.merge(local: syncLibrary, remote: remote)
        guard result.changed else { return }

        feeds = result.library.feeds
        folders = result.library.folders
        tombstones = result.library.tombstones
        for removed in result.removedFeeds { items.removeValue(forKey: removed.id) }

        invalidateItemCaches()
        updateCachedCounts()
        updateSmartCategoryCaches()
        save(updateCounts: false)

        for feed in result.addedFeeds {
            Task { await refreshFeed(feed) }
        }
    }

    func applyIncomingReadHashes(_ hashes: Set<UInt64>) {
        var hasChanges = false
        for (feedId, feedItems) in items {
            var updatedList = feedItems
            var listChanged = false
            for i in updatedList.indices where !updatedList[i].isRead && hashes.contains(updatedList[i].link.syncHash64) {
                updatedList[i].isRead = true
                listChanged = true
            }
            if listChanged {
                items[feedId] = updatedList
                hasChanges = true
            }
        }
        if hasChanges { didApplyIncomingItemChanges() }
    }

    func applyIncomingBookmark(link: String, isBookmarked: Bool) {
        for (feedId, feedItems) in items {
            if let idx = feedItems.firstIndex(where: { $0.link == link }) {
                guard items[feedId]?[idx].isBookmarked != isBookmarked else { return }
                items[feedId]?[idx].isBookmarked = isBookmarked
                didApplyIncomingItemChanges()
                return
            }
        }
    }

    /// Union: a snapshot can add bookmarks but never removes one.
    func applyIncomingBookmarks(_ links: Set<String>) {
        guard !links.isEmpty else { return }
        var hasChanges = false
        for (feedId, feedItems) in items {
            var updatedList = feedItems
            var listChanged = false
            for i in updatedList.indices where !updatedList[i].isBookmarked && links.contains(updatedList[i].link) {
                updatedList[i].isBookmarked = true
                listChanged = true
            }
            if listChanged {
                items[feedId] = updatedList
                hasChanges = true
            }
        }
        if hasChanges { didApplyIncomingItemChanges() }
    }

    private func didApplyIncomingItemChanges() {
        invalidateItemCaches()
        updateCachedCounts()
        updateSmartCategoryCaches()
        save(updateCounts: false)
    }
}
