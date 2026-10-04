import SwiftUI
import AppKit
import WebKit

struct SettingsView: View {

    private enum SettingsTab: Hashable {
        case general
        case reader
        case shortcuts
        case filters
        case sync
        case storage
        case health
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

            ShortcutsSettingsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(SettingsTab.shortcuts)

            FiltersSettingsTab()
                .tabItem {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .tag(SettingsTab.filters)

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

            FeedHealthSettingsTab()
                .tabItem {
                    Label("Feed Health", systemImage: "heart.text.square")
                }
                .tag(SettingsTab.health)
        }
        .frame(width: 580, height: 510)
    }
}

// MARK: - 1. General Tab
