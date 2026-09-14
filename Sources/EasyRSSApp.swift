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

        Self.setupMemoryPressureMonitor()

        Task { @MainActor in
            await ContentBlockerService.shared.prepare()
            ReaderModeExtractor.shared.cleanupDiskCache(olderThanDays: 30)
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

    private static var memoryPressureSource: (any DispatchSourceMemoryPressure)?

    private static func setupMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                Self.purgeTransientMemory()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    @MainActor
    private static func purgeTransientMemory() {
        ImageDownsampleCache.shared.clearMemory()
        FaviconService.shared.clearMemoryCache()
        ReaderModeExtractor.shared.clearMemoryCache()
        PodcastSearchService.shared.clearCache()
        URLCache.shared.removeAllCachedResponses()
        URLSession.shared.flush(completionHandler: {})
        WebView.flushMemoryCache()
        if !VideoPlayerService.shared.isPlaying && VideoPlayerService.shared.webView != nil {
            VideoPlayerService.shared.close()
        }
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

// MARK: - App Design Theme Environment & Tokens

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

    // MARK: - Colors (Sade, doymamış renk paleti ve yüzeyler)
    enum Colors {
        private static var currentPalette: AppColorPalette {
            let raw = UserDefaults.standard.string(forKey: AppSettingsKeys.appColorPalette) ?? AppColorPalette.slate.rawValue
            return AppColorPalette(rawValue: raw) ?? .slate
        }

        /// Ana vurgu: Seçili sakin paletin doğal rengi
        static var accent: Color { currentPalette.accentColor }

        /// Okunmamış göstergesi: Zarif ve net bir nokta
        static var unreadDot: Color { currentPalette.unreadDotColor }

        /// Yıldız / Yerimi: Sıcak kehribar / altın tonu
        static var bookmark: Color { currentPalette.bookmarkColor }

        /// Çevrimdışı / İkaz durumu: Sakin sarı/kehribar
        static let warning = Color(nsColor: .systemYellow)

        /// İndirme / Başarılı durum: Doymamış, doğal yeşil
        static let success = Color(nsColor: .systemGreen).opacity(0.9)

        /// YouTube göstergesi: Doğal tuğla/koyu kırmızı
        static let youtube = Color(nsColor: .systemRed).opacity(0.85)

        /// Podcast mikro-etiket rengi: Nötr mor/indigo
        static let podcast = Color(nsColor: .systemIndigo).opacity(0.85)

        // MARK: Arka Plan ve Yüzeyler
        /// Kart hover arka planı: Çok hafif saydam kontrol dolgusu
        static let cardHover = Color.primary.opacity(0.04)

        /// Seçili kart arka planı
        static var cardSelected: Color { currentPalette.cardSelected }

        /// Seçili kart kenarlık çizgisi
        static var cardSelectedBorder: Color { currentPalette.cardSelectedBorder }

        /// Ultra ince sınır çizgileri (Hairline borders)
        static let hairlineBorder = Color.primary.opacity(0.08)
        static let subtleBorder = Color.primary.opacity(0.09)

        /// Hap ve sayaç dolguları
        static let badgeBackground = Color.primary.opacity(0.06)
        static let badgeText = Color.secondary

        /// Aktif sayaç rozeti dolgusu
        static var activeBadgeBackground: Color { accent.opacity(0.14) }
        static var activeBadgeText: Color { accent }
    }

    // MARK: - Radius & Spacing Tokens
    enum Metrics {
        static let cardCornerRadius: CGFloat = 9
        static let pillCornerRadius: CGFloat = 20
        static let thumbnailCornerRadius: CGFloat = 7
        static let floatingBarCornerRadius: CGFloat = 22
    }
}

// MARK: - Dokunsal Haptik Geri Bildirim (AppKit Haptics)

enum AppHaptics {
    /// Hafif seçim tıklaması (okundu, yıldız, sekme değiştirme)
    @MainActor
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
    }

    /// Seçim değişikliği bildirimi
    @MainActor
    static func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
    }

    /// Onay / İşlem tamamlandı tıklaması
    @MainActor
    static func notifySuccess() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
    }

    /// Genel bildirim tıklaması
    @MainActor
    static func notification() {
        notifySuccess()
    }
}

// MARK: - Animasyon Motoru (Apple HIG Motion & GPU-Composited Guidelines)

enum AppAnimation {
    /// Hızlı ve hassas yay: Liste güncellemeleri, segment değişimleri (0.22s)
    static let snappy = Animation.snappy(duration: 0.22, extraBounce: 0.05)

    /// Hafif mikro-etkileşim yayı: Yıldızlama, okundu ikonu, sayaç balonu (0.24s)
    static let bouncy = Animation.bouncy(duration: 0.24, extraBounce: 0.10)

    /// Akıcı kayan kapsül yayı: Okuma modu switch'i ve seçim kapsülü (0.26s)
    static let slidingPill = Animation.spring(response: 0.26, dampingFraction: 0.78)

    /// Etkileşimli buton/seçim yayı (0.22s)
    static let interactiveSpring = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.80)

    /// Kart tıklama/dokunma tepkisi: Basılma hissi (0.15s)
    static let cardPress = Animation.interactiveSpring(response: 0.15, dampingFraction: 0.75)

    /// Pürüzsüz sayfa ve makale geçiş yayı (0.26s)
    static let pageReveal = Animation.spring(response: 0.26, dampingFraction: 0.85)

    /// Klasör akordeon açılma yayı (0.24s)
    static let accordion = Animation.spring(response: 0.24, dampingFraction: 0.82)

    /// Pürüzsüz hover geçişi (0.12s)
    static let hover = Animation.easeInOut(duration: 0.12)

    /// Hızlı durum değişimi için easeOut (0.14s)
    static let quickFeedback = Animation.easeOut(duration: 0.14)

    /// Erişilebilirlik (Reduce Motion) aktifken kullanılacak sade fade geçişi
    static let reduced = Animation.easeInOut(duration: 0.14)

    /// Reduce Motion durumuna göre uygun animasyonu döndürür
    static func motion(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// Liste elemanlarının basamaklı belirmesi için gecikme (maksimum 0.15s)
    static func stagger(index: Int) -> Double {
        min(Double(index) * 0.015, 0.15)
    }
}
