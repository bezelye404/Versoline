import Foundation
import AppKit

// MARK: - iCloud Drive Sync Engine (Turbo Coordinated File Storage)

final class ICloudDriveSyncEngine: NSObject, NSFilePresenter, @unchecked Sendable {

    var presentedItemURL: URL? { syncDirectoryURL }
    var presentedItemOperationQueue: OperationQueue { syncOperationQueue }

    private let syncOperationQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.bezelye.easyRSS.iCloudSyncQueue"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()

    private var onRemoteChangeHandler: (@Sendable () -> Void)?

    /// Resolves the iCloud Drive easyRSS directory path without requiring Apple Dev credentials.
    var syncDirectoryURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloudDocs = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/easyRSS", isDirectory: true)
        
        // If iCloud Drive is available on macOS, use it; otherwise fallback to local sync sandbox
        let parentDir = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: cloudDocs, withIntermediateDirectories: true)
            return cloudDocs
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let fallback = appSupport.appendingPathComponent("EasyRSS/Sync", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }
    }

    var isICloudDriveAvailable: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let parentDir = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: parentDir.path)
    }

    private var isObserving = false

    override init() {
        super.init()
    }

    func startObserving(onChange: @escaping @Sendable () -> Void) {
        guard !isObserving else { return }
        self.onRemoteChangeHandler = onChange
        NSFileCoordinator.addFilePresenter(self)
        isObserving = true
    }

    func stopObserving() {
        guard isObserving else { return }
        NSFileCoordinator.removeFilePresenter(self)
        self.onRemoteChangeHandler = nil
        isObserving = false
    }

    // MARK: - NSFilePresenter Callbacks

    func presentedSubitemDidChange(at url: URL) {
        // Fast-path ignore hidden/temporary files
        guard !url.lastPathComponent.hasPrefix(".") else { return }
        
        // Prioritize downloading if cloud placeholder
        forceDownloadIfNeeded(url: url)

        onRemoteChangeHandler?()
    }

    private func forceDownloadIfNeeded(url: URL) {
        // If file is not yet downloaded locally, force high-priority download
        if FileManager.default.isUbiquitousItem(at: url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    // MARK: - High-Performance Coordinated File Operations

    func saveManifest(_ manifest: SyncManifest) {
        let fileURL = syncDirectoryURL.appendingPathComponent("sync_manifest.json")
        saveCoordinated(data: manifest, to: fileURL)
    }

    func loadManifest() -> SyncManifest? {
        let fileURL = syncDirectoryURL.appendingPathComponent("sync_manifest.json")
        return loadCoordinated(from: fileURL, type: SyncManifest.self)
    }

    func saveStates(_ states: SyncStates) {
        let fileURL = syncDirectoryURL.appendingPathComponent("sync_states.json")
        saveCoordinated(data: states, to: fileURL)
    }

    func loadStates() -> SyncStates? {
        let fileURL = syncDirectoryURL.appendingPathComponent("sync_states.json")
        return loadCoordinated(from: fileURL, type: SyncStates.self)
    }

    func saveSettings(_ settings: SyncSettings) {
        let fileURL = syncDirectoryURL.appendingPathComponent("sync_settings.json")
        saveCoordinated(data: settings, to: fileURL)
    }

    func loadSettings() -> SyncSettings? {
        let fileURL = syncDirectoryURL.appendingPathComponent("sync_settings.json")
        return loadCoordinated(from: fileURL, type: SyncSettings.self)
    }

    // MARK: - Low-Level Helpers (Autoreleasepool Memory Containment)

    private func saveCoordinated<T: Encodable>(data: T, to fileURL: URL) {
        autoreleasepool {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                let rawData = try encoder.encode(data)

                let coordinator = NSFileCoordinator(filePresenter: self)
                var coordinatorError: NSError?
                coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { targetURL in
                    try? rawData.write(to: targetURL, options: .atomic)
                }
            } catch {
                let msg = "Failed to encode sync file: \(fileURL.lastPathComponent) (\(error.localizedDescription))"
                Task { @MainActor in
                    AppLogger.shared.log(msg, level: .error, category: .storage)
                }
            }
        }
    }

    private func loadCoordinated<T: Decodable>(from fileURL: URL, type: T.Type) -> T? {
        forceDownloadIfNeeded(url: fileURL)

        return autoreleasepool {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

            var result: T?
            let coordinator = NSFileCoordinator(filePresenter: self)
            var coordinatorError: NSError?

            coordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &coordinatorError) { targetURL in
                do {
                    let rawData = try Data(contentsOf: targetURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    result = try decoder.decode(type, from: rawData)
                } catch {
                    let warnMsg = "Corrupt or incomplete sync file \(targetURL.lastPathComponent), ignoring: \(error.localizedDescription)"
                    Task { @MainActor in
                        AppLogger.shared.log(warnMsg, level: .warning, category: .storage)
                    }
                }
            }
            return result
        }
    }
}
