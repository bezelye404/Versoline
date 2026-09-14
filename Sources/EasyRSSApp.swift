import SwiftUI
import AppKit
import WebKit

@main
struct EasyRSSApp: App {

    @State private var store = FeedStore()
    @AppStorage(AppSettingsKeys.showMenuBarIcon) private var showMenuBarIcon = false

    init() {
        // Memory optimization: Strict URLCache capacity limits (2MB RAM / 25MB Disk)
        URLCache.shared = URLCache(
            memoryCapacity: 2 * 1024 * 1024,
            diskCapacity: 25 * 1024 * 1024
        )

        Task { @MainActor in
            await ContentBlockerService.shared.prepare()
        }

        // Memory optimization: Purge transient RAM caches and flush network/WebKit memory when the app is minimized, hidden or backgrounded
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                Self.purgeTransientMemory()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                Self.purgeTransientMemory()
            }
        }
    }

    @MainActor
    private static func purgeTransientMemory() {
        FaviconService.shared.clearMemoryCache()
        ReaderModeExtractor.shared.clearMemoryCache()
        PodcastSearchService.shared.clearCache()
        URLCache.shared.removeAllCachedResponses()
        URLSession.shared.flush(completionHandler: {})
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeMemoryCache],
            modifiedSince: .distantPast,
            completionHandler: {}
        )
    }

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

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            let player = AudioPlayerService.shared
            if let episode = player.currentEpisode {
                Text("Now Playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2)

                Button(player.isPlaying ? "Pause Episode" : "Play Episode") {
                    player.togglePlayPause()
                }

                Button("Skip Forward 15s") {
                    player.seek(to: player.currentTime + 15)
                }

                Divider()
            }

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
        } label: {
            let player = AudioPlayerService.shared
            if player.isPlaying {
                Image(systemName: "headphones")
            } else {
                Image(systemName: "newspaper")
            }
        }
    }
}

// MARK: - App Animation Engine (Apple HIG Motion & GPU-Composited Guidelines)

enum AppAnimation {
    /// Crisp snappy spring for fast state changes and list entries (0.22s)
    static let snappy = Animation.snappy(duration: 0.22, extraBounce: 0.08)

    /// Tactile bouncy spring for micro-interactions: stars, bookmarks, checks, unread bubble pop (0.26s)
    static let bouncy = Animation.bouncy(duration: 0.26, extraBounce: 0.15)

    /// Fluid sliding spring for matchedGeometry capsules, sliding pills, and segment switches (0.28s)
    static let slidingPill = Animation.spring(response: 0.28, dampingFraction: 0.76)

    /// Snappy card press response when tapping or clicking rows (0.16s)
    static let cardPress = Animation.interactiveSpring(response: 0.16, dampingFraction: 0.72)

    /// Smooth page reveal spring when switching articles or opening detail panes (0.28s)
    static let pageReveal = Animation.spring(response: 0.28, dampingFraction: 0.84)

    /// Gentle accordion expansion for folders and dropdowns (0.26s)
    static let accordion = Animation.spring(response: 0.26, dampingFraction: 0.82)

    /// Subtle hover transition (0.15s)
    static let hover = Animation.easeInOut(duration: 0.15)

    /// Quick easeOut for read/unread state changes (0.15s per guide.md)
    static let quickFeedback = Animation.easeOut(duration: 0.15)

    /// Fallback animation when accessibilityReduceMotion is enabled
    static let reduced = Animation.easeInOut(duration: 0.15)

    /// Returns the appropriate animation respecting accessibilityReduceMotion
    static func motion(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// Calculate staggered delay for cascading list animations (capped at 0.18s max delay)
    static func stagger(index: Int) -> Double {
        min(Double(index) * 0.02, 0.18)
    }
}
