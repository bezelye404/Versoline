import SwiftUI
import AppKit
import AVFoundation

struct ArticleDetailView: View {

    @Environment(FeedStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(AppSettingsKeys.readerFontSize) private var readerFontSize = 16
    @AppStorage(AppSettingsKeys.readerTheme) private var readerThemeRaw = ReaderTheme.system.rawValue
    @AppStorage(AppSettingsKeys.readerFontFamily) private var readerFontFamilyRaw = ReaderFontFamily.system.rawValue
    @AppStorage(AppSettingsKeys.readerLineHeight) private var readerLineHeightRaw = ReaderLineHeight.normal.rawValue
    @AppStorage(AppSettingsKeys.autoReaderMode) private var autoReaderMode = false
    @AppStorage(AppSettingsKeys.defaultReadingMode) private var defaultReadingModeRaw = ReadingViewMode.reader.rawValue
    @AppStorage(AppSettingsKeys.preferredExternalBrowser) private var preferredExternalBrowserRaw = ExternalBrowserOption.systemDefault.rawValue
    @AppStorage(AppSettingsKeys.isContentBlockerEnabled) private var isContentBlockerEnabled = true
    @AppStorage(AppSettingsKeys.isBionicReadingEnabled) private var isBionicReadingEnabled = false

    let selectedItem: FeedItem?

    @State private var activeViewMode: ReadingViewMode = .reader
    @State private var extractedReaderHTML: String? = nil
    @State private var isLoadingReaderMode = false
    @State private var isSpeaking = false
    @State private var speechSynthesizer: AVSpeechSynthesizer? = nil
    @State private var speechDelegate = ArticleSpeechDelegate()
    @State private var showQuoteCardSheet = false
    @State private var currentExtractionTask: Task<Void, Never>? = nil
    @Namespace private var animationNamespace

    private let networkMonitor = NetworkMonitor.shared

    private var currentTheme: ReaderTheme {
        if readerThemeRaw == ReaderTheme.system.rawValue {
            return theme.readerThemeDefault
        }
        return ReaderTheme(rawValue: readerThemeRaw) ?? theme.readerThemeDefault
    }

    private var currentFontFamily: ReaderFontFamily {
        ReaderFontFamily(rawValue: readerFontFamilyRaw) ?? .system
    }

    private var currentLineHeight: ReaderLineHeight {
        ReaderLineHeight(rawValue: readerLineHeightRaw) ?? .normal
    }

    private var currentExternalBrowser: ExternalBrowserOption {
        ExternalBrowserOption(rawValue: preferredExternalBrowserRaw) ?? .systemDefault
    }

    // Always read fresh data from store with safe fallback to selectedItem
    private var currentItem: FeedItem? {
        guard let item = selectedItem else { return nil }
        if let fresh = store.items[item.feedId]?.first(where: { $0.id == item.id || $0.link == item.link }) {
            return fresh
        }
        return item
    }

    private var currentFeed: Feed? {
        guard let item = selectedItem else { return nil }
        return store.feed(for: item.feedId)
    }

    var body: some View {
        Group {
            if let item = currentItem {
                VStack(spacing: 0) {
                    // Dedicated, non-overlapping Top Bar (stays stably pinned at the top)
                    readerTopBar(item: item)

                    Divider()

                    // Main Reader / Media Content Layer (smooth cross-fade transition on item change)
                    Group {
                        if item.isPodcast {
                            if activeViewMode == .inAppBrowser {
                                inAppBrowserView(item: item)
                            } else {
                                podcastFullPageView(item: item)
                            }
                        } else if item.isYouTube {
                            VStack(spacing: 0) {
                                if let videoID = item.youtubeVideoID {
                                    YouTubePlayerView(videoID: videoID, title: item.title, link: item.link, item: item)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 12)
                                }
                                articleContent(item: item)
                            }
                        } else {
                            articleContent(item: item)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(item.id)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 6)),
                                removal: .opacity
                            )
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(AppAnimation.motion(AppAnimation.articleTransition, reduceMotion: reduceMotion), value: item.id)
                .onChange(of: item.id) { _, _ in
                    let videoPlayer = VideoPlayerService.shared
                    // If a video was loaded but is NOT playing (paused, ended, or stopped),
                    // and navigating to a non-video article, close it to free ~300MB WebKit & GPU memory
                    if !videoPlayer.isPlaying && videoPlayer.currentVideo != nil && !item.isYouTube {
                        videoPlayer.close()
                    }

                    resetStateForNewArticle(item: item)
                }
                .onAppear {
                    resetStateForNewArticle(item: item)
                }
                .onDisappear {
                    currentExtractionTask?.cancel()
                    currentExtractionTask = nil
                    stopSpeech()
                    let videoPlayer = VideoPlayerService.shared
                    if !videoPlayer.isPlaying {
                        videoPlayer.close()
                    }
                    WebView.flushMemoryCache()
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text(String(localized: "Select an Article"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Choose an article from the list to begin reading."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    WebView.flushMemoryCache()
                }
            }
        }
        .sheet(isPresented: $showQuoteCardSheet) {
            if let item = currentItem {
                QuoteCardSheet(item: item, feedTitle: currentFeed?.title)
            }
        }
    }

    private func resetStateForNewArticle(item: FeedItem) {
        currentExtractionTask?.cancel()
        currentExtractionTask = nil
        stopSpeech()
        let defaultMode = ReadingViewMode(rawValue: defaultReadingModeRaw) ?? .reader
        activeViewMode = defaultMode
        let cached = ReaderModeExtractor.shared.cachedContent(for: item.link, requireSubstantive: true)
        extractedReaderHTML = cached

        if activeViewMode == .reader && cached == nil {
            loadReaderMode(for: item, forceWeb: false)
        }
    }

    // MARK: - Date & Duration Typography Helper

    private static let heroDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.autoupdatingCurrent
        fmt.dateFormat = "MMM d"
        return fmt
    }()

    private func heroDateDurationPill(date: Date?, duration: String?) -> String {
        var parts: [String] = []
        if let date {
            parts.append(Self.heroDateFormatter.string(from: date).uppercased())
        }
        if let duration, !duration.isEmpty {
            parts.append(duration.uppercased())
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Reader Top Bar (Calm, Non-Overlapping & Integrated)

    @ViewBuilder
    private func readerTopBar(item: FeedItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // Left: Feed Identity & Offline Capsule
            HStack(spacing: 6) {
                if let feed = currentFeed {
                    FaviconView(hostOrURL: feed.url, size: 13)
                    Text(feed.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !networkMonitor.isConnected {
                    HStack(spacing: 3) {
                        Image(systemName: "wifi.slash")
                        Text(String(localized: "Offline"))
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 240, alignment: .leading)

            Spacer(minLength: 8)

            // Right: Control Group
            HStack(spacing: 8) {
                // Reading Mode Sliding Bubble Switcher
                HStack(spacing: 0) {
                    Button {
                        AppHaptics.tap()
                        withAnimation(AppAnimation.slidingPill) {
                            activeViewMode = .reader
                        }
                    } label: {
                        Text(String(localized: "Reader"))
                            .font(.system(size: 11, weight: activeViewMode == .reader ? .semibold : .medium))
                            .foregroundStyle(activeViewMode == .reader ? Color.primary : Color.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background {
                                if activeViewMode == .reader {
                                    Capsule()
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
                                        .matchedGeometryEffect(id: "readingModeBubble", in: animationNamespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)

                    Button {
                        AppHaptics.tap()
                        withAnimation(AppAnimation.slidingPill) {
                            activeViewMode = .inAppBrowser
                        }
                    } label: {
                        Text(String(localized: "Web"))
                            .font(.system(size: 11, weight: activeViewMode == .inAppBrowser ? .semibold : .medium))
                            .foregroundStyle(activeViewMode == .inAppBrowser ? Color.primary : Color.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background {
                                if activeViewMode == .inAppBrowser {
                                    Capsule()
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
                                        .matchedGeometryEffect(id: "readingModeBubble", in: animationNamespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .background(Color.primary.opacity(0.05), in: Capsule())
                .onChange(of: activeViewMode) { _, newMode in
                    if newMode == .reader && (extractedReaderHTML == nil || !ReaderModeExtractor.shared.isSubstantiveContent(extractedReaderHTML ?? "")) {
                        loadReaderMode(for: item, forceWeb: false)
                    }
                }

                // Appearance Menu
                Menu {
                    Picker(String(localized: "Theme"), selection: $readerThemeRaw) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                    Divider()
                    Picker(String(localized: "Font Family"), selection: $readerFontFamilyRaw) {
                        ForEach(ReaderFontFamily.allCases) { font in
                            Text(font.title).tag(font.rawValue)
                        }
                    }
                    Picker(String(localized: "Line Spacing"), selection: $readerLineHeightRaw) {
                        ForEach(ReaderLineHeight.allCases) { lh in
                            Text(lh.title).tag(lh.rawValue)
                        }
                    }
                    Divider()
                    Toggle(String(localized: "Bionic Reading"), isOn: $isBionicReadingEnabled)
                    Divider()
                    HStack {
                        Button(String(localized: "Smaller Font")) {
                            if readerFontSize > 12 { readerFontSize -= 2 }
                        }
                        Button(String(localized: "Larger Font")) {
                            if readerFontSize < 32 { readerFontSize += 2 }
                        }
                    }
                } label: {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(String(localized: "Appearance"))

                // Reload or Content Blocker
                if activeViewMode == .reader {
                    Button {
                        AppHaptics.tap()
                        loadReaderMode(for: item, forceWeb: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(isLoadingReaderMode ? AppTheme.Colors.accent : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoadingReaderMode)
                    .help(String(localized: "Fetch / Reload Full Article from Web"))
                } else {
                    Button {
                        AppHaptics.tap()
                        isContentBlockerEnabled.toggle()
                    } label: {
                        Image(systemName: isContentBlockerEnabled ? "shield.fill" : "shield.slash")
                            .font(.system(size: 11))
                            .foregroundStyle(isContentBlockerEnabled ? AppTheme.Colors.accent : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(isContentBlockerEnabled ? String(localized: "Content Blocker Active") : String(localized: "Content Blocker Disabled"))
                }

                Divider()
                    .frame(height: 10)

                // Bookmark
                Button {
                    AppHaptics.tap()
                    withAnimation(AppAnimation.bouncy) {
                        store.toggleBookmark(item)
                    }
                } label: {
                    Image(systemName: item.isBookmarked ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.isBookmarked ? theme.bookmarkColor : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help(item.isBookmarked ? String(localized: "Remove Bookmark") : String(localized: "Add Bookmark"))

                // Read Status
                Button {
                    AppHaptics.tap()
                    withAnimation(AppAnimation.bouncy) {
                        store.toggleReadStatus(item)
                    }
                } label: {
                    Image(systemName: item.isRead ? "circle" : "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.isRead ? Color.secondary : theme.accentColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help(item.isRead ? String(localized: "Mark as Unread") : String(localized: "Mark as Read"))

                Divider()
                    .frame(height: 10)

                // Text-to-speech
                Button {
                    AppHaptics.tap()
                    withAnimation(AppAnimation.bouncy) {
                        toggleSpeech(item: item)
                    }
                } label: {
                    Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2")
                        .font(.system(size: 11))
                        .foregroundStyle(isSpeaking ? theme.accentColor : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help(isSpeaking ? String(localized: "Stop Reading") : String(localized: "Read Aloud"))

                // Share & External Actions
                Menu {
                    Button {
                        shareArticleOrEpisode(item: item)
                    } label: {
                        Label(String(localized: "Share..."), systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showQuoteCardSheet = true
                    } label: {
                        Label(String(localized: "Create Quote Card"), systemImage: "quote.opening")
                    }

                    if let url = URL(string: item.link) {
                        Button {
                            currentExternalBrowser.open(url: url)
                        } label: {
                            Label(String(format: String(localized: "Open in %@"), currentExternalBrowser.title), systemImage: "arrow.up.right.square")
                        }

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.link, forType: .string)
                        } label: {
                            Label(String(localized: "Copy Link"), systemImage: "doc.on.doc")
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(String(localized: "Share & External Actions"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 40)
        .background(theme.detailBackground)
    }

    // MARK: - Podcast Full Page Scroll View

    @ViewBuilder
    private func podcastFullPageView(item: FeedItem) -> some View {
        let player = AudioPlayerService.shared
        let isCurrentEpisode = player.currentEpisode?.id == item.id
        let isPlaying = isCurrentEpisode && player.isPlaying
        let downloadService = PodcastDownloadService.shared
        let isDownloaded = downloadService.isDownloaded(item.id)
        let isDownloading = downloadService.activeDownloads[item.id] != nil

        ScrollView {
            VStack(spacing: 18) {
                Spacer().frame(height: 14)

                // 1. Artwork presentation
                ZStack {
                    if let artworkURL = currentFeed?.imageURL.flatMap({ URL(string: $0) }) {
                        DownsampledImageView(
                            url: artworkURL,
                            targetSize: CGSize(width: 240, height: 240),
                            contentMode: .fill,
                            cornerRadius: 16
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppTheme.Colors.hairlineBorder, lineWidth: 0.8)
                        )
                    } else {
                        ZStack {
                            Color.primary.opacity(0.04)
                            Image(systemName: "headphones")
                                .font(.system(size: 56, weight: .ultraLight))
                                .foregroundStyle(AppTheme.Colors.podcast)
                        }
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppTheme.Colors.hairlineBorder, lineWidth: 0.8)
                        )
                    }

                    // Glass Play/Pause Button
                    Button {
                        AppHaptics.tap()
                        withAnimation(AppAnimation.bouncy) {
                            player.play(item: item, feedTitle: currentFeed?.title, store: store)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Circle()
                                        .stroke(AppTheme.Colors.hairlineBorder, lineWidth: 0.5)
                                )

                            if isCurrentEpisode && player.isBuffering {
                                ProgressView()
                                    .controlSize(.regular)
                            } else {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .offset(x: isPlaying ? 0 : 2)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(isPlaying ? String(localized: "Pause") : String(localized: "Play Episode"))
                }

                // 2. Minimalist Scrubber Bar
                VStack(spacing: 4) {
                    let totalDur = isCurrentEpisode && player.duration > 0 ? player.duration : (Double(item.audioDuration ?? "0") ?? 1.0)
                    let currTime = isCurrentEpisode ? player.currentTime : item.playbackPosition

                    Slider(
                        value: Binding(
                            get: { isCurrentEpisode ? player.currentTime : item.playbackPosition },
                            set: { val in
                                if isCurrentEpisode {
                                    player.seek(to: val)
                                }
                            }
                        ),
                        in: 0...max(totalDur, 1.0)
                    )
                    .controlSize(.mini)
                    .tint(AppTheme.Colors.accent)

                    HStack {
                        Text(formatDuration(currTime))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Spacer()

                        let remaining = totalDur > currTime ? totalDur - currTime : 0
                        Text(totalDur > 1 ? "-\(formatDuration(remaining))" : "--:--")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 380)
                .padding(.horizontal, 24)

                // 3. Date & Duration Pill
                let pillText = heroDateDurationPill(date: item.pubDate, duration: item.formattedDuration)
                if !pillText.isEmpty {
                    Text(pillText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.6)
                }

                // 4. Episode Title
                Text(item.title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 24)

                // 5. Podcast Feed Title & Subtitle with Equalizer
                HStack(spacing: 6) {
                    if let feedTitle = currentFeed?.title {
                        Text(feedTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if isPlaying {
                        EqualizerWaveformView(isPlaying: true, barWidth: 2, maxHeight: 11)
                    }
                }

                // 6. Transport Controls Row
                HStack(spacing: 20) {
                    Button {
                        if isCurrentEpisode {
                            AppHaptics.tap()
                            player.skipBackward(seconds: 15)
                        }
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Skip backward 15 seconds"))

                    // Speed Menu
                    Menu {
                        ForEach(AudioPlayerService.availableRates, id: \.self) { rate in
                            Button {
                                player.setPlaybackRate(rate)
                            } label: {
                                HStack {
                                    Text(String(format: "%.2fx", rate))
                                    if player.playbackRate == rate {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(String(format: "%.2fx", player.playbackRate))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(String(localized: "Playback Speed"))

                    // Sleep Timer Menu
                    Menu {
                        Button(String(localized: "Turn Off Timer")) {
                            player.cancelSleepTimer()
                        }
                        Divider()
                        Button("15 " + String(localized: "minutes")) { player.startSleepTimer(minutes: 15) }
                        Button("30 " + String(localized: "minutes")) { player.startSleepTimer(minutes: 30) }
                        Button("45 " + String(localized: "minutes")) { player.startSleepTimer(minutes: 45) }
                        Button("60 " + String(localized: "minutes")) { player.startSleepTimer(minutes: 60) }
                        Button(String(localized: "End of Episode")) { player.startSleepTimerUntilEndOfEpisode() }
                    } label: {
                        Image(systemName: player.sleepTimerRemainingSeconds != nil ? "moon.zzz.fill" : "moon.zzz")
                            .font(.system(size: 14))
                            .foregroundStyle(player.sleepTimerRemainingSeconds != nil ? AppTheme.Colors.accent : Color.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(String(localized: "Sleep Timer"))

                    Button {
                        if isCurrentEpisode {
                            AppHaptics.tap()
                            player.skipForward(seconds: 15)
                        }
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Skip forward 15 seconds"))

                    Button {
                        AppHaptics.tap()
                        if isDownloaded {
                            downloadService.deleteDownload(for: item.id)
                        } else if !isDownloading {
                            downloadService.downloadEpisode(item)
                        }
                    } label: {
                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: isDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(isDownloaded ? AppTheme.Colors.success : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(isDownloaded ? String(localized: "Downloaded (Click to delete)") : String(localized: "Download Episode"))
                }
                .padding(.vertical, 4)

                // 7. Clickable Chapters
                let chapters = parseChapters(from: item.itemDescription + " " + (extractedReaderHTML ?? item.content ?? ""))
                if !chapters.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(chapters) { ch in
                                Button {
                                    AppHaptics.tap()
                                    if player.currentEpisode?.id != item.id {
                                        player.play(item: item, feedTitle: currentFeed?.title, store: store)
                                    }
                                    player.seek(to: ch.seconds)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(ch.timestamp)
                                            .font(.caption2.monospacedDigit().weight(.semibold))
                                            .foregroundStyle(AppTheme.Colors.accent)
                                        Text(ch.title)
                                            .font(.caption2)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.05))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }

                // 8. Episode Show Notes
                Divider()
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "SHOW NOTES"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.6)

                    let showNotesText = cleanShowNotesText(from: item.content ?? item.itemDescription)
                    Text(showNotesText)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 24)

                Spacer().frame(height: 48)
            }
        }
    }

    private func cleanShowNotesText(from raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</(?:p|div|li|h[1-6])>"#, with: "\n\n", options: .regularExpression)
        return text.strippingHTML()
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private static let chapterRegex = try? NSRegularExpression(
        pattern: #"(?:^|\s)(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\s*[-–—]?\s*([^\n\r<]{3,60})"#,
        options: [.anchorsMatchLines]
    )

    private func parseChapters(from text: String) -> [PodcastChapter] {
        guard let regex = Self.chapterRegex else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [] }
        var chapters: [PodcastChapter] = []
        chapters.reserveCapacity(matches.count)

        for match in matches {
            let hStr = match.range(at: 1).location != NSNotFound ? ns.substring(with: match.range(at: 1)) : nil
            let mStr = ns.substring(with: match.range(at: 2))
            let sStr = ns.substring(with: match.range(at: 3))
            let titleStr = ns.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines)

            let h = Double(hStr ?? "0") ?? 0
            let m = Double(mStr) ?? 0
            let s = Double(sStr) ?? 0
            let totalSeconds = (h * 3600) + (m * 60) + s
            let timeLabel = h > 0 ? String(format: "%d:%02d:%02d", Int(h), Int(m), Int(s)) : String(format: "%d:%02d", Int(m), Int(s))

            chapters.append(PodcastChapter(timestamp: timeLabel, seconds: totalSeconds, title: titleStr))
        }
        return chapters
    }

    private func shareArticleOrEpisode(item: FeedItem) {
        let player = AudioPlayerService.shared
        let urlText = (item.isPodcast && player.currentEpisode?.id == item.id) ? player.shareURLString(for: item) : item.link
        let shareString = "\(item.title)\n\(urlText)"
        let picker = NSSharingServicePicker(items: [shareString])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .maxY)
        }
    }

    // MARK: - Article Content

    @ViewBuilder
    private func articleContent(item: FeedItem) -> some View {
        ZStack {
            if activeViewMode == .reader {
                readerModeView(item: item)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.99)),
                        removal: .opacity
                    ))
            } else {
                inAppBrowserView(item: item)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.99)),
                        removal: .opacity
                    ))
            }
        }
        .animation(AppAnimation.slidingPill, value: activeViewMode)
    }

    // MARK: - In-App Browser Mode

    @ViewBuilder
    private func inAppBrowserView(item: FeedItem) -> some View {
        if !networkMonitor.isConnected {
            VStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundStyle(.quaternary)
                Text(String(localized: "Live web page unavailable offline."))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Switching to cached Reader Mode."))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                Button(String(localized: "View Cached Reader Mode")) {
                    activeViewMode = .reader
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let url = URL(string: item.link) {
            WebView(
                url: url,
                fontSize: readerFontSize,
                theme: currentTheme,
                fontFamily: currentFontFamily,
                lineHeight: currentLineHeight,
                isContentBlockerEnabled: isContentBlockerEnabled
            )
        } else {
            readerModeView(item: item)
        }
    }

    // MARK: - Reader Mode View

    private func readerHTML(for item: FeedItem) -> String {
        if let extracted = extractedReaderHTML, !extracted.isEmpty {
            return extracted
        }
        return ReaderModeExtractor.shared.formatFeedContentAsReaderHTML(
            title: item.title,
            author: item.author,
            pubDate: item.pubDate,
            htmlContent: item.content ?? item.itemDescription,
            link: item.link,
            feedTitle: currentFeed?.title,
            includeHeader: true
        )
    }

    @ViewBuilder
    private func readerModeView(item: FeedItem) -> some View {
        let contentHTML = readerHTML(for: item)
        let isSubstantive = extractedReaderHTML != nil && ReaderModeExtractor.shared.isSubstantiveContent(contentHTML)

        VStack(spacing: 0) {
            if isLoadingReaderMode {
                // Subtle non-blocking top extraction progress indicator
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(theme.accentColor)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }

            // Keep the WebView continuously mounted across article changes to reuse the same WebContent process
            WebView(
                html: contentHTML,
                fontSize: readerFontSize,
                theme: currentTheme,
                fontFamily: currentFontFamily,
                lineHeight: currentLineHeight,
                isBionicReadingEnabled: isBionicReadingEnabled
            )

            if !isSubstantive && !isLoadingReaderMode {
                summaryNoticeBanner(item: item)
            }
        }
    }

    @ViewBuilder
    private func summaryNoticeBanner(item: FeedItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            Text(String(localized: "Showing feed summary. Tap to fetch full article from web."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                AppHaptics.tap()
                loadReaderMode(for: item, forceWeb: true)
            } label: {
                Label(String(localized: "Fetch Full Article"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.Colors.hairlineBorder, lineWidth: 0.5)
        )
        .padding(10)
    }

    // MARK: - Reader Mode Logic

    private func loadReaderMode(for item: FeedItem, forceWeb: Bool = false) {
        if !forceWeb, let cached = ReaderModeExtractor.shared.cachedContent(for: item.link, requireSubstantive: true) {
            extractedReaderHTML = cached
            return
        }

        let isReddit = item.link.lowercased().contains("reddit.com")
        let isYouTube = item.link.lowercased().contains("youtube.com") || item.link.lowercased().contains("youtu.be")

        if (isReddit || isYouTube) && !forceWeb {
            let formatted = ReaderModeExtractor.shared.formatFeedContentAsReaderHTML(
                title: item.title,
                author: item.author,
                pubDate: item.pubDate,
                htmlContent: item.content ?? item.itemDescription,
                link: item.link,
                feedTitle: currentFeed?.title,
                includeHeader: true
            )
            extractedReaderHTML = formatted
            ReaderModeExtractor.shared.saveToCache(urlString: item.link, content: formatted, storeInMemory: false)
            return
        }

        isLoadingReaderMode = true
        let targetId = item.id
        currentExtractionTask?.cancel()
        currentExtractionTask = Task {
            let extracted = await ReaderModeExtractor.shared.extract(
                from: item.link,
                fallbackContent: item.content ?? item.itemDescription,
                title: item.title,
                author: item.author,
                pubDate: item.pubDate,
                forceWebFetch: forceWeb
            )
            guard !Task.isCancelled else { return }
            guard currentItem?.id == targetId else { return }
            isLoadingReaderMode = false
            if let extracted, !extracted.isEmpty {
                extractedReaderHTML = extracted
            }
        }
    }

    // MARK: - Text to Speech Logic

    private func toggleSpeech(item: FeedItem) {
        if isSpeaking {
            stopSpeech()
        } else {
            let textToRead = cleanTextForSpeech(item: item)
            guard !textToRead.isEmpty else { return }
            let synth = speechSynthesizer ?? AVSpeechSynthesizer()
            speechSynthesizer = synth
            speechDelegate.onFinish = { [self] in
                self.isSpeaking = false
                self.speechSynthesizer = nil
            }
            synth.delegate = speechDelegate
            let utterance = AVSpeechUtterance(string: textToRead)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synth.speak(utterance)
            isSpeaking = true
        }
    }

    private func stopSpeech() {
        if isSpeaking {
            speechSynthesizer?.stopSpeaking(at: .immediate)
            speechSynthesizer = nil
            isSpeaking = false
        }
    }

    private func cleanTextForSpeech(item: FeedItem) -> String {
        let content = (extractedReaderHTML ?? item.content ?? item.itemDescription).strippingHTML()
        return "\(item.title). \(content)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Reading Time Calculation

    private func calculateReadingTime(item: FeedItem) -> String {
        let raw = extractedReaderHTML ?? item.content ?? item.itemDescription
        var wordCount = 0
        var inWord = false
        var inTag = false
        for ch in raw {
            if ch == "<" { inTag = true; continue }
            if ch == ">" { inTag = false; continue }
            if inTag { continue }
            if ch.isWhitespace {
                if inWord {
                    wordCount += 1
                    inWord = false
                }
            } else {
                inWord = true
            }
        }
        if inWord { wordCount += 1 }
        let minutes = max(1, Int(ceil(Double(wordCount) / 200.0)))
        return String(format: String(localized: "%d min read"), minutes)
    }
}

// MARK: - AVSpeechSynthesizer Delegate

@MainActor
final class ArticleSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (@MainActor () -> Void)?

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.onFinish?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.onFinish?()
        }
    }
}

// MARK: - Podcast Chapter Model

struct PodcastChapter: Identifiable, Hashable {
    let id = UUID()
    let timestamp: String
    let seconds: Double
    let title: String
}

// MARK: - Quote Card Generator & Preview (Native ImageRenderer / Zero External Deps)

struct QuoteCardSheet: View {
    let item: FeedItem
    let feedTitle: String?
    @Environment(\.dismiss) private var dismiss
    @State private var quoteText: String = ""
    @State private var selectedPalette: AppColorPalette = .slate
    @State private var isCopied: Bool = false

    init(item: FeedItem, feedTitle: String?) {
        self.item = item
        self.feedTitle = feedTitle
        let initial = item.itemDescription.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines)
        _quoteText = State(initialValue: initial.isEmpty ? item.title : String(initial.prefix(280)))
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text(String(localized: "Quote Card Generator"))
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Live Preview Card
            QuoteCardPreview(
                quote: quoteText,
                articleTitle: item.title,
                author: item.author,
                feedTitle: feedTitle ?? "easyRSS",
                palette: selectedPalette
            )
            .padding(.horizontal, 20)

            // Edit Quote
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Quote Text:"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $quoteText)
                    .font(.system(size: 13))
                    .frame(height: 60)
                    .padding(4)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.Colors.hairlineBorder, lineWidth: 1))
            }
            .padding(.horizontal, 20)

            // Palette selector
            HStack(spacing: 12) {
                Text(String(localized: "Palette:"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(AppColorPalette.allCases) { palette in
                    Button {
                        selectedPalette = palette
                    } label: {
                        Circle()
                            .fill(palette.accentColor)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: selectedPalette == palette ? 2 : 0)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(selectedPalette == palette ? palette.accentColor : Color.clear, lineWidth: 1)
                                    .scaleEffect(1.3)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            Divider()

            // Actions
            HStack {
                Spacer()
                Button {
                    copyCardToPasteboard()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? String(localized: "Copied!") : String(localized: "Copy Image to Clipboard"))
                    }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(selectedPalette.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @MainActor
    private func copyCardToPasteboard() {
        let card = QuoteCardPreview(
            quote: quoteText,
            articleTitle: item.title,
            author: item.author,
            feedTitle: feedTitle ?? "easyRSS",
            palette: selectedPalette
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0 // High-DPI Retina
        if let image = renderer.nsImage {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            AppHaptics.notification()
            isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isCopied = false
            }
        }
    }
}

struct QuoteCardPreview: View {
    let quote: String
    let articleTitle: String
    let author: String?
    let feedTitle: String
    let palette: AppColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(palette.accentColor)
                    .frame(width: 10, height: 10)
                Text(feedTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "quote.opening")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.accentColor.opacity(0.4))
            }

            Text("“\(quote)”")
                .font(.system(size: 15, weight: .medium, design: .serif))
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .opacity(0.4)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(articleTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let author, !author.isEmpty {
                        Text(author)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("easyRSS")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}
