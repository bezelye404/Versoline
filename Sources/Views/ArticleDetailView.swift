import SwiftUI
import AppKit

struct ArticleDetailView: View {

    @Environment(FeedStore.self) private var store

    @AppStorage(AppSettingsKeys.readerFontSize) private var readerFontSize = 16
    @AppStorage(AppSettingsKeys.readerTheme) private var readerThemeRaw = ReaderTheme.system.rawValue
    @AppStorage(AppSettingsKeys.readerFontFamily) private var readerFontFamilyRaw = ReaderFontFamily.system.rawValue
    @AppStorage(AppSettingsKeys.readerLineHeight) private var readerLineHeightRaw = ReaderLineHeight.normal.rawValue
    @AppStorage(AppSettingsKeys.autoReaderMode) private var autoReaderMode = false

    let selectedItem: FeedItem?

    @State private var isReaderModeActive = false
    @State private var extractedReaderHTML: String? = nil
    @State private var isLoadingReaderMode = false

    private var currentTheme: ReaderTheme {
        ReaderTheme(rawValue: readerThemeRaw) ?? .system
    }

    private var currentFontFamily: ReaderFontFamily {
        ReaderFontFamily(rawValue: readerFontFamilyRaw) ?? .system
    }

    private var currentLineHeight: ReaderLineHeight {
        ReaderLineHeight(rawValue: readerLineHeightRaw) ?? .normal
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
                    isReaderModeActive = false
                    extractedReaderHTML = nil
                    if autoReaderMode {
                        loadReaderMode(for: item)
                    }
                }
                .onAppear {
                    if autoReaderMode {
                        loadReaderMode(for: item)
                    }
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

    // MARK: - Article Header

    @ViewBuilder
    private func articleHeader(item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)

            HStack(spacing: 16) {
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

                Spacer()

                HStack(spacing: 8) {
                    // Reader Mode Toggle
                    Button {
                        toggleReaderMode(item: item)
                    } label: {
                        if isLoadingReaderMode {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: isReaderModeActive ? "sparkles" : "sparkle")
                                .foregroundStyle(isReaderModeActive ? Color.accentColor : Color.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                    .help(isReaderModeActive ? "Exit Reader Mode" : "Enter Reader Mode (Cmd+Shift+R)")
                    .keyboardShortcut("r", modifiers: [.command, .shift])

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
                        Label("Appearance", systemImage: "textformat.size")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Reader Appearance & Themes")

                    // Share Link
                    if let url = URL(string: item.link) {
                        ShareLink(item: url, subject: Text(item.title)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Share Article")
                    }

                    // Bookmark toggle
                    Button {
                        store.toggleBookmark(item)
                    } label: {
                        Label(
                            item.isBookmarked ? "Remove Bookmark" : "Add Bookmark",
                            systemImage: item.isBookmarked ? "star.fill" : "star"
                        )
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(item.isBookmarked ? .orange : .secondary)

                    // Read toggle
                    Button {
                        store.toggleReadStatus(item)
                    } label: {
                        Label(
                            item.isRead ? "Mark as Unread" : "Mark as Read",
                            systemImage: item.isRead ? "circle" : "checkmark.circle.fill"
                        )
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)

                    // Open in browser
                    if let url = URL(string: item.link) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Open in Browser", systemImage: "safari")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Open in Browser (Cmd+Return)")
                    }
                }
            }
        }
        .padding(18)
    }

    // MARK: - Article Content

    @ViewBuilder
    private func articleContent(item: FeedItem) -> some View {
        let contentHTML: String = {
            if isReaderModeActive, let extracted = extractedReaderHTML {
                return extracted
            }
            return item.content ?? item.itemDescription
        }()

        if contentHTML.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundStyle(.quaternary)
                Text("Content not available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let url = URL(string: item.link) {
                    Button("Open in Browser") {
                        NSWorkspace.shared.open(url)
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

    private func toggleReaderMode(item: FeedItem) {
        if isReaderModeActive {
            isReaderModeActive = false
        } else {
            loadReaderMode(for: item)
        }
    }

    private func loadReaderMode(for item: FeedItem) {
        if extractedReaderHTML != nil {
            isReaderModeActive = true
            return
        }

        isLoadingReaderMode = true
        Task {
            let extracted = await ReaderModeExtractor.shared.extract(from: item.link)
            isLoadingReaderMode = false
            if let extracted, !extracted.isEmpty {
                extractedReaderHTML = extracted
                isReaderModeActive = true
            }
        }
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
