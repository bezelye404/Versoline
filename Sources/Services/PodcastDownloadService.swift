import Foundation

@MainActor
@Observable
final class PodcastDownloadService {

    static let shared = PodcastDownloadService()

    private(set) var downloadedEpisodeIDs: Set<UUID> = []
    /// Progress of each running download, 0 to 1.
    private(set) var activeDownloads: [UUID: Double] = [:]

    @ObservationIgnored private let downloadsDirectory: URL
    @ObservationIgnored private var downloadTasks: [UUID: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var progressObservations: [UUID: NSKeyValueObservation] = [:]

    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600 // 1 hour max download
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private init() {
        let dir = AppInfo.supportDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.downloadsDirectory = dir
        scanExistingDownloads()
    }

    func scanExistingDownloads() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil) else {
            downloadedEpisodeIDs = []
            return
        }

        var ids = Set<UUID>()
        for file in files {
            let filename = file.deletingPathExtension().lastPathComponent
            if let uuid = UUID(uuidString: filename) {
                ids.insert(uuid)
            }
        }
        self.downloadedEpisodeIDs = ids
    }

    func isDownloaded(_ episodeId: UUID) -> Bool {
        downloadedEpisodeIDs.contains(episodeId)
    }

    func localFileURL(for episodeId: UUID) -> URL? {
        let file = downloadsDirectory.appendingPathComponent("\(episodeId.uuidString).mp3")
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            return file
        }
        return nil
    }

    func downloadEpisode(_ item: FeedItem) {
        guard let urlString = item.audioURL, let streamURL = URL(string: urlString), AppInfo.isWebAddress(streamURL) else { return }
        guard !isDownloaded(item.id), activeDownloads[item.id] == nil else { return }

        let itemId = item.id
        activeDownloads[itemId] = 0.02
        AppLogger.shared.log("Starting offline download for episode: \(item.title)", level: .info, category: .network)

        let destination = downloadsDirectory.appendingPathComponent("\(itemId.uuidString).mp3")

        let task = session.downloadTask(with: streamURL) { [weak self] tempURL, response, error in
            // The temporary file is deleted as soon as this handler returns, so it is moved here and not later on the
            // main actor.
            var failure = error?.localizedDescription
            var saved = false
            if error == nil, let tempURL {
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    failure = "HTTP \(http.statusCode)"
                } else {
                    do {
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: tempURL, to: destination)
                        saved = true
                    } catch {
                        failure = error.localizedDescription
                    }
                }
            }
            let outcome = (saved: saved, failure: failure)
            Task { @MainActor in
                guard let self else { return }
                self.activeDownloads.removeValue(forKey: itemId)
                self.downloadTasks.removeValue(forKey: itemId)
                self.progressObservations.removeValue(forKey: itemId)
                if outcome.saved {
                    self.downloadedEpisodeIDs.insert(itemId)
                    AppLogger.shared.log("Downloaded episode: \(item.title)", level: .info, category: .storage)
                } else if let reason = outcome.failure {
                    AppLogger.shared.log("Download failed: \(reason)", level: .error, category: .network)
                }
            }
        }

        progressObservations[itemId] = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                guard let self, self.activeDownloads[itemId] != nil else { return }
                self.activeDownloads[itemId] = max(0.02, fraction)
            }
        }
        downloadTasks[itemId] = task
        task.resume()
    }

    func cancelDownload(for episodeId: UUID) {
        downloadTasks[episodeId]?.cancel()
        downloadTasks.removeValue(forKey: episodeId)
        progressObservations.removeValue(forKey: episodeId)
        activeDownloads.removeValue(forKey: episodeId)
    }

    func deleteDownload(for episodeId: UUID) {
        let file = downloadsDirectory.appendingPathComponent("\(episodeId.uuidString).mp3")
        try? FileManager.default.removeItem(at: file)
        downloadedEpisodeIDs.remove(episodeId)
        AppLogger.shared.log("Deleted offline download for episode ID: \(episodeId)", level: .info, category: .storage)
    }

    func deleteAllDownloads() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        downloadedEpisodeIDs.removeAll()
        AppLogger.shared.log("All offline podcast downloads cleared", level: .info, category: .storage)
    }

    var totalDownloadSizeBytes: Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for file in files {
            if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = attrs.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
