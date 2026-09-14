import Foundation
import Observation
import AppKit

// MARK: - Sync Coordinator (Dual-Engine Orchestrator)

@Observable
@MainActor
final class SyncCoordinator {

    static let shared = SyncCoordinator()

    // Observable UI State
    var isEnabled: Bool = false
    var isLocalP2PEnabled: Bool = false
    private(set) var lastSyncDate: Date?
    private(set) var connectedPeerCount: Int = 0
    private(set) var isSyncing: Bool = false
    private(set) var statusMessage: String = ""

    var syncDirectoryPath: String {
        icloudEngine.syncDirectoryURL.path
    }

    var isICloudAvailable: Bool {
        icloudEngine.isICloudDriveAvailable
    }

    // Engine Instances
    private let icloudEngine = ICloudDriveSyncEngine()
    private let peerEngine = LocalPeerSyncEngine()

    private var debounceSaveTask: Task<Void, Never>?
    private weak var feedStore: FeedStore?

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: AppSettingsKeys.isSyncEnabled) as? Bool ?? false
        self.isLocalP2PEnabled = UserDefaults.standard.object(forKey: AppSettingsKeys.isLocalPeerSyncEnabled) as? Bool ?? false

        setupEngines()
    }

    func configure(with store: FeedStore) {
        self.feedStore = store
        if isEnabled {
            Task {
                await performSync()
            }
        }
    }

    private func setupEngines() {
        // 1. Local P2P Peer Handler
        peerEngine.onConnectedPeersChanged = { [weak self] count in
            Task { @MainActor [weak self] in
                self?.connectedPeerCount = count
            }
        }

        peerEngine.onPeerEventReceived = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, self.isLocalP2PEnabled else { return }
                self.handleIncomingPeerEvent(event)
            }
        }

        // 2. Start engines if enabled by user
        if isEnabled {
            startICloudObserving()
            if isLocalP2PEnabled {
                peerEngine.start()
            }
        }
    }

    private func startICloudObserving() {
        icloudEngine.startObserving { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }
                AppLogger.shared.log("iCloud Drive remote changes detected, triggering sync", level: .info, category: .storage)
                await self.performSync()
            }
        }
    }

    func setSyncEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: AppSettingsKeys.isSyncEnabled)
        if enabled {
            startICloudObserving()
            if isLocalP2PEnabled { peerEngine.start() }
            Task { await performSync() }
        } else {
            icloudEngine.stopObserving()
            peerEngine.stop()
            statusMessage = ""
        }
    }

    func setLocalP2PEnabled(_ enabled: Bool) {
        self.isLocalP2PEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: AppSettingsKeys.isLocalPeerSyncEnabled)
        if enabled && isEnabled {
            peerEngine.start()
        } else {
            peerEngine.stop()
        }
    }

    // MARK: - Full Synchronization Flow

    func performSync() async {
        guard isEnabled, let store = feedStore, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        statusMessage = String(localized: "Syncing with iCloud Drive...")

        // 1. Load remote manifest and states
        let remoteManifest = icloudEngine.loadManifest()
        let remoteStates = icloudEngine.loadStates()

        // 2. Perform Smart Merge on Feeds & Folders
        let (mergedFeeds, updatedSyncFeeds) = SmartMergeEngine.mergeFeeds(
            localFeeds: store.feeds,
            remoteSyncFeeds: remoteManifest?.feeds ?? []
        )
        let (mergedFolders, updatedSyncFolders) = SmartMergeEngine.mergeFolders(
            localFolders: store.folders,
            remoteFolders: remoteManifest?.folders ?? []
        )

        // 3. Perform Smart Merge on Read Hashes & Bookmarks
        let localReadHashes = Set(store.items.values.flatMap { $0 }.filter { $0.isRead }.map { $0.link.syncHash64 })
        let mergedReadHashes = SmartMergeEngine.mergeReadHashes(
            localHashes: localReadHashes,
            remoteHashes: remoteStates?.readItemHashes ?? []
        )

        let localBookmarks = Set(store.bookmarkedItems().map { $0.link })
        let mergedBookmarks = SmartMergeEngine.mergeBookmarks(
            localBookmarkLinks: localBookmarks,
            remoteBookmarkLinks: remoteStates?.bookmarkedLinks ?? []
        )

        // 4. Apply back to FeedStore
        store.applySyncUpdate(
            feeds: mergedFeeds,
            folders: mergedFolders,
            readHashes: mergedReadHashes,
            bookmarkedLinks: mergedBookmarks
        )

        // 5. Write back updated coordinated files
        let newManifest = SyncManifest(
            deviceId: Host.current().localizedName ?? "Mac",
            updatedAt: Date(),
            feeds: updatedSyncFeeds,
            folders: updatedSyncFolders
        )
        icloudEngine.saveManifest(newManifest)

        let newStates = SyncStates(
            deviceId: Host.current().localizedName ?? "Mac",
            updatedAt: Date(),
            readItemHashes: Array(mergedReadHashes),
            bookmarkedLinks: Array(mergedBookmarks)
        )
        icloudEngine.saveStates(newStates)

        self.lastSyncDate = Date()
        statusMessage = String(localized: "Up to date")
        AppLogger.shared.log("Full sync complete (\(mergedFeeds.count) feeds, \(mergedReadHashes.count) read items)", level: .info, category: .storage)
    }

    // MARK: - Outgoing Event Notifications (Sub-100ms P2P + Debounced iCloud)

    func notifyReadArticles(links: [String]) {
        guard isEnabled else { return }
        let hashes = links.map { $0.syncHash64 }

        // Anında yerel ağdaki cihazlara fırlat (50ms)
        if isLocalP2PEnabled {
            peerEngine.broadcastEvent(.readArticles(hashes: hashes))
        }

        scheduleDebouncedSave()
    }

    func notifyBookmarkToggled(link: String, isBookmarked: Bool) {
        guard isEnabled else { return }
        if isLocalP2PEnabled {
            peerEngine.broadcastEvent(.bookmarkToggled(link: link, isBookmarked: isBookmarked))
        }
        scheduleDebouncedSave()
    }

    func notifyFeedAddedOrUpdated(_ feed: Feed) {
        guard isEnabled else { return }
        let syncFeed = SyncFeed(
            id: feed.id,
            title: feed.title,
            url: feed.url,
            folderId: feed.folderId,
            updatedAt: Date(),
            deletedAt: nil
        )
        if isLocalP2PEnabled {
            peerEngine.broadcastEvent(.feedAddedOrUpdated(feed: syncFeed))
        }
        scheduleDebouncedSave()
    }

    func notifyFeedDeleted(id: UUID) {
        guard isEnabled else { return }
        if isLocalP2PEnabled {
            peerEngine.broadcastEvent(.feedDeleted(id: id, deletedAt: Date()))
        }
        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        guard isEnabled else { return }
        debounceSaveTask?.cancel()
        debounceSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s debounce
            guard !Task.isCancelled, self.isEnabled else { return }
            await self.performSync()
        }
    }

    // MARK: - Incoming Peer Event Handler

    private func handleIncomingPeerEvent(_ event: SyncPeerEvent) {
        guard let store = feedStore else { return }

        switch event {
        case .readArticles(let hashes):
            store.applyIncomingReadHashes(Set(hashes))

        case .bookmarkToggled(let link, let isBookmarked):
            store.applyIncomingBookmark(link: link, isBookmarked: isBookmarked)

        case .feedAddedOrUpdated(let syncFeed):
            store.applyIncomingFeed(syncFeed)

        case .feedDeleted(let id, _):
            store.applyIncomingFeedDeletion(id: id)

        case .requestFullSync:
            Task {
                await self.performSync()
            }
        }
    }
}
