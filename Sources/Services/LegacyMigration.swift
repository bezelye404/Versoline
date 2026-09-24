import Foundation
import SwiftUI

// MARK: - Legacy Data Migration (easyRSS -> Versoline)
/// Handles one-time, non-destructive migration of persisted user data (subscriptions, articles,
/// downloaded podcast episodes, and cached favicons) from the legacy easyRSS application storage
/// (`~/Library/Application Support/EasyRSS`) to the new Versoline directory
/// (`~/Library/Application Support/Versoline`).
///
/// Note: References to "EasyRSS" in this file are intentional and preserved for migration compatibility.
public enum LegacyMigrationResult: Equatable, Sendable {
    case notNeeded
    case alreadyCompleted
    case success(migratedFilesCount: Int)
    case failure(String)
}

@MainActor
@Observable
public final class LegacyMigration {

    public static let shared = LegacyMigration()

    // MARK: - Constants
    public static let legacyDirName = "EasyRSS"
    public static let newDirName = "Versoline"
    public static let markerFileName = ".migrated-from-easyrss"

    private static let migrationNoticeShownKey = "Versoline_MigrationNoticeDismissed"
    private static let didMigrateKey = "Versoline_DidMigrateFromEasyRSS"

    public var showImportNotification: Bool = false

    private init() {
        let dismissed = UserDefaults.standard.bool(forKey: Self.migrationNoticeShownKey)
        let didMigrate = UserDefaults.standard.bool(forKey: Self.didMigrateKey)
        self.showImportNotification = didMigrate && !dismissed
    }

    public func dismissNotification() {
        self.showImportNotification = false
        UserDefaults.standard.set(true, forKey: Self.migrationNoticeShownKey)
    }

    // MARK: - Migration Execution
    @discardableResult
    public static func runMigration(
        fileManager: FileManager = .default,
        customAppSupportURL: URL? = nil
    ) -> LegacyMigrationResult {
        let baseAppSupportURL: URL
        if let customAppSupportURL {
            baseAppSupportURL = customAppSupportURL
        } else {
            guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return .failure("Unable to locate Application Support directory")
            }
            baseAppSupportURL = appSupport
        }

        let legacyURL = baseAppSupportURL.appendingPathComponent(legacyDirName, isDirectory: true)
        let newURL = baseAppSupportURL.appendingPathComponent(newDirName, isDirectory: true)
        let markerURL = newURL.appendingPathComponent(markerFileName, isDirectory: false)

        // 1. If marker exists, migration was already completed safely.
        if fileManager.fileExists(atPath: markerURL.path) {
            return .alreadyCompleted
        }

        let legacyExists = fileManager.fileExists(atPath: legacyURL.path)
        let newExists = fileManager.fileExists(atPath: newURL.path)

        // 2. If new exists without marker and legacy exists, this indicates an interrupted/partial copy.
        // Clean up partial target before re-copying.
        if newExists && !fileManager.fileExists(atPath: markerURL.path) && legacyExists {
            do {
                try fileManager.removeItem(at: newURL)
            } catch {
                return .failure("Failed to clean up incomplete target directory: \(error.localizedDescription)")
            }
        } else if newExists && !legacyExists {
            // New directory was created fresh, no legacy data to migrate.
            try? writeMarker(at: markerURL, fileManager: fileManager)
            return .notNeeded
        }

        // 3. If legacy directory does not exist, nothing to migrate.
        if !fileManager.fileExists(atPath: legacyURL.path) {
            return .notNeeded
        }

        // 4. Perform non-destructive copy (APFS clone-on-write) from legacy to new URL.
        do {
            try fileManager.copyItem(at: legacyURL, to: newURL)
            try writeMarker(at: markerURL, fileManager: fileManager)

            let count = (try? fileManager.contentsOfDirectory(atPath: newURL.path).count) ?? 0

            UserDefaults.standard.set(true, forKey: didMigrateKey)
            MainActor.assumeIsolated {
                LegacyMigration.shared.showImportNotification = true
            }

            return .success(migratedFilesCount: count)
        } catch {
            return .failure("Migration copy failed: \(error.localizedDescription)")
        }
    }

    private static func writeMarker(at markerURL: URL, fileManager: FileManager) throws {
        let content = "migratedAt=\(ISO8601DateFormatter().string(from: Date()))\nsource=\(legacyDirName)\ntarget=\(newDirName)\n"
        guard let data = content.data(using: .utf8) else { return }
        try data.write(to: markerURL, options: .atomic)
    }
}
