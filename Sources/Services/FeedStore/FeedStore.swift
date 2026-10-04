import Foundation
import SwiftUI
import WebKit

struct FullscreenVideoContext: Identifiable, Equatable {
    var id: String { videoID }
    let videoID: String
    let title: String
    let link: String
}

@MainActor
@Observable
final class FeedStore {

    nonisolated static let maxItemsPerFeed = 70

    var feeds: [Feed] = []
    var items: [UUID: [FeedItem]] = [:]
    var folders: [Folder] = []
    /// Deletion records for nearby sync (see `SmartMergeEngine.merge`). Persisted in `data.json`.
    var tombstones: [Tombstone] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var fullscreenVideo: FullscreenVideoContext?

    /// Set when an existing database file could not be read. Saving is blocked in that
    /// state so the unreadable file is never overwritten by an empty library.
    /// Not `private(set)` because the split-out `FeedStore+*.swift` extensions write it.
    var loadFailed = false
    /// One-time message shown at startup when the database had to be set aside.
    var startupRecoveryNotice: String?

    let saveURL: URL
    /// Disk cache for article bodies. Injected so tests never touch the user's real cache.
    let readerCache: ReaderModeExtractor
    var pendingSaveTask: Task<Void, Never>?

    // Fast O(1) in-memory cached aggregates. Written only by `FeedStore+Counts.swift`.
    var cachedTotalUnreadCount: Int = 0
    var cachedTotalItemCount: Int = 0
    var cachedBookmarkCount: Int = 0
    var cachedTodayCount: Int = 0
    var cachedStreamCounts: [ItemStream: Int] = [:]
    var cachedTotalReadCount: Int = 0
    var cachedFeedUnreadCounts: [UUID: Int] = [:]
    var cachedFeedMap: [UUID: Feed] = [:]
    var cachedFeedsInFolder: [UUID: [Feed]] = [:]
    var cachedUncategorizedFeeds: [Feed] = []
    var cachedPinnedFeeds: [Feed] = []

    // Active View Cache: Holds exactly ONE sorted list in memory corresponding to the active view.
    // Switching views releases previous arrays, saving 70-80% heap compared to multi-array caching.
    struct ActiveViewCache {
        let key: String
        let items: [FeedItem]
    }
    @ObservationIgnored var activeViewCache: ActiveViewCache?
    @ObservationIgnored var cachedSmartCategoryCounts: [SmartCategory: Int] = [:]
    var activeSmartCategories: [SmartCategory] = []
    @ObservationIgnored var lastRefreshDate: Date?
    /// Feeds that keep failing wait longer between automatic refreshes (see `RefreshBackoff`).
    @ObservationIgnored var refreshBackoff: [UUID: RefreshBackoff] = [:]

    static let dayOfWeekFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE"
        return df
    }()

    func getActiveViewItems(key: String, compute: () -> [FeedItem]) -> [FeedItem] {
        if let current = activeViewCache, current.key == key {
            return current.items
        }
        let computed = compute()
        activeViewCache = ActiveViewCache(key: key, items: computed)
        return computed
    }

    func invalidateItemCaches() {
        activeViewCache = nil
    }

    func updateItemInActiveViewCache(_ updatedItem: FeedItem) {
        guard let current = activeViewCache else { return }
        if let idx = current.items.firstIndex(where: { $0.id == updatedItem.id }) {
            var newItems = current.items
            newItems[idx] = updatedItem
            activeViewCache = ActiveViewCache(key: current.key, items: newItems)
        }
    }

    func compactMemory(deep: Bool = false) {
        if deep {
            invalidateItemCaches()
        }
        ImageDownsampleCache.shared.clearMemory()
        CuratedFeedManager.shared.clearMemory()
        WebView.flushMemoryCache()

        if deep {
            Task.detached(priority: .background) { [weak self] in
                guard let self else { return }
                let preserved = await MainActor.run {
                    Set(self.items.values.flatMap { $0 }.filter { $0.isBookmarked }.map { $0.link })
                }
                await readerCache.enforceQuota(maxSizeBytes: 50 * 1024 * 1024, preservedLinks: preserved)
                await ImageDownsampleCache.shared.enforceQuota(maxSizeBytes: 30 * 1024 * 1024)
            }
        }
        AppLogger.shared.log("In-memory transient caches compacted for background memory relief", level: .debug, category: .storage)
    }

    /// - Parameter storageDirectory: Overrides the default `Application Support/Versoline`
    ///   location. Intended for tests; skips app-wide sync wiring when set. `readerCache` is
    ///   likewise replaceable in tests.
    init(storageDirectory: URL? = nil, readerCache: ReaderModeExtractor = .shared) {
        self.readerCache = readerCache
        let appDir: URL
        if let storageDirectory {
            appDir = storageDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            appDir = appSupport.appendingPathComponent("Versoline", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.saveURL = appDir
        load()
        // Decoding the library leaves a lot of freed-but-resident pages behind; hand them back.
        MemoryRelief.trim()

        let cleanupDays = UserDefaults.standard.integer(forKey: AppSettingsKeys.autoCleanupDays)
        if cleanupDays > 0 {
            autoCleanup(olderThanDays: cleanupDays)
        } else {
            // Scanning every cached article is not needed to show the window: do it a few seconds later.
            let preserved = Set(items.values.flatMap { $0 }.filter { $0.isBookmarked }.map { $0.link })
            let cache = readerCache
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                cache.enforceQuota(maxSizeBytes: 150 * 1024 * 1024, preservedLinks: preserved)
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("VersolineCompactMemory"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.compactMemory(deep: false)
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("VersolineDeepCompactMemory"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.compactMemory(deep: true)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushPendingSave()
            }
        }

        if storageDirectory == nil {
            SyncCoordinator.shared.configure(with: self)
        }
    }
}
