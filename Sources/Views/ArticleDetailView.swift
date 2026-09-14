import SwiftUI
import AppKit
import AVFoundation

struct ArticleDetailView: View {

    @Environment(FeedStore.self) private var store

    @AppStorage(AppSettingsKeys.readerFontSize) private var readerFontSize = 16
    @AppStorage(AppSettingsKeys.readerTheme) private var readerThemeRaw = ReaderTheme.system.rawValue
    @AppStorage(AppSettingsKeys.readerFontFamily) private var readerFontFamilyRaw = ReaderFontFamily.system.rawValue
    @AppStorage(AppSettingsKeys.readerLineHeight) private var readerLineHeightRaw = ReaderLineHeight.normal.rawValue
    @AppStorage(AppSettingsKeys.autoReaderMode) private var autoReaderMode = false
    @AppStorage(AppSettingsKeys.defaultReadingMode) private var defaultReadingModeRaw = ReadingViewMode.reader.rawValue
    @AppStorage(AppSettingsKeys.preferredExternalBrowser) private var preferredExternalBrowserRaw = ExternalBrowserOption.systemDefault.rawValue
    @AppStorage(AppSettingsKeys.isContentBlockerEnabled) private var isContentBlockerEnabled = true

    let selectedItem: FeedItem?

    @State private var activeViewMode: ReadingViewMode = .reader
    @State private var extractedReaderHTML: String? = nil
    @State private var isLoadingReaderMode = false
    @State private var isSpeaking = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var speechDelegate = ArticleSpeechDelegate()
    @State private var isVideoTheater: Bool = false

    private let networkMonitor = NetworkMonitor.shared

    private var currentTheme: ReaderTheme {
        ReaderTheme(rawValue: readerThemeRaw) ?? .system
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

    // Always read fresh data from store
    private var currentItem: FeedItem? {
        guard let item = selectedItem else { return nil }
        return store.items[item.feedId]?.first { $0.id == item.id }
    }

    private var currentFeed: Feed? {
        guard let item = selectedItem else { return nil }
        return store.feed(for: item.feedId)
    }

    var body: some View {
        Group {
            if let item = currentItem {
                VStack(spacing: 0) {
                    if !isVideoTheater {
                        floatingToolbar(item: item)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                        Divider()
                    }

                    ZStack {
                        if isVideoTheater {
                            Color.black.ignoresSafeArea()
                        }

                        VStack(spacing: 0) {
                            if !isVideoTheater {
                                if item.isPodcast {
                                    podcastHeroMediaCard(item: item)
                                        .padding(.top, 14)
                                } else if !item.isYouTube {
                                    standardArticleHeader(item: item)
                                    Divider()
                                }
                            }

                            // YouTube Built-in Player (Seamlessly expands in-app without reload)
                            if let videoID = item.youtubeVideoID {
                                YouTubePlayerView(videoID: videoID, title: item.title, link: item.link, isTheaterMode: $isVideoTheater)
                                    .frame(maxWidth: .infinity, maxHeight: isVideoTheater ? .infinity : nil)
                                    .padding(.horizontal, isVideoTheater ? 0 : 20)
                                    .padding(.vertical, isVideoTheater ? 0 : 12)
                            }

                            if !isVideoTheater {
                                articleContent(item: item)
                            }
                        }
                    }
                }
                .id(item.id)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 8)),
                    removal: .opacity
                ))
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: item.id)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isVideoTheater)
                .onChange(of: item.id) { _, _ in
                    resetStateForNewArticle(item: item)
                }
                .onAppear {
                    resetStateForNewArticle(item: item)
                }
                .onDisappear {
                    stopSpeech()
                    WebView.flushMemoryCache()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text("Select an article")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Select an article from the list on the left to read.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    WebView.flushMemoryCache()
                }
            }
        }
    }

    private func resetStateForNewArticle(item: FeedItem) {
        isVideoTheater = false
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

    private func heroDateDurationPill(date: Date?, duration: String?) -> String {
        var parts: [String] = []
        if let date {
            let fmt = DateFormatter()
            fmt.locale = Locale.autoupdatingCurrent
            fmt.dateFormat = "MMM d"
            parts.append(fmt.string(from: date).uppercased())
        }
        if let duration, !duration.isEmpty {
            parts.append(duration.uppercased())
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Floating Pill Toolbar

    @ViewBuilder
    private func floatingToolbar(item: FeedItem) -> some View {
        HStack(alignment: .center) {
            // Left: Feed Title & Favicon
            HStack(spacing: 6) {
                if let feed = currentFeed {
                    FaviconView(hostOrURL: feed.url, size: 14)
                    Text(feed.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !networkMonitor.isConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi.slash")
                        Text(String(localized: "Offline"))
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            // Right: Floating Pill Capsule Toolbar
            HStack(spacing: 8) {
                // Reading Mode Switcher
                Picker("", selection: $activeViewMode) {
                    Text(String(localized: "Reader")).tag(ReadingViewMode.reader)
                    Text(String(localized: "Web")).tag(ReadingViewMode.inAppBrowser)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 128)
                .onChange(of: activeViewMode) { _, newMode in
                    if newMode == .reader && (extractedReaderHTML == nil || !ReaderModeExtractor.shared.isSubstantiveContent(extractedReaderHTML ?? "")) {
                        loadReaderMode(for: item, forceWeb: false)
                    }
                }

                // Appearance Menu
                Menu {
                    Picker("Theme", selection: $readerThemeRaw) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                    Divider()
                    Picker("Font Family", selection: $readerFontFamilyRaw) {
                        ForEach(ReaderFontFamily.allCases) { font in
                            Text(font.title).tag(font.rawValue)
                        }
                    }
                    Picker("Line Spacing", selection: $readerLineHeightRaw) {
                        ForEach(ReaderLineHeight.allCases) { lh in
                            Text(lh.title).tag(lh.rawValue)
                        }
                    }
                    Divider()
                    HStack {
                        Button("Smaller Font") {
                            if readerFontSize > 12 { readerFontSize -= 2 }
                        }
                        Button("Larger Font") {
                            if readerFontSize < 32 { readerFontSize += 2 }
                        }
                    }
                } label: {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(String(localized: "Appearance"))

                // Reload or Content Blocker
                if activeViewMode == .reader {
                    Button {
                        loadReaderMode(for: item, forceWeb: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(isLoadingReaderMode ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoadingReaderMode)
                    .help(String(localized: "Fetch / Reload Full Article from Web"))
                } else {
                    Button {
                        isContentBlockerEnabled.toggle()
                    } label: {
                        Image(systemName: isContentBlockerEnabled ? "shield.fill" : "shield.slash")
                            .font(.system(size: 12))
                            .foregroundStyle(isContentBlockerEnabled ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(isContentBlockerEnabled ? String(localized: "Content Blocker Active") : String(localized: "Content Blocker Disabled"))
                }

                Divider()
                    .frame(height: 12)

                // Bookmark
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        store.toggleBookmark(item)
                    }
                } label: {
                    Image(systemName: item.isBookmarked ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(item.isBookmarked ? .orange : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help(item.isBookmarked ? String(localized: "Remove Bookmark") : String(localized: "Add Bookmark"))

                // Read Status
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        store.toggleReadStatus(item)
                    }
                } label: {
                    Image(systemName: item.isRead ? "circle" : "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(item.isRead ? .secondary : Color.accentColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help(item.isRead ? String(localized: "Mark as Unread") : String(localized: "Mark as Read"))

                Divider()
                    .frame(height: 12)

                // Text-to-speech
                Button {
                    toggleSpeech(item: item)
                } label: {
                    Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2")
                        .font(.system(size: 12))
                        .foregroundStyle(isSpeaking ? Color.accentColor : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help(isSpeaking ? String(localized: "Stop Reading") : String(localized: "Read Aloud"))

                // Share & Open in browser
                Menu {
                    Button {
                        shareArticleOrEpisode(item: item)
                    } label: {
                        Label(String(localized: "Share..."), systemImage: "square.and.arrow.up")
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
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(String(localized: "Share & External Actions"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Standard Article Header

    @ViewBuilder
    private func standardArticleHeader(item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let readingTime = calculateReadingTime(item: item)
            let pillText = heroDateDurationPill(date: item.pubDate, duration: readingTime)
            if !pillText.isEmpty {
                Text(pillText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
            }

            Text(item.title)
                .font(.title.weight(.bold))
                .textSelection(.enabled)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let feedTitle = currentFeed?.title {
                    HStack(spacing: 5) {
                        FaviconView(hostOrURL: currentFeed?.url ?? item.link, size: 14)
                        Text(feedTitle)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                if let author = item.author, !author.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Label(author, systemImage: "person")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Podcast Hero Media Card

    @ViewBuilder
    private func podcastHeroMediaCard(item: FeedItem) -> some View {
        let player = AudioPlayerService.shared
        let isCurrentEpisode = player.currentEpisode?.id == item.id
        let isPlaying = isCurrentEpisode && player.isPlaying
        let downloadService = PodcastDownloadService.shared
        let isDownloaded = downloadService.isDownloaded(item.id)
        let isDownloading = downloadService.activeDownloads[item.id] != nil

        VStack(spacing: 14) {
            // Large Centered Square Artwork with Floating Glass Play Button
            ZStack {
                let artworkURL = currentFeed?.imageURL.flatMap { URL(string: $0) }
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    default:
                        ZStack {
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "headphones")
                                .font(.system(size: 60, weight: .ultraLight))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 7)

                // Large Glass Play/Pause Button
                Button {
                    player.play(item: item, feedTitle: currentFeed?.title, store: store)
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 62, height: 62)
                            .shadow(color: Color.black.opacity(0.28), radius: 10, y: 4)

                        if isCurrentEpisode && player.isBuffering {
                            ProgressView()
                                .controlSize(.regular)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.primary)
                                .offset(x: isPlaying ? 0 : 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(isPlaying ? String(localized: "Pause") : String(localized: "Play Episode"))
            }
            .padding(.top, 4)

            // Minimalist Scrubber Bar
            VStack(spacing: 5) {
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
                .tint(Color.accentColor)

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

            // Transport Controls Row
            HStack(spacing: 20) {
                Button {
                    if isCurrentEpisode {
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
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
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
                        .foregroundStyle(player.sleepTimerRemainingSeconds != nil ? Color.accentColor : Color.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(String(localized: "Sleep Timer"))

                Button {
                    if isCurrentEpisode {
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
                            .foregroundStyle(isDownloaded ? Color.green : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(isDownloaded ? String(localized: "Downloaded (Click to delete)") : String(localized: "Download Episode"))
            }

            // Episode Information & Typography
            VStack(spacing: 6) {
                let pillText = heroDateDurationPill(date: item.pubDate, duration: item.formattedDuration)
                if !pillText.isEmpty {
                    Text(pillText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                }

                Text(item.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .padding(.horizontal, 16)

                HStack(spacing: 6) {
                    if let feedTitle = currentFeed?.title {
                        Text(feedTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if isPlaying {
                        EqualizerWaveformView(isPlaying: true, barWidth: 2, maxHeight: 12)
                    }
                }
            }

            // Clickable Chapters
            let chapters = parseChapters(from: item.itemDescription + " " + (extractedReaderHTML ?? item.content ?? ""))
            if !chapters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chapters) { ch in
                            Button {
                                if player.currentEpisode?.id != item.id {
                                    player.play(item: item, feedTitle: currentFeed?.title, store: store)
                                }
                                player.seek(to: ch.seconds)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(ch.timestamp)
                                        .font(.caption2.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                    Text(ch.title)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 20)
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
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: activeViewMode)
    }

    // MARK: - In-App Browser Mode

    @ViewBuilder
    private func inAppBrowserView(item: FeedItem) -> some View {
        if !networkMonitor.isConnected {
            VStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 36, weight: .ultraLight))
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

    @ViewBuilder
    private func readerModeView(item: FeedItem) -> some View {
        if isLoadingReaderMode {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                Text(String(localized: "Extracting article text..."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let extracted = extractedReaderHTML, !extracted.isEmpty {
            VStack(spacing: 0) {
                WebView(
                    html: extracted,
                    fontSize: readerFontSize,
                    theme: currentTheme,
                    fontFamily: currentFontFamily,
                    lineHeight: currentLineHeight
                )

                if !ReaderModeExtractor.shared.isSubstantiveContent(extracted) {
                    summaryNoticeBanner(item: item)
                }
            }
        } else {
            // Fallback to item content formatted as reader mode HTML if reader extraction yielded nothing
            let fallbackHTML = ReaderModeExtractor.shared.formatFeedContentAsReaderHTML(
                title: item.title,
                author: item.author,
                pubDate: item.pubDate,
                htmlContent: item.content ?? item.itemDescription,
                link: item.link
            )
            VStack(spacing: 0) {
                WebView(
                    html: fallbackHTML,
                    fontSize: readerFontSize,
                    theme: currentTheme,
                    fontFamily: currentFontFamily,
                    lineHeight: currentLineHeight
                )

                summaryNoticeBanner(item: item)
            }
        }
    }

    @ViewBuilder
    private func summaryNoticeBanner(item: FeedItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 15))

            Text(String(localized: "Showing feed summary. Tap to fetch full article from web."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                loadReaderMode(for: item, forceWeb: true)
            } label: {
                Label(String(localized: "Fetch Full Article"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }

    // MARK: - Reader Mode Logic

    private func loadReaderMode(for item: FeedItem, forceWeb: Bool = false) {
        if !forceWeb, let cached = ReaderModeExtractor.shared.cachedContent(for: item.link, requireSubstantive: true) {
            extractedReaderHTML = cached
            return
        }

        // Reddit and YouTube feeds contain full post HTML inside the RSS enclosure
        let isReddit = item.link.lowercased().contains("reddit.com")
        let isYouTube = item.link.lowercased().contains("youtube.com") || item.link.lowercased().contains("youtu.be")

        if (isReddit || isYouTube) && !forceWeb {
            let formatted = ReaderModeExtractor.shared.formatFeedContentAsReaderHTML(
                title: item.title,
                author: item.author,
                pubDate: item.pubDate,
                htmlContent: item.content ?? item.itemDescription,
                link: item.link
            )
            extractedReaderHTML = formatted
            ReaderModeExtractor.shared.saveToCache(urlString: item.link, content: formatted, storeInMemory: false)
            return
        }

        isLoadingReaderMode = true
        Task {
            let extracted = await ReaderModeExtractor.shared.extract(
                from: item.link,
                fallbackContent: item.content ?? item.itemDescription,
                title: item.title,
                author: item.author,
                pubDate: item.pubDate,
                forceWebFetch: forceWeb
            )
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
            speechDelegate.onFinish = { [self] in
                self.isSpeaking = false
            }
            speechSynthesizer.delegate = speechDelegate
            let utterance = AVSpeechUtterance(string: textToRead)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            speechSynthesizer.speak(utterance)
            isSpeaking = true
        }
    }

    private func stopSpeech() {
        if isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
        }
    }

    private func cleanTextForSpeech(item: FeedItem) -> String {
        let content = (extractedReaderHTML ?? item.content ?? item.itemDescription).strippingHTML()
        return "\(item.title). \(content)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Reading Time Calculation

    private func calculateReadingTime(item: FeedItem) -> String {
        let text = (extractedReaderHTML ?? item.content ?? item.itemDescription).strippingHTML()
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let minutes = max(1, Int(ceil(Double(words) / 200.0)))
        return String(format: String(localized: "%d min read"), minutes)
    }

    // MARK: - Date Formatting

    private static let articleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func formattedDate(_ date: Date) -> String {
        Self.articleDateFormatter.string(from: date)
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
