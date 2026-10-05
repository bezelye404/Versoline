import Foundation
import Observation
import AppKit

// Off by default. When enabled the app advertises on the local network, but only talks to devices the
// user has paired (see `PeerHandshake`). There is no server, no cloud storage and no account.
//
// What is synced: feeds and folders (union, nothing is deleted by a snapshot), read states, bookmarks
// and reader/appearance settings. What is not: article bodies, downloaded episodes, caches.

@Observable
@MainActor
final class SyncCoordinator {

    static let shared = SyncCoordinator()

    enum PairingState: Equatable {
        case idle
        case searching
        case confirming(peerName: String, code: String)
        case succeeded(peerName: String)
        case failed(String)
    }

    // Observable UI state
    private(set) var isEnabled = false
    private(set) var pairingState: PairingState = .idle
    private(set) var trustedPeers: [TrustedPeer] = []
    private(set) var connectedPeerCount = 0
    private(set) var lastSyncDate: Date?

    @ObservationIgnored private lazy var trustStore = PeerTrustStore(directory: Self.storageDirectory)
    @ObservationIgnored private lazy var engine = LocalPeerSyncEngine(trustStore: trustStore)
    @ObservationIgnored private weak var feedStore: FeedStore?
    @ObservationIgnored private var settingsDebounce: Task<Void, Never>?
    @ObservationIgnored private var pairingTimeout: Task<Void, Never>?
    @ObservationIgnored private var isApplyingRemoteSettings = false
    @ObservationIgnored private var lastBroadcastSettings: SyncSettings?
    @ObservationIgnored private var engineConfigured = false

    private static var storageDirectory: URL {
        AppInfo.supportDirectory
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: AppSettingsKeys.isLocalPeerSyncEnabled)
        // iCloud Drive sync was removed; forget its leftover switch.
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.legacyICloudSyncEnabled)
        setupSettingsObserver()
    }

    func configure(with store: FeedStore) {
        feedStore = store
        if isEnabled { startEngine() }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: AppSettingsKeys.isLocalPeerSyncEnabled)
        if enabled {
            startEngine()
        } else {
            cancelPairing()
            if engineConfigured { engine.stop() }
            connectedPeerCount = 0
        }
    }

    private func startEngine() {
        configureEngineIfNeeded()
        trustedPeers = trustStore.peers
        engine.start()
    }

    private func configureEngineIfNeeded() {
        guard !engineConfigured else { return }
        engineConfigured = true

        var handlers = LocalPeerSyncEngine.Handlers()
        handlers.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in self?.handleIncoming(event) }
        }
        handlers.onAuthenticated = { [weak self] peer, newlyPaired in
            Task { @MainActor [weak self] in self?.peerAuthenticated(peer, newlyPaired: newlyPaired) }
        }
        handlers.onAuthenticatedCountChanged = { [weak self] count in
            Task { @MainActor [weak self] in self?.connectedPeerCount = count }
        }
        handlers.onConfirmation = { [weak self] name, code in
            Task { @MainActor [weak self] in self?.pairingState = .confirming(peerName: name, code: code) }
        }
        handlers.onPairingFailed = { [weak self] reason in
            Task { @MainActor [weak self] in self?.pairingFailed(reason) }
        }
        handlers.onLog = { message, level in
            Task { @MainActor in AppLogger.shared.log(message, level: level, category: .network) }
        }
        engine.setHandlers(handlers)
    }

    /// Opens a two-minute window in which this Mac accepts a new device. The other Mac must do the same.
    func startPairing() {
        guard isEnabled else { return }
        configureEngineIfNeeded()
        pairingState = .searching
        engine.setPairingMode(true)
        pairingTimeout?.cancel()
        pairingTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, let self, self.pairingState == .searching else { return }
            self.pairingFailed(String(localized: "No device was found. Open Pair New Device on the other Mac too."))
        }
    }

    func cancelPairing() {
        pairingTimeout?.cancel()
        if engineConfigured { engine.setPairingMode(false) }
        pairingState = .idle
    }

    /// The user compared the six-digit codes on both screens.
    func confirmPairing(codesMatch: Bool) {
        guard case .confirming = pairingState else { return }
        engine.confirmPairing(accepted: codesMatch)
        if !codesMatch { cancelPairing() }
    }

    /// After "Reset All Data": stop syncing and drop the in-memory identity and pairings.
    func resetAfterFactoryReset() {
        setEnabled(false)
        trustStore.forgetAll()
        trustedPeers = []
        lastSyncDate = nil
    }

    func removeTrustedPeer(_ peer: TrustedPeer) {
        trustStore.remove(peer.deviceId)
        trustedPeers = trustStore.peers
    }

    private func pairingFailed(_ reason: String) {
        pairingTimeout?.cancel()
        engine.setPairingMode(false)
        if pairingState != .idle { pairingState = .failed(reason) }
    }

    private func peerAuthenticated(_ peer: TrustedPeer, newlyPaired: Bool) {
        if newlyPaired {
            pairingTimeout?.cancel()
            engine.setPairingMode(false)
            pairingState = .succeeded(peerName: peer.name)
        }
        trustedPeers = trustStore.peers
        sendSnapshot(to: peer)
    }

    private func sendSnapshot(to peer: TrustedPeer) {
        guard let store = feedStore else { return }
        var events = store.syncSnapshotEvents()
        events.append(.settings(SyncSettings.current()))
        engine.send(events, to: peer.deviceId)
        lastSyncDate = Date()
    }

    /// "Sync Now": sends the full snapshot to every connected paired device.
    func syncNow() {
        guard isEnabled, connectedPeerCount > 0, let store = feedStore else { return }
        var events = store.syncSnapshotEvents()
        events.append(.settings(SyncSettings.current()))
        for event in events { engine.broadcast(event) }
        lastSyncDate = Date()
    }

    /// Re-sends feeds, folders and deletion records (used after bulk changes such as an OPML import).
    func notifyFeedsOrFoldersChanged() {
        guard isEnabled, connectedPeerCount > 0, let store = feedStore else { return }
        for event in store.syncFeedSnapshotEvents() { engine.broadcast(event) }
    }

    func notifyReadArticles(links: [String]) {
        guard isEnabled, connectedPeerCount > 0 else { return }
        engine.broadcast(.readArticles(hashes: links.map { $0.syncHash64 }))
    }

    func notifyBookmarkToggled(link: String, isBookmarked: Bool) {
        guard isEnabled, connectedPeerCount > 0 else { return }
        engine.broadcast(.bookmarkToggled(link: link, isBookmarked: isBookmarked))
    }

    func notifyFeedAddedOrUpdated(_ feed: Feed) {
        guard isEnabled, connectedPeerCount > 0 else { return }
        engine.broadcast(.feedAddedOrUpdated(feed: SyncFeed(
            id: feed.id, title: feed.title, url: feed.url, folderId: feed.folderId,
            isPinned: feed.isPinned, updatedAt: feed.updatedAt ?? SyncMerge.epoch)))
    }

    func notifyFeedDeleted(url: String, at date: Date) {
        guard isEnabled, connectedPeerCount > 0 else { return }
        engine.broadcast(.feedDeleted(url: url, deletedAt: date))
    }

    func notifyFolderUpdated(_ folder: Folder) {
        guard isEnabled, connectedPeerCount > 0 else { return }
        engine.broadcast(.folderUpdated(folder: SyncFolder(id: folder.id, name: folder.name, updatedAt: folder.updatedAt ?? SyncMerge.epoch)))
    }

    func notifyFolderDeleted(id: UUID, at date: Date) {
        guard isEnabled, connectedPeerCount > 0 else { return }
        engine.broadcast(.folderDeleted(id: id, deletedAt: date))
    }

    private func setupSettingsObserver() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, self.connectedPeerCount > 0, !self.isApplyingRemoteSettings else { return }
                self.scheduleSettingsBroadcast()
            }
        }
    }

    private func scheduleSettingsBroadcast() {
        settingsDebounce?.cancel()
        settingsDebounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self, self.isEnabled else { return }
            let current = SyncSettings.current()
            if let last = self.lastBroadcastSettings, last.hasSamePreferences(as: current) { return }
            self.lastBroadcastSettings = current
            self.engine.broadcast(.settings(current))
        }
    }

    private func handleIncoming(_ event: SyncPeerEvent) {
        guard isEnabled else { return }
        if case .settings(let remote) = event {
            let (merged, shouldUpdateLocal, _) = SmartMergeEngine.mergeSettings(local: SyncSettings.current(), remote: remote)
            if shouldUpdateLocal {
                isApplyingRemoteSettings = true
                merged.applyToUserDefaults()
                isApplyingRemoteSettings = false
                lastBroadcastSettings = merged
            }
            lastSyncDate = Date()
            return
        }
        feedStore?.applySyncEvent(event)
        lastSyncDate = Date()
    }
}
