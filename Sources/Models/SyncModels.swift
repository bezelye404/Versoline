import Foundation

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

struct SyncFeed: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    let url: String
    var folderId: UUID?
    var isPinned: Bool?
    var updatedAt: Date
}

/// A durable "this was deleted" marker so a deletion reaches devices that were offline.
/// Feeds are identified by their lower-cased URL (the same feed can have different ids on two Macs),
/// folders by their id. Records older than `SyncMerge.tombstoneLifetime` are dropped.
struct Tombstone: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case feed, folder }

    let kind: Kind
    let key: String
    let deletedAt: Date

    struct Key: Hashable, Sendable {
        let kind: Kind
        let key: String
    }

    static func feed(url: String, at date: Date) -> Tombstone {
        Tombstone(kind: .feed, key: url.lowercased(), deletedAt: date)
    }

    static func folder(id: UUID, at date: Date) -> Tombstone {
        Tombstone(kind: .folder, key: id.uuidString, deletedAt: date)
    }
}

struct SyncFolder: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var updatedAt: Date
}

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

/// Live changes and snapshots exchanged with an authenticated, paired device.
/// Snapshots are split into small chunks (`SyncEventValidator` caps every list) so a single message
/// stays well below MultipeerConnectivity's practical size limits.
enum SyncPeerEvent: Codable, Sendable, Equatable {
    case readArticles(hashes: [UInt64])
    case bookmarkToggled(link: String, isBookmarked: Bool)
    case feedAddedOrUpdated(feed: SyncFeed)
    /// Feeds are identified by URL because ids differ between Macs.
    case feedDeleted(url: String, deletedAt: Date)
    case folderUpdated(folder: SyncFolder)
    case folderDeleted(id: UUID, deletedAt: Date)
    case feedSnapshot(feeds: [SyncFeed], folders: [SyncFolder])
    case tombstoneSnapshot(tombstones: [Tombstone])
    case bookmarkSnapshot(links: [String])
    case settings(SyncSettings)
}

/// What actually travels over the wire.
enum SyncWireMessage: Codable, Sendable, Equatable {
    case handshake(HandshakeMessage)
    case event(SyncPeerEvent)
}

/// Defence in depth: even events from a paired device are range-checked before they touch the library.
enum SyncEventValidator {
    static let maxHashes = 5_000
    static let maxFeeds = 200
    static let maxFolders = 500
    static let maxLinks = 500
    static let maxTombstones = 500
    static let maxURLLength = 2_048
    static let maxTextLength = 500

    static func isAcceptable(_ event: SyncPeerEvent) -> Bool {
        switch event {
        case .readArticles(let hashes):
            return hashes.count <= maxHashes
        case .bookmarkToggled(let link, _):
            return isAcceptableLink(link)
        case .feedAddedOrUpdated(let feed):
            return isAcceptable(feed)
        case .feedDeleted(let url, _):
            return url.count <= maxURLLength
        case .folderUpdated(let folder):
            return folder.name.count <= maxTextLength
        case .folderDeleted:
            return true
        case .tombstoneSnapshot(let tombstones):
            return tombstones.count <= maxTombstones && tombstones.allSatisfy { $0.key.count <= maxURLLength }
        case .feedSnapshot(let feeds, let folders):
            return feeds.count <= maxFeeds && folders.count <= maxFolders
                && feeds.allSatisfy(isAcceptable) && folders.allSatisfy { $0.name.count <= maxTextLength }
        case .bookmarkSnapshot(let links):
            return links.count <= maxLinks && links.allSatisfy(isAcceptableLink)
        case .settings(let settings):
            return (settings.mutedKeywords?.count ?? 0) <= 10_000
        }
    }

    /// Feeds are fetched by the app, so only plain web URLs are allowed.
    static func isAcceptable(_ feed: SyncFeed) -> Bool {
        guard feed.url.count <= maxURLLength, feed.title.count <= maxTextLength,
              let url = URL(string: feed.url), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return false }
        return true
    }

    private static func isAcceptableLink(_ link: String) -> Bool {
        link.count <= 4_096
    }
}
