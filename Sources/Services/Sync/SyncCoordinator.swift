import Foundation
import Observation
import AppKit

// MARK: - Sync Coordinator (Dual-Engine Delta Orchestrator)

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

    private var debounceFeedsTask: Task<Void, Never>?
    private var debounceStatesTask: Task<Void, Never>?
    private var debounceSettingsTask: Task<Void, Never>?
    private weak var feedStore: FeedStore?
    private var isApplyingRemoteSettings = false

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: AppSettingsKeys.isSyncEnabled) as? Bool ?? false
        self.isLocalP2PEnabled = UserDefaults.standard.object(forKey: AppSettingsKeys.isLocalPeerSyncEnabled) as? Bool ?? false

        setupEngines()
        setupSettingsObserver()
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

    private func setupSettingsObserver() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, !self.isApplyingRemoteSettings else { return }
                self.scheduleDebouncedSettingsSave()
            }
        }
    }

    private func startICloudObserving() {
        icloudEngine.startObserving { [weak self] changedURL in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }
                let filename = changedURL.lastPathComponent.lowercased()
                AppLogger.shared.log("iCloud Drive change detected: \(filename)", level: .info, category: .storage)

                if filename.contains("sync_settings") {
                    await self.performSync(scope: .settingsOnly)
                } else if filename.contains("sync_states") {
                    await self.performSync(scope: .statesOnly)
                } else if filename.contains("sync_manifest") || filename.contains(".opml") {
                    await self.performSync(scope: .feedsAndOPMLOnly)
                } else {
                    await self.performSync(scope: .all)
                }
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

    // MARK: - Scoped Synchronization

    enum SyncScope {
        case all
        case settingsOnly
        case feedsAndOPMLOnly
        case statesOnly
    }

    func performSync(scope: SyncScope = .all) async {
        guard isEnabled, let store = feedStore, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        statusMessage = String(localized: "Syncing with iCloud Drive...")

        // 1. Settings Pass
        if scope == .all || scope == .settingsOnly {
            syncSettings()
        }

        // 2. Feeds & OPML Pass
        if scope == .all || scope == .feedsAndOPMLOnly {
            syncFeedsAndOPML(store: store)
        }

        // 3. States Pass
        if scope == .all || scope == .statesOnly {
            syncStates(store: store)
        }

        self.lastSyncDate = Date()
        statusMessage = String(localized: "Up to date")
    }

    // MARK: - Delta Sync Components

    private func syncSettings() {
        let localSettings = SyncSettings.current()

        if let remoteSettings = icloudEngine.loadSettings() {
            let (merged, shouldUpdateLocal, shouldUpdateRemote) = SmartMergeEngine.mergeSettings(
                local: localSettings,
                remote: remoteSettings
            )

            if shouldUpdateLocal {
                isApplyingRemoteSettings = true
                merged.applyToUserDefaults()
                isApplyingRemoteSettings = false
                AppLogger.shared.log("Applied remote user settings from iCloud Drive", level: .info, category: .storage)
            }

            if shouldUpdateRemote {
                let wrote = icloudEngine.saveSettingsIfChanged(merged)
                if wrote {
                    AppLogger.shared.log("Saved updated user settings to iCloud Drive", level: .info, category: .storage)
                }
            }
        } else {
            // First-time export to iCloud
            let wrote = icloudEngine.saveSettingsIfChanged(localSettings)
            if wrote {
                AppLogger.shared.log("Exported initial user settings to iCloud Drive", level: .info, category: .storage)
            }
        }
    }

    private func syncFeedsAndOPML(store: FeedStore) {
        let remoteManifest = icloudEngine.loadManifest()
        let remoteOPML = icloudEngine.loadOPML()

        // 1. Parse remote OPML if present and extract any missing feeds/folders
        var currentFeeds = store.feeds
        var currentFolders = store.folders

        if let remoteOPML, let opmlData = remoteOPML.data(using: .utf8) {
            let opmlFeeds = OPMLManager().parse(data: opmlData)
            let (opmlFeedsResult, opmlFoldersResult, opmlChanged) = SmartMergeEngine.mergeOPMLFeeds(
                localFeeds: currentFeeds,
                localFolders: currentFolders,
                opmlFeeds: opmlFeeds
            )
            if opmlChanged {
                currentFeeds = opmlFeedsResult
                currentFolders = opmlFoldersResult
            }
        }

        // 2. Perform Smart Merge with remote manifest
        let (mergedFeeds, updatedSyncFeeds) = SmartMergeEngine.mergeFeeds(
            localFeeds: currentFeeds,
            remoteSyncFeeds: remoteManifest?.feeds ?? []
        )
        let (mergedFolders, updatedSyncFolders) = SmartMergeEngine.mergeFolders(
            localFolders: currentFolders,
            remoteFolders: remoteManifest?.folders ?? []
        )

        // 3. Apply to FeedStore if feeds or folders changed
        if mergedFeeds != store.feeds || mergedFolders != store.folders {
            store.applySyncUpdate(
                feeds: mergedFeeds,
                folders: mergedFolders,
                readHashes: Set(),
                bookmarkedLinks: Set()
            )
        }

        // 4. Delta-Save Manifest (only writes if changed)
        let newManifest = SyncManifest(
            deviceId: Host.current().localizedName ?? "Mac",
            updatedAt: Date(),
            feeds: updatedSyncFeeds,
            folders: updatedSyncFolders
        )
        let manifestWrote = icloudEngine.saveManifestIfChanged(newManifest)
        if manifestWrote {
            AppLogger.shared.log("Saved updated sync_manifest.json to iCloud Drive", level: .info, category: .storage)
        }

        // 5. Delta-Save OPML (only writes if changed)
        let newOPML = OPMLManager.generate(feeds: mergedFeeds, folders: mergedFolders)
        let opmlWrote = icloudEngine.saveOPMLIfChanged(newOPML)
        if opmlWrote {
            AppLogger.shared.log("Exported updated subscriptions.opml to iCloud Drive", level: .info, category: .storage)
        }
    }

    private func syncStates(store: FeedStore) {
        let remoteStates = icloudEngine.loadStates()

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

        // Apply back to FeedStore if remote had new read/bookmarked items
        if mergedReadHashes.count > localReadHashes.count || mergedBookmarks != localBookmarks {
            store.applyIncomingReadHashes(mergedReadHashes)
            for link in mergedBookmarks where !localBookmarks.contains(link) {
                store.applyIncomingBookmark(link: link, isBookmarked: true)
            }
        }

        // Delta-Save States (only writes if changed)
        let newStates = SyncStates(
            deviceId: Host.current().localizedName ?? "Mac",
            updatedAt: Date(),
            readItemHashes: Array(mergedReadHashes),
            bookmarkedLinks: Array(mergedBookmarks)
        )
        let statesWrote = icloudEngine.saveStatesIfChanged(newStates)
        if statesWrote {
            AppLogger.shared.log("Saved updated sync_states.json to iCloud Drive", level: .info, category: .storage)
        }
    }

    // MARK: - Outgoing Event Notifications (Targeted & Debounced)

    func notifySettingsChanged() {
        guard isEnabled else { return }
        scheduleDebouncedSettingsSave()
    }

    func notifyFeedsOrFoldersChanged() {
        guard isEnabled else { return }
        scheduleDebouncedFeedsSave()
    }

    func notifyReadArticles(links: [String]) {
        guard isEnabled else { return }
        let hashes = links.map { $0.syncHash64 }

        if isLocalP2PEnabled {
            peerEngine.broadcastEvent(.readArticles(hashes: hashes))
        }

        scheduleDebouncedStatesSave()
    }

    func notifyBookmarkToggled(link: String, isBookmarked: Bool) {
        guard isEnabled else { return }
        if isLocalP2PEnabled {
            peerEngine.broadcastEvent(.bookmarkToggled(link: link, isBookmarked: isBookmarked))
        }
        scheduleDebouncedStatesSave()
    }

    func notifyFeedAddedOrUpdated(_ feed: Feed) {
        guard isEnabled else { return }
        let syncFeed = SyncFeed(
            id: feed.id,
            title: feed.title,
            url: feed.url,
            folderId: feed.folderId,
            isPinned: feed.isPinned,
            updatedAt: Date(),
            deletedAt: nil
        )
        if isLocalP2PEnabled {
            peerEngine.broadcastEvent(.feedAddedOrUpdated(feed: syncFeed))
        }
        scheduleDebouncedFeedsSave()
    }

    func notifyFeedDeleted(id: UUID) {
        guard isEnabled else { return }
        if isLocalP2PEnabled {
            peerEngine.broadcastEvent(.feedDeleted(id: id, deletedAt: Date()))
        }
        scheduleDebouncedFeedsSave()
    }

    // MARK: - Debounced Delta Schedulers

    private func scheduleDebouncedSettingsSave() {
        guard isEnabled, !isApplyingRemoteSettings else { return }
        debounceSettingsTask?.cancel()
        debounceSettingsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, self.isEnabled else { return }
            self.syncSettings()
        }
    }

    private func scheduleDebouncedFeedsSave() {
        guard isEnabled else { return }
        debounceFeedsTask?.cancel()
        debounceFeedsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, self.isEnabled, let store = self.feedStore else { return }
            self.syncFeedsAndOPML(store: store)
        }
    }

    private func scheduleDebouncedStatesSave() {
        guard isEnabled else { return }
        debounceStatesTask?.cancel()
        debounceStatesTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, self.isEnabled, let store = self.feedStore else { return }
            self.syncStates(store: store)
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
