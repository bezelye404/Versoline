import Foundation

extension FeedStore {

    // MARK: - Folder Management

    @discardableResult
    func addFolder(name: String) -> Folder {
        let folder = Folder(name: name, updatedAt: Date())
        folders.append(folder)
        AppLogger.shared.log("Added folder: \"\(name)\"", level: .info, category: .storage)
        save()
        SyncCoordinator.shared.notifyFolderUpdated(folder)
        return folder
    }

    func removeFolder(_ folderId: UUID) {
        let folderName = folders.first(where: { $0.id == folderId })?.name ?? folderId.uuidString
        AppLogger.shared.log("Removed folder: \"\(folderName)\"", level: .info, category: .storage)
        let now = Date()
        for i in feeds.indices where feeds[i].folderId == folderId {
            feeds[i].folderId = nil
            feeds[i].updatedAt = now
        }
        folders.removeAll { $0.id == folderId }
        tombstones.removeAll { $0.kind == .folder && $0.key == folderId.uuidString }
        tombstones.append(.folder(id: folderId, at: now))
        save()
        SyncCoordinator.shared.notifyFolderDeleted(id: folderId, at: now)
    }

    func renameFolder(_ folderId: UUID, name: String) {
        if let index = folders.firstIndex(where: { $0.id == folderId }) {
            let old = folders[index].name
            folders[index].name = name
            folders[index].updatedAt = Date()
            AppLogger.shared.log("Renamed folder \"\(old)\" -> \"\(name)\"", level: .info, category: .storage)
            save()
            SyncCoordinator.shared.notifyFolderUpdated(folders[index])
        }
    }

    func moveFeed(_ feedId: UUID, toFolder folderId: UUID?) {
        if let index = feeds.firstIndex(where: { $0.id == feedId }) {
            feeds[index].folderId = folderId
            feeds[index].updatedAt = Date()
            save()
            // A snapshot merge keeps the receiver's own folder, so send the change as an explicit update.
            SyncCoordinator.shared.notifyFeedAddedOrUpdated(feeds[index])
        }
    }


    func setFeedsInFolder(_ folderId: UUID, feedIds: Set<UUID>) {
        var changedFeeds: [Feed] = []
        for i in feeds.indices {
            let shouldBeInFolder = feedIds.contains(feeds[i].id)
            if shouldBeInFolder && feeds[i].folderId != folderId {
                feeds[i].folderId = folderId
                feeds[i].updatedAt = Date()
                changedFeeds.append(feeds[i])
            } else if !shouldBeInFolder && feeds[i].folderId == folderId {
                feeds[i].folderId = nil
                feeds[i].updatedAt = Date()
                changedFeeds.append(feeds[i])
            }
        }
        if !changedFeeds.isEmpty {
            save()
            for feed in changedFeeds {
                SyncCoordinator.shared.notifyFeedAddedOrUpdated(feed)
            }
        }
    }

    func feedsInFolder(_ folderId: UUID) -> [Feed] {
        cachedFeedsInFolder[folderId] ?? []
    }

    func uncategorizedFeeds() -> [Feed] {
        cachedUncategorizedFeeds
    }

    func pinnedFeeds() -> [Feed] {
        cachedPinnedFeeds
    }

    func isPinned(feedId: UUID) -> Bool {
        cachedFeedMap[feedId]?.isPinned ?? false
    }

    func togglePin(feedId: UUID) {
        guard let index = feeds.firstIndex(where: { $0.id == feedId }) else { return }
        feeds[index].isPinned.toggle()
        feeds[index].updatedAt = Date()
        let updatedFeed = feeds[index]
        save()
        SyncCoordinator.shared.notifyFeedAddedOrUpdated(updatedFeed)
        AppLogger.shared.log("Toggled pin for \"\(updatedFeed.title)\": \(updatedFeed.isPinned)", level: .info, category: .storage)
    }

    func setFeedPinned(_ feedId: UUID, isPinned: Bool) {
        guard let index = feeds.firstIndex(where: { $0.id == feedId }), feeds[index].isPinned != isPinned else { return }
        feeds[index].isPinned = isPinned
        feeds[index].updatedAt = Date()
        let updatedFeed = feeds[index]
        save()
        SyncCoordinator.shared.notifyFeedAddedOrUpdated(updatedFeed)
        AppLogger.shared.log("Set pin for \"\(updatedFeed.title)\": \(isPinned)", level: .info, category: .storage)
    }

    func reorderPinnedFeeds(fromOffsets source: IndexSet, toOffset destination: Int) {
        var pinned = cachedPinnedFeeds
        pinned.move(fromOffsets: source, toOffset: destination)

        var pinnedIterator = pinned.makeIterator()
        for i in feeds.indices {
            if feeds[i].isPinned {
                if let next = pinnedIterator.next() {
                    feeds[i] = next
                }
            }
        }
        save()
        AppLogger.shared.log("Reordered pinned feeds", level: .info, category: .ui)
    }
}
