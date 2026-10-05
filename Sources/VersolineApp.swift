import SwiftUI
import AppKit
import WebKit

@main
struct VersolineApp: App {

    /// `xcodebuild test` launches the app as the test host. Keep that launch away from the
    /// user's real library by pointing the store at a throwaway directory.
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    @State private var store = FeedStore(
        storageDirectory: Self.isRunningTests
            ? FileManager.default.temporaryDirectory.appendingPathComponent("VersolineTestHost-\(UUID().uuidString)", isDirectory: true)
            : (Benchmark.isRequested ? Benchmark.scratchLibrary() : nil)
    )
    @AppStorage(AppSettingsKeys.showMenuBarIcon) private var showMenuBarIcon = false

    init() {
        // Run one-time non-destructive legacy data migration if needed
        if !Self.isRunningTests {
            LegacyMigration.runMigration()
        }

        // Keep the shared URL cache small: 2 MB in memory, 25 MB on disk.
        URLCache.shared = URLCache(
            memoryCapacity: 2 * 1024 * 1024,
            diskCapacity: 25 * 1024 * 1024
        )

        Self.setupMemoryPressureMonitor()

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AnnotationStore.shared.flush() }
        }

        if !Self.isRunningTests {
            Task { @MainActor in
                await ContentBlockerService.shared.prepare()
                ReaderModeExtractor.shared.cleanupDiskCache(olderThanDays: 30)
                ImageDownsampleCache.shared.cleanupDiskCache(olderThanDays: 14)
                ImageDownsampleCache.shared.enforceQuota(maxSizeBytes: Int64(MemoryLimits.imageDiskBytes))
            }
        }

        // Give memory back when the app goes to the background or is hidden.
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

    private static var memoryPressureSource: (any DispatchSourceMemoryPressure)?

    private static func setupMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                Self.purgeTransientMemory()
                NotificationCenter.default.post(name: Notification.Name("VersolineDeepCompactMemory"), object: nil)
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    @MainActor
    private static func purgeTransientMemory() {
        // The benchmark runs without anyone watching, so the app often loses focus; that must not change the numbers.
        guard !Benchmark.isRequested else { return }
        ImageDownsampleCache.shared.clearMemory()
        FaviconService.shared.clearMemoryCache()
        ReaderModeExtractor.shared.clearMemoryCache()
        CuratedFeedManager.shared.clearMemory()
        PodcastSearchService.shared.clearCache()
        URLCache.shared.removeAllCachedResponses()
        URLSession.shared.flush(completionHandler: {})
        WebView.flushMemoryCache()
        if !VideoPlayerService.shared.isPlaying && VideoPlayerService.shared.webView != nil {
            VideoPlayerService.shared.close()
        }
        MemoryRelief.trim()
        NotificationCenter.default.post(name: Notification.Name("VersolineCompactMemory"), object: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1100, height: 700)
        // A feed link or an OPML file opened from another app goes to the window that is already there.
        .handlesExternalEvents(matching: ["*"])
        .commands {
            SidebarCommands()
            AppCommands()
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
            Text("Versoline")
                .font(.headline)
            Text(unread == 1 ? "1 unread article" : "\(unread) unread articles")
                .font(.caption)

            Divider()

            let recentUnread = Array(store.unreadItems().prefix(5))
            if !recentUnread.isEmpty {
                Text("Recent Unread")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(recentUnread) { item in
                    Button(item.title) {
                        NSApp.activate(ignoringOtherApps: true)
                        if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                }
                Divider()
            }

            Button("Open Versoline") {
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

            Button("Quit Versoline") {
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

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppColorPalette = .slate
}

extension EnvironmentValues {
    var appTheme: AppColorPalette {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

enum AppTheme {

    enum Colors {
        private static var currentPalette: AppColorPalette {
            let raw = UserDefaults.standard.string(forKey: AppSettingsKeys.appColorPalette) ?? AppColorPalette.slate.rawValue
            return AppColorPalette(rawValue: raw) ?? .slate
        }

        /// Main accent of the selected palette.
        static var accent: Color { currentPalette.accentColor }

        /// Unread dot.
        static var unreadDot: Color { currentPalette.unreadDotColor }

        /// Bookmark star.
        static var bookmark: Color { currentPalette.bookmarkColor }

        /// Offline and warning states.
        static var warning: Color { currentPalette.warningColor }

        /// Downloads and success.
        static var success: Color { currentPalette.successColor }

        /// YouTube marker.
        static var youtube: Color { currentPalette.youtubeColor }

        /// Podcast marker.
        static var podcast: Color { currentPalette.podcastColor }

        /// Card background on hover.
        static var cardHover: Color { currentPalette.cardHover }

        /// Selected card background.
        static var cardSelected: Color { currentPalette.cardSelected }

        /// Selected card border.
        static var cardSelectedBorder: Color { currentPalette.cardSelectedBorder }

        /// Hairline borders.
        static var hairlineBorder: Color { currentPalette.hairlineBorder }
        static var subtleBorder: Color { currentPalette.hairlineBorder }

        /// Pills and counters.
        static var badgeBackground: Color { currentPalette.badgeBackground }
        static var badgeText: Color { currentPalette.badgeText }

        /// Counter of the active row.
        static var activeBadgeBackground: Color { currentPalette.activeBadgeBackground }
        static var activeBadgeText: Color { currentPalette.activeBadgeText }
    }

    enum Metrics {
        static let cardCornerRadius: CGFloat = 9
        static let pillCornerRadius: CGFloat = 20
        static let thumbnailCornerRadius: CGFloat = 7
        static let floatingBarCornerRadius: CGFloat = 22
    }
}

enum AppHaptics {
    /// Light tap for marking read, starring and switching tabs.
    @MainActor
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
    }

    /// Selection change.
    @MainActor
    static func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
    }

    /// Confirmation of a finished action.
    @MainActor
    static func notifySuccess() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
    }

    /// General notification.
    @MainActor
    static func notification() {
        notifySuccess()
    }
}

@MainActor
enum AppAnimation {
    // Every token below resolves to `reduced` when macOS "Reduce Motion" is on (Apple HIG: replace
    // springs and bounces with a short fade). Call sites need no extra handling; use `safe(_:)`
    // for one-off animations that are not one of these tokens.

    /// List updates and segmented controls.
    static var snappy: Animation { safe(.snappy(duration: 0.22, extraBounce: 0.05)) }

    /// Starring, the read icon and counters.
    static var bouncy: Animation { safe(.bouncy(duration: 0.24, extraBounce: 0.10)) }

    /// The reading mode switch and selection capsule.
    static var slidingPill: Animation { safe(.spring(response: 0.26, dampingFraction: 0.78)) }

    /// Buttons and selection while dragging.
    static var interactiveSpring: Animation { safe(.interactiveSpring(response: 0.22, dampingFraction: 0.80)) }

    /// Pressing a card.
    static var cardPress: Animation { safe(.interactiveSpring(response: 0.15, dampingFraction: 0.75)) }

    /// Pages and sheets appearing.
    static var pageReveal: Animation { safe(.spring(response: 0.26, dampingFraction: 0.85)) }

    /// Switching between articles; no bounce.
    static var articleTransition: Animation { safe(.spring(response: 0.20, dampingFraction: 0.90)) }

    /// Folders expanding.
    static var accordion: Animation { safe(.spring(response: 0.24, dampingFraction: 0.82)) }

    /// Hover changes.
    static var hover: Animation { safe(.easeInOut(duration: 0.12)) }

    /// Quick state changes.
    static var quickFeedback: Animation { safe(.easeOut(duration: 0.14)) }

    /// The short fade used when Reduce Motion is on.
    static let reduced = Animation.easeInOut(duration: 0.14)

    /// The animation itself, or the short fade when Reduce Motion is on.
    static func motion(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// Follows the system Reduce Motion setting; for one-off animations that are not a token above:
    /// `withAnimation(AppAnimation.safe(.spring(...)))`.
    static func safe(_ animation: Animation) -> Animation {
        motion(animation, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// Delay for rows appearing one after another, at most 0.15 s.
    static func stagger(index: Int) -> Double {
        min(Double(index) * 0.015, 0.15)
    }
}
