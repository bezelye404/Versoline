import Foundation

/// One file with the whole library (subscriptions, folders, articles with their read and bookmark state, deletions
/// for sync) and the reading preferences, so a library can be kept safe or moved to another Mac without a cloud.
/// Article bodies are not included: they are fetched again when opened.
enum LibraryBackup {

    static let formatName = "versoline-backup"
    static let currentVersion = 1

    struct Envelope: Codable {
        var format: String = LibraryBackup.formatName
        var version: Int = LibraryBackup.currentVersion
        var createdAt: Date
        var appVersion: String
        var library: FeedStore.StorageData
        var settings: SyncSettings?
    }

    struct Summary: Equatable {
        let feeds: Int
        let articles: Int
        let createdAt: Date
    }

    enum BackupError: LocalizedError, Equatable {
        case notABackup
        case newerVersion(Int)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notABackup:
                return String(localized: "This file is not a Versoline backup.")
            case .newerVersion:
                return String(localized: "This backup was made by a newer version of Versoline. Update the app to restore it.")
            case .unreadable:
                return String(localized: "The backup file could not be read. It may be damaged.")
            }
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func make(library: FeedStore.StorageData, settings: SyncSettings? = nil, now: Date = Date()) throws -> Data {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return try encoder().encode(Envelope(createdAt: now, appVersion: version, library: library, settings: settings))
    }

    /// Checks the file's header before decoding the library, so a wrong or newer file gets a clear message.
    static func read(_ data: Data) throws -> Envelope {
        struct Header: Decodable { let format: String?; let version: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == formatName else {
            throw BackupError.notABackup
        }
        if let version = header.version, version > currentVersion { throw BackupError.newerVersion(version) }
        guard let envelope = try? decoder().decode(Envelope.self, from: data) else { throw BackupError.unreadable }
        return envelope
    }

    static func summary(of envelope: Envelope) -> Summary {
        Summary(feeds: envelope.library.feeds.count,
                articles: envelope.library.items.values.reduce(0) { $0 + $1.count },
                createdAt: envelope.createdAt)
    }
}
