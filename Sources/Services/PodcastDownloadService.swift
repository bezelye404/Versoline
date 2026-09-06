import Foundation
import SwiftUI

@MainActor
@Observable
final class PodcastDownloadService {

    static let shared = PodcastDownloadService()

    private(set) var downloadedEpisodeIDs: Set<UUID> = []
    private(set) var activeDownloads: [UUID: Double] = [:] // Progress 0.0...1.0

    @ObservationIgnored private let downloadsDirectory: URL
    @ObservationIgnored private var downloadTasks: [UUID: URLSessionDownloadTask] = [:]

    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600 // 1 hour max download
        return URLSession(configuration: config)
    }()

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("EasyRSS/Downloads", isDirectory: true)
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
        guard let urlString = item.audioURL, let streamURL = URL(string: urlString) else { return }
        guard !isDownloaded(item.id), activeDownloads[item.id] == nil else { return }

        let itemId = item.id
        activeDownloads[itemId] = 0.05
        AppLogger.shared.log("Starting offline download for episode: \(item.title)", level: .info, category: .network)

        let destination = downloadsDirectory.appendingPathComponent("\(itemId.uuidString).mp3")

        let task = session.downloadTask(with: streamURL) { [weak self] tempURL, response, error in
            Task { @MainActor in
                guard let self else { return }
                self.activeDownloads.removeValue(forKey: itemId)
                self.downloadTasks.removeValue(forKey: itemId)

                if let tempURL, error == nil {
                    do {
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: tempURL, to: destination)
                        self.downloadedEpisodeIDs.insert(itemId)
                        AppLogger.shared.log("Successfully downloaded episode: \(item.title)", level: .info, category: .storage)
                    } catch {
                        AppLogger.shared.log("Failed to save downloaded file: \(error.localizedDescription)", level: .error, category: .storage)
                    }
                } else if let error {
                    AppLogger.shared.log("Download failed: \(error.localizedDescription)", level: .error, category: .network)
                }
            }
        }

        downloadTasks[itemId] = task
        task.resume()
    }

    func cancelDownload(for episodeId: UUID) {
        downloadTasks[episodeId]?.cancel()
        downloadTasks.removeValue(forKey: episodeId)
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
