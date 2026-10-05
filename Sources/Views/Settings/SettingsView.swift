import SwiftUI
import AppKit
import WebKit

struct SettingsView: View {

    @AppStorage(AppSettingsKeys.appColorPalette) private var appColorPaletteRaw = AppColorPalette.slate.rawValue

    private var palette: AppColorPalette {
        AppColorPalette(rawValue: appColorPaletteRaw) ?? .slate
    }

    private enum SettingsTab: Hashable {
        case general
        case reader
        case feeds
        case sync
        case storage
    }

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            ReaderSettingsTab()
                .tabItem {
                    Label("Reader", systemImage: "doc.text")
                }
                .tag(SettingsTab.reader)

            FeedsSettingsTab()
                .tabItem {
                    Label("Feeds", systemImage: "dot.radiowaves.up.forward")
                }
                .tag(SettingsTab.feeds)

            SyncSettingsTab()
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(SettingsTab.sync)

            StorageSettingsTab()
                .tabItem {
                    Label("Storage", systemImage: "internaldrive")
                }
                .tag(SettingsTab.storage)
        }
        // The settings window follows the app theme: same accent colour and appearance.
        .environment(\.appTheme, palette)
        .tint(palette.accentColor)
        .frame(width: 580, height: 510)
    }
}
