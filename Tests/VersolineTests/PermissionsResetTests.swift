import Testing
import Foundation
@testable import Versoline

@MainActor
struct PermissionsResetTests {

    @Test func integrationsAreSwitchedOff() {
        let name = "PermissionsResetTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        for key in PermissionsReset.integrationKeys { defaults.set(true, forKey: key) }
        defaults.set("kept", forKey: AppSettingsKeys.mutedKeywords)

        PermissionsReset.turnOffIntegrations(in: defaults)

        for key in PermissionsReset.integrationKeys { #expect(defaults.bool(forKey: key) == false, "\(key)") }
        #expect(defaults.string(forKey: AppSettingsKeys.mutedKeywords) == "kept")   // other settings are left alone
    }

    @Test func theListCoversTheOptionalIntegrations() {
        let keys = Set(PermissionsReset.integrationKeys)
        #expect(keys == [AppSettingsKeys.showDockBadge, AppSettingsKeys.spotlightBookmarks, AppSettingsKeys.showMenuBarIcon, AppSettingsKeys.shareWithWidget])
    }

    @Test func widgetFileIsRemovedAndRemovalIsIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PermissionsResetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = WidgetSnapshot(generatedAt: Date(), unreadCount: 3, headlines: [])
        #expect(snapshot.write(directory: directory) == true)
        #expect(WidgetSnapshot.load(directory: directory) != nil)

        #expect(WidgetSnapshot.remove(directory: directory) == true)
        #expect(WidgetSnapshot.load(directory: directory) == nil)
        #expect(WidgetSnapshot.remove(directory: directory) == false)
    }

    @Test func systemResetCommandNamesTheApp() {
        #expect(PermissionsReset.systemResetCommand.hasPrefix("tccutil reset All com.bezelye.Versoline"))
        #expect(PermissionsReset.privacySettingsURL?.scheme == "x-apple.systempreferences")
    }
}
