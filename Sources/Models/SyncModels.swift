import Foundation

// MARK: - 64-bit Stable FNV-1a Hash for URLs & Links (Minimal Memory)

extension String {
    /// Produces a deterministic 64-bit FNV-1a hash for URL strings.
    /// This allows storing tens of thousands of read article states in memory
    /// using only 8 bytes per item instead of storing full URL strings.
    var syncHash64: UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

// MARK: - Sync Feed Model

struct SyncFeed: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    let url: String
    var folderId: UUID?
    var isPinned: Bool?
    var updatedAt: Date
    var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }
}

// MARK: - Sync Folder Model

struct SyncFolder: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var updatedAt: Date
    var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }
}

// MARK: - Sync Manifest (Feeds & Folders)

struct SyncManifest: Codable, Equatable, Sendable {
    var version: Int = 1
    var deviceId: String
    var updatedAt: Date
    var feeds: [SyncFeed]
    var folders: [SyncFolder]
}

// MARK: - Sync States (Read States & Bookmarks)

struct SyncStates: Codable, Equatable, Sendable {
    var version: Int = 1
    var deviceId: String
    var updatedAt: Date
    /// Compact list of 64-bit hashes for read articles (kept for last 30 days)
    var readItemHashes: [UInt64]
    /// Bookmarked article links (full URLs to guarantee zero collision)
    var bookmarkedLinks: [String]
}

// MARK: - Sync Settings (User Preferences)

struct SyncSettings: Codable, Equatable, Sendable {
    var version: Int = 1
    var deviceId: String
    var updatedAt: Date
    var appColorPalette: String?
    var isCompactListMode: Bool?
    var showFavicons: Bool?
    var showReadingTimeStreams: Bool?
    var preferredExternalBrowser: String?
}

// MARK: - Peer-to-Peer Micro Payload (Multipeer Packet)

enum SyncPeerEvent: Codable, Sendable {
    case readArticles(hashes: [UInt64])
    case bookmarkToggled(link: String, isBookmarked: Bool)
    case feedAddedOrUpdated(feed: SyncFeed)
    case feedDeleted(id: UUID, deletedAt: Date)
    case requestFullSync
}
