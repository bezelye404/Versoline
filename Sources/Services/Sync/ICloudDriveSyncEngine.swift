import Foundation
import AppKit

// MARK: - iCloud Drive Sync Engine (Turbo Coordinated File Storage)

final class ICloudDriveSyncEngine: NSObject, NSFilePresenter, @unchecked Sendable {

    var presentedItemURL: URL? { syncDirectoryURL }
    var presentedItemOperationQueue: OperationQueue { syncOperationQueue }

    private let syncOperationQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.bezelye.versoline.iCloudSyncQueue"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()

    private var onRemoteChangeHandler: (@Sendable (URL) -> Void)?

    /// Resolves real user home directory bypassing App Sandbox container redirection.
    private static var realHomeDirectoryURL: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Resolves the iCloud Drive Versoline directory path without requiring Apple Dev credentials.
    var syncDirectoryURL: URL {
        let realHome = Self.realHomeDirectoryURL
        let cloudDocsParent = realHome.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        let versolineCloudDocs = cloudDocsParent.appendingPathComponent("Versoline", isDirectory: true)

        // If iCloud Drive is available on macOS, use it; otherwise fallback to local sync sandbox
        if FileManager.default.fileExists(atPath: cloudDocsParent.path) {
            if !FileManager.default.fileExists(atPath: versolineCloudDocs.path) {
                try? FileManager.default.createDirectory(at: versolineCloudDocs, withIntermediateDirectories: true)
            }
            return versolineCloudDocs
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let fallback = appSupport.appendingPathComponent("Versoline/Sync", isDirectory: true)
            if !FileManager.default.fileExists(atPath: fallback.path) {
                try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            }
            return fallback
        }
    }

    var isICloudDriveAvailable: Bool {
        let realHome = Self.realHomeDirectoryURL
        let cloudDocsParent = realHome.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: cloudDocsParent.path)
    }

    private var isObserving = false

    override init() {
        super.init()
    }

    func startObserving(onChange: @escaping @Sendable (URL) -> Void) {
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
        let filename = url.lastPathComponent

        // Handle .icloud placeholder files by initiating download
        if filename.hasSuffix(".icloud") {
            forceDownloadIfNeeded(url: url)
            return
        }

        // Fast-path ignore temporary or hidden dotfiles (except .icloud placeholders handled above)
        guard !filename.hasPrefix(".") else { return }

        // Prioritize downloading if cloud placeholder
        forceDownloadIfNeeded(url: url)

        onRemoteChangeHandler?(url)
    }

    private func forceDownloadIfNeeded(url: URL) {
        if FileManager.default.isUbiquitousItem(at: url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        } else if url.lastPathComponent.hasSuffix(".icloud") {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    // MARK: - High-Performance Coordinated File Operations (Delta-Checked)

    // 1. Manifest
    @discardableResult
    func saveManifestIfChanged(_ manifest: SyncManifest) -> Bool {
        let fileURL = syncDirectoryURL.appendingPathComponent("sync_manifest.json")
        if let existing = loadManifest() {
            if existing.feeds == manifest.feeds && existing.folders == manifest.folders {
                return false
            }
        }
        return saveCoordinated(data: manifest, to: fileURL)
    }

    func saveManifest(_ manifest: SyncManifest) {
        saveManifestIfChanged(manifest)
    }

    func loadManifest() -> SyncManifest? {
        let fileURL = syncDirectoryURL.appendingPathComponent("sync_manifest.json")
        return loadCoordinated(from: fileURL, type: SyncManifest.self)
    }

    // 2. States
    @discardableResult
    func saveStatesIfChanged(_ states: SyncStates) -> Bool {
        let fileURL = syncDirectoryURL.appendingPathComponent("sync_states.json")
        if let existing = loadStates() {
            if Set(existing.readItemHashes) == Set(states.readItemHashes) &&
                Set(existing.bookmarkedLinks) == Set(states.bookmarkedLinks) {
                return false
            }
        }
        return saveCoordinated(data: states, to: fileURL)
    }

    func saveStates(_ states: SyncStates) {
        saveStatesIfChanged(states)
    }

    func loadStates() -> SyncStates? {
        let fileURL = syncDirectoryURL.appendingPathComponent("sync_states.json")
        return loadCoordinated(from: fileURL, type: SyncStates.self)
    }

    // 3. User Settings
    @discardableResult
    func saveSettingsIfChanged(_ settings: SyncSettings) -> Bool {
        let fileURL = syncDirectoryURL.appendingPathComponent("sync_settings.json")
        if let existing = loadSettings(), existing.hasSamePreferences(as: settings) {
            return false
        }
        return saveCoordinated(data: settings, to: fileURL)
    }

    func saveSettings(_ settings: SyncSettings) {
        saveSettingsIfChanged(settings)
    }

    func loadSettings() -> SyncSettings? {
        let fileURL = syncDirectoryURL.appendingPathComponent("sync_settings.json")
        return loadCoordinated(from: fileURL, type: SyncSettings.self)
    }

    // 4. OPML Subscriptions
    @discardableResult
    func saveOPMLIfChanged(_ opmlContent: String) -> Bool {
        let fileURL = syncDirectoryURL.appendingPathComponent("subscriptions.opml")
        guard let rawData = opmlContent.data(using: .utf8) else { return false }
        return saveCoordinatedIfDifferent(data: rawData, to: fileURL)
    }

    func loadOPML() -> String? {
        let fileURL = syncDirectoryURL.appendingPathComponent("subscriptions.opml")
        guard let data = loadCoordinatedRaw(from: fileURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Low-Level Helpers (Autoreleasepool Memory Containment & Delta Diffing)

    private func saveCoordinatedIfDifferent(data rawData: Data, to fileURL: URL) -> Bool {
        autoreleasepool {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let existing = try? Data(contentsOf: fileURL), existing == rawData {
                    return false
                }
            }

            var wroteSuccessfully = false
            let coordinator = NSFileCoordinator(filePresenter: self)
            var coordinatorError: NSError?
            coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { targetURL in
                do {
                    try rawData.write(to: targetURL, options: .atomic)
                    wroteSuccessfully = true
                } catch {
                    let msg = "Failed to write sync file: \(targetURL.lastPathComponent) (\(error.localizedDescription))"
                    Task { @MainActor in
                        AppLogger.shared.log(msg, level: .error, category: .storage)
                    }
                }
            }
            return wroteSuccessfully
        }
    }

    private func saveCoordinated<T: Encodable>(data: T, to fileURL: URL) -> Bool {
        autoreleasepool {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                let rawData = try encoder.encode(data)
                return saveCoordinatedIfDifferent(data: rawData, to: fileURL)
            } catch {
                let msg = "Failed to encode sync file: \(fileURL.lastPathComponent) (\(error.localizedDescription))"
                Task { @MainActor in
                    AppLogger.shared.log(msg, level: .error, category: .storage)
                }
                return false
            }
        }
    }

    private func loadCoordinatedRaw(from fileURL: URL) -> Data? {
        forceDownloadIfNeeded(url: fileURL)

        return autoreleasepool {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

            var result: Data?
            let coordinator = NSFileCoordinator(filePresenter: self)
            var coordinatorError: NSError?

            coordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &coordinatorError) { targetURL in
                result = try? Data(contentsOf: targetURL)
            }
            return result
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
