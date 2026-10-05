import AppKit

/// The unread count on the Dock icon (Settings > General, off by default). Shown only while the setting is on; it
/// costs one string per change of the count and nothing runs in the background.
enum DockBadge {

    /// What the badge says: nothing for zero, the number up to 999, "999+" beyond.
    static func label(forUnreadCount count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 999 ? "999+" : String(count)
    }

    @MainActor
    static func update(unreadCount: Int, enabled: Bool) {
        NSApp?.dockTile.badgeLabel = enabled ? label(forUnreadCount: unreadCount) : nil
    }
}
