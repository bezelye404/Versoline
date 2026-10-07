import AppKit
import Foundation
import WidgetKit

/// "Reset Permissions & Access": switches off everything optional that reaches outside the app's own data, and
/// forgets the Macs paired for sync. What macOS itself remembers about the app (for example local network access) can
/// only be cleared from outside the sandbox, so the settings offer the command and the Privacy & Security pane for that.
@MainActor
enum PermissionsReset {

    /// The optional integrations that are on or off by the user's choice.
    static let integrationKeys = [
        AppSettingsKeys.showDockBadge,
        AppSettingsKeys.spotlightBookmarks,
        AppSettingsKeys.showMenuBarIcon,
        AppSettingsKeys.shareWithWidget,
    ]

    static func turnOffIntegrations(in defaults: UserDefaults = .standard) {
        for key in integrationKeys { defaults.set(false, forKey: key) }
    }

    static func run(store: FeedStore, defaults: UserDefaults = .standard) {
        turnOffIntegrations(in: defaults)
        DockBadge.update(unreadCount: 0, enabled: false)
        store.spotlightSettingChanged(isOn: false)

        let sync = SyncCoordinator.shared
        sync.setEnabled(false)
        for peer in sync.trustedPeers { sync.removeTrustedPeer(peer) }

        if WidgetSnapshot.remove() { WidgetCenter.shared.reloadAllTimelines() }
        AppLogger.shared.log("Permissions and access reset: integrations off, widget data removed, paired Macs forgotten", level: .info, category: .storage)
    }

    /// The Terminal command that clears what macOS remembers about this app (Local Network and the like).
    static var systemResetCommand: String {
        "tccutil reset All \(Bundle.main.bundleIdentifier ?? "com.bezelye.Versoline")"
    }

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")

    static func copySystemResetCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(systemResetCommand, forType: .string)
    }

    static func openPrivacySettings() {
        if let url = privacySettingsURL { NSWorkspace.shared.open(url) }
    }
}
