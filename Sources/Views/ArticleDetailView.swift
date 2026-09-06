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
                    articleHeader(item: item)
                    Divider()
                    articleContent(item: item)
                }
                .onChange(of: item.id) { _, _ in
                    resetStateForNewArticle(item: item)
                }
                .onAppear {
                    resetStateForNewArticle(item: item)
                }
                .onDisappear {
                    stopSpeech()
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
            }
        }
    }

    private func resetStateForNewArticle(item: FeedItem) {
        stopSpeech()
        let defaultMode = ReadingViewMode(rawValue: defaultReadingModeRaw) ?? .reader
        activeViewMode = defaultMode
        extractedReaderHTML = ReaderModeExtractor.shared.cachedContent(for: item.link)

        if activeViewMode == .reader && extractedReaderHTML == nil {
            loadReaderMode(for: item)
        }
    }

    // MARK: - Article Header

    @ViewBuilder
    private func articleHeader(item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title & Offline indicator
            HStack(alignment: .top, spacing: 10) {
                Text(item.title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)

                Spacer()

                if !networkMonitor.isConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi.slash")
                        Text(String(localized: "Offline"))
                    }
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
                }
            }

            // Metadata row & Toolbar Actions
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    if let feedTitle = currentFeed?.title {
                        HStack(spacing: 6) {
                            FaviconView(hostOrURL: currentFeed?.url ?? item.link, size: 14)
                            Text(feedTitle)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if let author = item.author, !author.isEmpty {
                        Label(author, systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let date = item.pubDate {
                        Label(formattedDate(date), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Reading Time
                    let readingTime = calculateReadingTime(item: item)
                    Label(readingTime, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .truncationMode(.tail)

                Spacer(minLength: 12)

                // Actions
                actionToolbar(item: item)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(16)
    }

    // MARK: - Action Toolbar

    @ViewBuilder
    private func actionToolbar(item: FeedItem) -> some View {
        HStack(spacing: 8) {
            // 2-Way Reading Mode Selector: Reader | Web
            Picker("", selection: $activeViewMode) {
                Text(String(localized: "Reader")).tag(ReadingViewMode.reader)
                Text(String(localized: "Web")).tag(ReadingViewMode.inAppBrowser)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
            .onChange(of: activeViewMode) { _, newMode in
                if newMode == .reader && extractedReaderHTML == nil {
                    loadReaderMode(for: item)
                }
            }

            // 1-Click WebKit Content Blocker Toggle (Web Mode)
            if activeViewMode == .inAppBrowser {
                Button {
                    isContentBlockerEnabled.toggle()
                } label: {
                    Image(systemName: isContentBlockerEnabled ? "shield.fill" : "shield.slash")
                        .foregroundStyle(isContentBlockerEnabled ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(isContentBlockerEnabled ? String(localized: "Content Blocker Active (Click to Disable)") : String(localized: "Content Blocker Disabled (Click to Enable)"))
            }

            // Text to Speech
            Button {
                toggleSpeech(item: item)
            } label: {
                Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2")
                    .foregroundStyle(isSpeaking ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(isSpeaking ? String(localized: "Stop Reading") : String(localized: "Read Aloud"))

            // Appearance Menu (Theme, Font, Size)
            Menu {
                // Themes
                Picker("Theme", selection: $readerThemeRaw) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }

                Divider()

                // Fonts
                Picker("Font Family", selection: $readerFontFamilyRaw) {
                    ForEach(ReaderFontFamily.allCases) { font in
                        Text(font.title).tag(font.rawValue)
                    }
                }

                // Line Spacing
                Picker("Line Spacing", selection: $readerLineHeightRaw) {
                    ForEach(ReaderLineHeight.allCases) { lh in
                        Text(lh.title).tag(lh.rawValue)
                    }
                }

                Divider()

                // Font size
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
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "Appearance"))

            // Share Link
            if let url = URL(string: item.link) {
                ShareLink(item: url, subject: Text(item.title)) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Share"))
            }

            // Bookmark toggle
            Button {
                store.toggleBookmark(item)
            } label: {
                Image(systemName: item.isBookmarked ? "star.fill" : "star")
                    .foregroundStyle(item.isBookmarked ? .orange : .secondary)
            }
            .buttonStyle(.borderless)
            .help(item.isBookmarked ? String(localized: "Remove Bookmark") : String(localized: "Add Bookmark"))

            // Read toggle
            Button {
                store.toggleReadStatus(item)
            } label: {
                Image(systemName: item.isRead ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(item.isRead ? .secondary : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .help(item.isRead ? String(localized: "Mark as Unread") : String(localized: "Mark as Read"))

            // Open in Preferred External Browser
            if let url = URL(string: item.link) {
                Button {
                    currentExternalBrowser.open(url: url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(String(format: String(localized: "Open in %@ (Cmd+Return)"), currentExternalBrowser.title))
            }
        }
    }

    // MARK: - Article Content

    @ViewBuilder
    private func articleContent(item: FeedItem) -> some View {
        switch activeViewMode {
        case .inAppBrowser:
            inAppBrowserView(item: item)

        case .reader:
            readerModeView(item: item)
        }
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
                Text(String(localized: "Switching to cached Reader Mode or RSS summary."))
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
            feedContentView(item: item)
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
            WebView(
                html: extracted,
                fontSize: readerFontSize,
                theme: currentTheme,
                fontFamily: currentFontFamily,
                lineHeight: currentLineHeight
            )
        } else {
            // Fallback to feed content if reader extraction yielded nothing
            feedContentView(item: item)
        }
    }

    // MARK: - Feed Content View

    @ViewBuilder
    private func feedContentView(item: FeedItem) -> some View {
        let contentHTML = item.content ?? item.itemDescription

        if contentHTML.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundStyle(.quaternary)
                Text("Content not available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if URL(string: item.link) != nil {
                    Button(String(localized: "Open in Web View")) {
                        activeViewMode = .inAppBrowser
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WebView(
                html: contentHTML,
                fontSize: readerFontSize,
                theme: currentTheme,
                fontFamily: currentFontFamily,
                lineHeight: currentLineHeight
            )
        }
    }

    // MARK: - Reader Mode Logic

    private func loadReaderMode(for item: FeedItem) {
        if let cached = ReaderModeExtractor.shared.cachedContent(for: item.link) {
            extractedReaderHTML = cached
            return
        }

        isLoadingReaderMode = true
        Task {
            let extracted = await ReaderModeExtractor.shared.extract(from: item.link)
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
        let raw = item.title + ". " + (item.content ?? item.itemDescription)
        return raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Reading Time Calculation

    private func calculateReadingTime(item: FeedItem) -> String {
        let text = (item.content ?? item.itemDescription)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
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
