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

    // Appearance & Typography
    var appColorPalette: String?
    var readerTheme: String?
    var readerFontFamily: String?
    var readerFontSize: Double?
    var readerLineHeight: String?

    // Reader & Browser
    var isCompactListMode: Bool?
    var showFavicons: Bool?
    var showMenuBarIcon: Bool?
    var autoReaderMode: Bool?
    var isBionicReadingEnabled: Bool?
    var defaultReadingMode: String?
    var showReadingTimeStreams: Bool?
    var offlinePrecacheEnabled: Bool?
    var isContentBlockerEnabled: Bool?
    var preferredExternalBrowser: String?

    // Shortcuts & Rules
    var enableSingleKeyShortcuts: Bool?
    var autoCleanupDays: Int?
    var mutedKeywords: String?

    /// Reads current settings from UserDefaults.
    static func current() -> SyncSettings {
        let defaults = UserDefaults.standard
        let fontSizeNum = defaults.object(forKey: AppSettingsKeys.readerFontSize) as? NSNumber
        let cleanupNum = defaults.object(forKey: AppSettingsKeys.autoCleanupDays) as? NSNumber

        return SyncSettings(
            version: 1,
            deviceId: Host.current().localizedName ?? "Mac",
            updatedAt: Date(),
            appColorPalette: defaults.string(forKey: AppSettingsKeys.appColorPalette),
            readerTheme: defaults.string(forKey: AppSettingsKeys.readerTheme),
            readerFontFamily: defaults.string(forKey: AppSettingsKeys.readerFontFamily),
            readerFontSize: fontSizeNum?.doubleValue,
            readerLineHeight: defaults.string(forKey: AppSettingsKeys.readerLineHeight),
            isCompactListMode: defaults.object(forKey: AppSettingsKeys.isCompactListMode) as? Bool,
            showFavicons: defaults.object(forKey: AppSettingsKeys.showFavicons) as? Bool,
            showMenuBarIcon: defaults.object(forKey: AppSettingsKeys.showMenuBarIcon) as? Bool,
            autoReaderMode: defaults.object(forKey: AppSettingsKeys.autoReaderMode) as? Bool,
            isBionicReadingEnabled: defaults.object(forKey: AppSettingsKeys.isBionicReadingEnabled) as? Bool,
            defaultReadingMode: defaults.string(forKey: AppSettingsKeys.defaultReadingMode),
            showReadingTimeStreams: defaults.object(forKey: AppSettingsKeys.showReadingTimeStreams) as? Bool,
            offlinePrecacheEnabled: defaults.object(forKey: AppSettingsKeys.offlinePrecacheEnabled) as? Bool,
            isContentBlockerEnabled: defaults.object(forKey: AppSettingsKeys.isContentBlockerEnabled) as? Bool,
            preferredExternalBrowser: defaults.string(forKey: AppSettingsKeys.preferredExternalBrowser),
            enableSingleKeyShortcuts: defaults.object(forKey: AppSettingsKeys.enableSingleKeyShortcuts) as? Bool,
            autoCleanupDays: cleanupNum?.intValue,
            mutedKeywords: defaults.string(forKey: AppSettingsKeys.mutedKeywords)
        )
    }

    /// Applies non-nil values to UserDefaults.
    func applyToUserDefaults() {
        let defaults = UserDefaults.standard
        if let appColorPalette { defaults.set(appColorPalette, forKey: AppSettingsKeys.appColorPalette) }
        if let readerTheme { defaults.set(readerTheme, forKey: AppSettingsKeys.readerTheme) }
        if let readerFontFamily { defaults.set(readerFontFamily, forKey: AppSettingsKeys.readerFontFamily) }
        if let readerFontSize { defaults.set(readerFontSize, forKey: AppSettingsKeys.readerFontSize) }
        if let readerLineHeight { defaults.set(readerLineHeight, forKey: AppSettingsKeys.readerLineHeight) }
        if let isCompactListMode { defaults.set(isCompactListMode, forKey: AppSettingsKeys.isCompactListMode) }
        if let showFavicons { defaults.set(showFavicons, forKey: AppSettingsKeys.showFavicons) }
        if let showMenuBarIcon { defaults.set(showMenuBarIcon, forKey: AppSettingsKeys.showMenuBarIcon) }
        if let autoReaderMode { defaults.set(autoReaderMode, forKey: AppSettingsKeys.autoReaderMode) }
        if let isBionicReadingEnabled { defaults.set(isBionicReadingEnabled, forKey: AppSettingsKeys.isBionicReadingEnabled) }
        if let defaultReadingMode { defaults.set(defaultReadingMode, forKey: AppSettingsKeys.defaultReadingMode) }
        if let showReadingTimeStreams { defaults.set(showReadingTimeStreams, forKey: AppSettingsKeys.showReadingTimeStreams) }
        if let offlinePrecacheEnabled { defaults.set(offlinePrecacheEnabled, forKey: AppSettingsKeys.offlinePrecacheEnabled) }
        if let isContentBlockerEnabled { defaults.set(isContentBlockerEnabled, forKey: AppSettingsKeys.isContentBlockerEnabled) }
        if let preferredExternalBrowser { defaults.set(preferredExternalBrowser, forKey: AppSettingsKeys.preferredExternalBrowser) }
        if let enableSingleKeyShortcuts { defaults.set(enableSingleKeyShortcuts, forKey: AppSettingsKeys.enableSingleKeyShortcuts) }
        if let autoCleanupDays { defaults.set(autoCleanupDays, forKey: AppSettingsKeys.autoCleanupDays) }
        if let mutedKeywords { defaults.set(mutedKeywords, forKey: AppSettingsKeys.mutedKeywords) }
    }

    /// Determines if preferences differ, ignoring metadata (deviceId, updatedAt, version).
    func hasSamePreferences(as other: SyncSettings) -> Bool {
        return appColorPalette == other.appColorPalette &&
            readerTheme == other.readerTheme &&
            readerFontFamily == other.readerFontFamily &&
            readerFontSize == other.readerFontSize &&
            readerLineHeight == other.readerLineHeight &&
            isCompactListMode == other.isCompactListMode &&
            showFavicons == other.showFavicons &&
            showMenuBarIcon == other.showMenuBarIcon &&
            autoReaderMode == other.autoReaderMode &&
            isBionicReadingEnabled == other.isBionicReadingEnabled &&
            defaultReadingMode == other.defaultReadingMode &&
            showReadingTimeStreams == other.showReadingTimeStreams &&
            offlinePrecacheEnabled == other.offlinePrecacheEnabled &&
            isContentBlockerEnabled == other.isContentBlockerEnabled &&
            preferredExternalBrowser == other.preferredExternalBrowser &&
            enableSingleKeyShortcuts == other.enableSingleKeyShortcuts &&
            autoCleanupDays == other.autoCleanupDays &&
            mutedKeywords == other.mutedKeywords
    }
}

// MARK: - Peer-to-Peer Micro Payload (Multipeer Packet)

enum SyncPeerEvent: Codable, Sendable {
    case readArticles(hashes: [UInt64])
    case bookmarkToggled(link: String, isBookmarked: Bool)
    case feedAddedOrUpdated(feed: SyncFeed)
    case feedDeleted(id: UUID, deletedAt: Date)
    case requestFullSync
}
