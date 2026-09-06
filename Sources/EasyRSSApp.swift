import SwiftUI
import AppKit

@main
struct EasyRSSApp: App {

    @State private var store = FeedStore()
    @AppStorage(AppSettingsKeys.showMenuBarIcon) private var showMenuBarIcon = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            SidebarCommands()
        }

        Settings {
            SettingsView()
                .environment(store)
        }

        MenuBarExtra("easyRSS", systemImage: "newspaper", isInserted: $showMenuBarIcon) {
            let unread = store.totalUnreadCount()
            Text("easyRSS")
                .font(.headline)
            Text(unread == 1 ? "1 unread article" : "\(unread) unread articles")
                .font(.caption)

            Divider()

            Button("Open easyRSS") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Button("Refresh Feeds") {
                Task {
                    await store.refreshAllFeeds()
                }
            }

            Divider()

            Button("Quit easyRSS") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
