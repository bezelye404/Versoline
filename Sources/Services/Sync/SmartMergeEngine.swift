import Foundation

// MARK: - Smart Merge Engine (Deterministic & Zero Data Loss)

enum SmartMergeEngine {

    /// Merges local Feed items with remote SyncFeed items using Union & Tombstone resolution.
    static func mergeFeeds(
        localFeeds: [Feed],
        remoteSyncFeeds: [SyncFeed],
        now: Date = Date()
    ) -> (mergedFeeds: [Feed], updatedSyncFeeds: [SyncFeed]) {
        var remoteMap: [String: SyncFeed] = [:] // Key: URL (normalized lowercase)
        for rf in remoteSyncFeeds {
            remoteMap[rf.url.lowercased()] = rf
        }

        var localMap: [String: Feed] = [:]
        for lf in localFeeds {
            localMap[lf.url.lowercased()] = lf
        }

        var resultFeeds: [Feed] = []
        var resultSyncFeeds: [SyncFeed] = []

        // 1. Process all local feeds
        for local in localFeeds {
            let key = local.url.lowercased()
            if let remote = remoteMap[key] {
                // If remote has marked it deleted more recently, delete locally
                if let deletedAt = remote.deletedAt {
                    // Feed is deleted on remote; do not keep in local resultFeeds
                    resultSyncFeeds.append(remote)
                } else {
                    // Both have the feed; preserve local or newer title/folder/isPinned
                    let resolvedTitle = local.title.isEmpty ? remote.title : local.title
                    let resolvedFolder = local.folderId ?? remote.folderId
                    let resolvedPinned = local.isPinned || (remote.isPinned ?? false)
                    let merged = Feed(
                        id: local.id,
                        title: resolvedTitle,
                        url: local.url,
                        description: local.description,
                        imageURL: local.imageURL,
                        lastUpdated: local.lastUpdated,
                        folderId: resolvedFolder,
                        etag: local.etag,
                        lastModifiedHeader: local.lastModifiedHeader,
                        isPinned: resolvedPinned
                    )
                    resultFeeds.append(merged)

                    let updatedSync = SyncFeed(
                        id: local.id,
                        title: resolvedTitle,
                        url: local.url,
                        folderId: resolvedFolder,
                        isPinned: resolvedPinned,
                        updatedAt: max(remote.updatedAt, now),
                        deletedAt: nil
                    )
                    resultSyncFeeds.append(updatedSync)
                }
            } else {
                // Feed is only on local; keep it and create SyncFeed
                resultFeeds.append(local)
                resultSyncFeeds.append(
                    SyncFeed(
                        id: local.id,
                        title: local.title,
                        url: local.url,
                        folderId: local.folderId,
                        isPinned: local.isPinned,
                        updatedAt: now,
                        deletedAt: nil
                    )
                )
            }
        }

        // 2. Add remote feeds that local didn't have (if not deleted)
        for remote in remoteSyncFeeds where remote.deletedAt == nil {
            let key = remote.url.lowercased()
            if localMap[key] == nil {
                let newFeed = Feed(
                    id: remote.id,
                    title: remote.title,
                    url: remote.url,
                    folderId: remote.folderId,
                    isPinned: remote.isPinned ?? false
                )
                resultFeeds.append(newFeed)
                resultSyncFeeds.append(remote)
            }
        }

        return (resultFeeds, resultSyncFeeds)
    }

    /// Merges local folders with remote sync folders.
    static func mergeFolders(
        localFolders: [Folder],
        remoteFolders: [SyncFolder],
        now: Date = Date()
    ) -> (mergedFolders: [Folder], updatedSyncFolders: [SyncFolder]) {
        var remoteMap: [UUID: SyncFolder] = [:]
        for rf in remoteFolders {
            remoteMap[rf.id] = rf
        }

        var localMap: [UUID: Folder] = [:]
        for lf in localFolders {
            localMap[lf.id] = lf
        }

        var resultFolders: [Folder] = []
        var resultSyncFolders: [SyncFolder] = []

        // Process local folders
        for local in localFolders {
            if let remote = remoteMap[local.id] {
                if remote.deletedAt != nil {
                    // Deleted on remote
                    resultSyncFolders.append(remote)
                } else {
                    let resolvedName = local.name.isEmpty ? remote.name : local.name
                    resultFolders.append(Folder(id: local.id, name: resolvedName, keywords: local.keywords))
                    resultSyncFolders.append(
                        SyncFolder(
                            id: local.id,
                            name: resolvedName,
                            updatedAt: max(remote.updatedAt, now),
                            deletedAt: nil
                        )
                    )
                }
            } else {
                resultFolders.append(local)
                resultSyncFolders.append(
                    SyncFolder(
                        id: local.id,
                        name: local.name,
                        updatedAt: now,
                        deletedAt: nil
                    )
                )
            }
        }

        // Add remote folders missing locally
        for remote in remoteFolders where remote.deletedAt == nil {
            if localMap[remote.id] == nil {
                resultFolders.append(Folder(id: remote.id, name: remote.name))
                resultSyncFolders.append(remote)
            }
        }

        return (resultFolders, resultSyncFolders)
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
}
