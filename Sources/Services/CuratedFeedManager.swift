import Foundation
import Observation

@Observable
@MainActor
final class CuratedFeedManager {

    static let shared = CuratedFeedManager()

    private(set) var categories: [CuratedFeedCategory] = []
    private(set) var isUpdatingFromRemote = false

    private static let remoteManifestURL = URL(string: "https://raw.githubusercontent.com/bezelye404/easyRSS/main/Sources/Resources/curated_feeds.json")!

    private var cacheFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("EasyRSS", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("curated_feeds_cache.json")
    }

    private init() {
        loadLocal()
        checkForRemoteUpdates()
    }

    // MARK: - 0ms Fast Local Load

    func loadLocal() {
        // 1. Prefer persisted dynamic cache if available
        let diskURL = cacheFileURL
        if FileManager.default.fileExists(atPath: diskURL.path),
           let cachedData = try? Data(contentsOf: diskURL),
           let list = try? JSONDecoder().decode([CuratedFeedCategory].self, from: cachedData),
           !list.isEmpty {
            self.categories = list
            AppLogger.shared.log("Loaded \(list.count) curated categories from disk cache", level: .info, category: .storage)
            return
        }

        // 2. Fallback to bundled curated_feeds.json
        if let bundleURL = Bundle.main.url(forResource: "curated_feeds", withExtension: "json"),
           let bundleData = try? Data(contentsOf: bundleURL),
           let list = try? JSONDecoder().decode([CuratedFeedCategory].self, from: bundleData) {
            self.categories = list
            AppLogger.shared.log("Loaded \(list.count) curated categories from app bundle", level: .info, category: .storage)
            return
        }
    }

    // MARK: - Silent Remote Sync with Local Cache & ETag

    func checkForRemoteUpdates() {
        guard !isUpdatingFromRemote else { return }
        isUpdatingFromRemote = true

        let targetURL = Self.remoteManifestURL
        let cacheDest = cacheFileURL
        let storedETag = UserDefaults.standard.string(forKey: "CuratedFeeds_LastETag")

        Task.detached(priority: .utility) {
            var request = URLRequest(url: targetURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("easyRSS/1.0", forHTTPHeaderField: "User-Agent")
            if let storedETag, !storedETag.isEmpty {
                request.setValue(storedETag, forHTTPHeaderField: "If-None-Match")
            }

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    CuratedFeedManager.shared.isUpdatingFromRemote = false
                }
                return
            }

            // 304 Not Modified: Cache is already up to date, 0 bytes needed
            if httpResponse.statusCode == 304 {
                await MainActor.run {
                    CuratedFeedManager.shared.isUpdatingFromRemote = false
                }
                return
            }

            // 200 OK: New content received
            if httpResponse.statusCode == 200,
               let remoteCategories = try? JSONDecoder().decode([CuratedFeedCategory].self, from: data),
               !remoteCategories.isEmpty {

                // Persist new ETag if provided
                if let newETag = httpResponse.value(forHTTPHeaderField: "Etag") ?? httpResponse.value(forHTTPHeaderField: "ETag") {
                    UserDefaults.standard.set(newETag, forKey: "CuratedFeeds_LastETag")
                }

                // Write atomic cache to disk
                try? data.write(to: cacheDest, options: .atomic)

                await MainActor.run {
                    CuratedFeedManager.shared.categories = remoteCategories
                    CuratedFeedManager.shared.isUpdatingFromRemote = false
                    AppLogger.shared.log("Updated curated feed catalog with \(remoteCategories.count) categories from remote CDN", level: .info, category: .network)
                }
            } else {
                await MainActor.run {
                    CuratedFeedManager.shared.isUpdatingFromRemote = false
                }
            }
        }
    }

    var totalFeedCount: Int {
        categories.reduce(0) { $0 + $1.feeds.count }
    }

    func allFeeds() -> [(category: String, feed: CuratedFeed)] {
        categories.flatMap { cat in
            cat.feeds.map { (category: cat.category, feed: $0) }
        }
    }
}
