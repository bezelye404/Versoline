import SwiftUI

struct FeedListView: View {

    @Environment(FeedStore.self) private var store
    @Environment(\.appTheme) private var theme
    let selection: SidebarItem?
    @Binding var selectedArticle: FeedItem?
    @State private var searchText = ""
    @State private var showPodcastSearch = false
    @State private var displayLimit: Int = 60

    @AppStorage(AppSettingsKeys.enableSingleKeyShortcuts) private var enableSingleKeyShortcuts = true
    @AppStorage(AppSettingsKeys.mutedKeywords) private var mutedKeywordsRaw = ""
    @AppStorage(AppSettingsKeys.preferredExternalBrowser) private var preferredExternalBrowserRaw = ExternalBrowserOption.systemDefault.rawValue

    private var title: String {
        switch selection {
        case .all: return String(localized: "All Articles")
        case .unread: return String(localized: "Unread")
        case .today: return String(localized: "Today")
        case .bookmarks: return String(localized: "Bookmarks")
        case .podcasts: return String(localized: "Podcasts")
        case .downloaded: return String(localized: "Downloaded Episodes")
        case .quickReads: return String(localized: "Quick Reads")
        case .longReads: return String(localized: "Deep Reads")
        case .media: return String(localized: "Media & Video")
        case .folder(let id): return store.folders.first(where: { $0.id == id })?.name ?? String(localized: "Folder")
        case .feed(let id): return store.feed(for: id)?.title ?? String(localized: "Feed")
        case nil: return ""
        }
    }

    private var showFeedName: Bool {
        switch selection {
        case .all, .bookmarks, .unread, .today, .podcasts, .downloaded, .quickReads, .longReads, .media, .folder: return true
        default: return false
        }
    }

    private var mutedKeywordsList: [String] {
        mutedKeywordsRaw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private var allItems: [FeedItem] {
        let base: [FeedItem]
        switch selection {
        case .all:
            base = store.allItems()
        case .unread:
            let unread = store.unreadItems()
            if let current = selectedArticle, !unread.contains(where: { $0.id == current.id }) {
                var combined = unread
                combined.append(current)
                base = combined.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            } else {
                base = unread
            }
        case .today:
            base = store.todayItems()
        case .bookmarks:
            base = store.bookmarkedItems()
        case .podcasts:
            base = store.podcastItems()
        case .downloaded:
            base = store.downloadedItems()
        case .quickReads:
            base = store.quickReadItems()
        case .longReads:
            base = store.longReadItems()
        case .media:
            base = store.mediaItems()
        case .folder(let id):
            base = store.itemsForFolder(id)
        case .feed(let id):
            base = store.itemsForFeed(id)
        case nil:
            base = []
        }

        // Apply Keyword Muting
        let muted = mutedKeywordsList
        let visibleItems: [FeedItem]
        if muted.isEmpty {
            visibleItems = base
        } else {
            visibleItems = base.filter { item in
                let lowerTitle = item.title.lowercased()
                let lowerSnippet = item.snippet.lowercased()
                for kw in muted {
                    if lowerTitle.contains(kw) || lowerSnippet.contains(kw) {
                        return false
                    }
                }
                return true
            }
        }

        if searchText.isEmpty {
            return visibleItems
        }

        let query = searchText.lowercased()
        return visibleItems.filter {
            $0.title.lowercased().contains(query) ||
            $0.snippet.lowercased().contains(query) ||
            ($0.author?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        Group {
            if selection != nil {
                let items = allItems
                if items.isEmpty && searchText.isEmpty {
                    emptyState(for: selection!)
                } else {
                    VStack(spacing: 0) {
                        inlineSearchBar

                        if !NetworkMonitor.shared.isConnected {
                            HStack(spacing: 6) {
                                Image(systemName: "wifi.slash")
                                    .font(.caption2)
                                Text(String(localized: "Offline Mode — Showing cached articles"))
                                    .font(.caption2.weight(.medium))
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.04))
                            .foregroundStyle(.secondary)
                            .overlay(alignment: .bottom) {
                                Divider()
                            }
                        }

                        if items.isEmpty && !searchText.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 36, weight: .ultraLight))
                                    .foregroundStyle(.quaternary)
                                Text(String(localized: "No results found"))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text(String(format: String(localized: "No articles matching \"%@\"."), searchText))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            let visibleItems: [FeedItem] = searchText.isEmpty ? Array(items.prefix(displayLimit)) : items

                            List(selection: Binding<UUID?>(
                                get: { selectedArticle?.id },
                                set: { newId in
                                    guard let newId else {
                                        selectedArticle = nil
                                        return
                                    }
                                    if let found = items.first(where: { $0.id == newId }) {
                                        AppHaptics.tap()
                                        withAnimation(AppAnimation.slidingPill) {
                                            selectedArticle = found
                                        }
                                    }
                                }
                            )) {
                                ForEach(visibleItems) { item in
                                    let feed = store.feed(for: item.feedId)
                                    FeedItemRow(
                                        item: item,
                                        isSelected: selectedArticle?.id == item.id,
                                        feedTitle: showFeedName ? feed?.title : nil,
                                        feedURL: feed?.url ?? URL(string: item.link)?.host,
                                        feedImageURL: feed?.imageURL
                                    )
                                    .tag(item.id)
                                    .listRowBackground(EmptyView())
                                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                    .listRowSeparator(.hidden)
                                    .onTapGesture {
                                        AppHaptics.tap()
                                        withAnimation(AppAnimation.slidingPill) {
                                            selectedArticle = item
                                        }
                                    }
                                    .contextMenu {
                                        itemContextMenu(item: item)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            AppHaptics.tap()
                                            withAnimation(AppAnimation.quickFeedback) {
                                                store.toggleReadStatus(item)
                                            }
                                        } label: {
                                            Label(
                                                item.isRead ? String(localized: "Mark as Unread") : String(localized: "Mark as Read"),
                                                systemImage: item.isRead ? "circle" : "checkmark.circle"
                                            )
                                        }
                                        .tint(AppTheme.Colors.accent)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button {
                                            AppHaptics.tap()
                                            withAnimation(AppAnimation.bouncy) {
                                                store.toggleBookmark(item)
                                            }
                                        } label: {
                                            Label(
                                                item.isBookmarked ? String(localized: "Remove Bookmark") : String(localized: "Bookmark"),
                                                systemImage: item.isBookmarked ? "star.slash" : "star.fill"
                                            )
                                        }
                                        .tint(AppTheme.Colors.bookmark)
                                    }
                                }

                                if searchText.isEmpty && displayLimit < items.count {
                                    Color.clear
                                        .frame(height: 1)
                                        .onAppear {
                                            displayLimit = min(displayLimit + 40, items.count)
                                        }
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .background(theme.listBackground)
                            .safeAreaInset(edge: .top) {
                                Color.clear.frame(height: 2)
                            }
                        }
                    }
                    .navigationTitle(title)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            let unreadItems = items.filter { !$0.isRead }
                            if !unreadItems.isEmpty {
                                Button {
                                    AppHaptics.notifySuccess()
                                    withAnimation(AppAnimation.quickFeedback) {
                                        store.markAllAsRead(items: unreadItems)
                                    }
                                } label: {
                                    Label(String(localized: "Mark All as Read"), systemImage: "checkmark.circle")
                                }
                                .help(String(localized: "Mark All as Read in Current View"))
                            } else if case .feed(let feedId) = selection, !items.isEmpty {
                                Button {
                                    AppHaptics.notifySuccess()
                                    withAnimation(AppAnimation.quickFeedback) {
                                        store.markAllAsUnread(feedId: feedId)
                                    }
                                } label: {
                                    Label(String(localized: "Mark All as Unread"), systemImage: "circle")
                                }
                                .help(String(localized: "Mark All as Unread"))
                            }
                        }
                    }
                    .onChange(of: selectedArticle?.id) { _, newId in
                        if let newId, let item = items.first(where: { $0.id == newId }), !item.isRead {
                            store.markAsRead(item)
                        }
                    }
                    .onChange(of: selection) {
                        displayLimit = 60
                    }
                    .background {
                        keyboardShortcutsBridge(in: items)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text(String(localized: "Select a Feed"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Inline Search Bar

    private var inlineSearchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(String(localized: "Search articles..."), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.Colors.hairlineBorder, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Keyboard Shortcuts

    @ViewBuilder
    private func keyboardShortcutsBridge(in items: [FeedItem]) -> some View {
        Group {
            Button("Toggle Read Status") {
                if let selected = selectedArticle {
                    AppHaptics.tap()
                    withAnimation(AppAnimation.quickFeedback) {
                        store.toggleReadStatus(selected)
                    }
                }
            }
            .keyboardShortcut("u", modifiers: .command)

            if enableSingleKeyShortcuts {
                Button("Next Article") {
                    selectNextArticle(in: items)
                }
                .keyboardShortcut("j", modifiers: [])

                Button("Previous Article") {
                    selectPreviousArticle(in: items)
                }
                .keyboardShortcut("k", modifiers: [])

                Button("Toggle Read Single Key") {
                    if let selected = selectedArticle {
                        AppHaptics.tap()
                        withAnimation(AppAnimation.quickFeedback) {
                            store.toggleReadStatus(selected)
                        }
                    }
                }
                .keyboardShortcut("m", modifiers: [])

                Button("Toggle Bookmark Single Key") {
                    if let selected = selectedArticle {
                        AppHaptics.tap()
                        withAnimation(AppAnimation.bouncy) {
                            store.toggleBookmark(selected)
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: [])

                Button("Open in Browser Single Key") {
                    if let selected = selectedArticle, let url = URL(string: selected.link) {
                        let browser = ExternalBrowserOption(rawValue: preferredExternalBrowserRaw) ?? .systemDefault
                        browser.open(url: url)
                    }
                }
                .keyboardShortcut("o", modifiers: [])

                Button("Spacebar Advance") {
                    handleSpacebarNavigation(in: items)
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Shift Spacebar Reverse") {
                    handleShiftSpacebarNavigation(in: items)
                }
                .keyboardShortcut(.space, modifiers: .shift)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func selectNextArticle(in items: [FeedItem]) {
        guard !items.isEmpty else { return }
        AppHaptics.tap()
        if let current = selectedArticle, let idx = items.firstIndex(where: { $0.id == current.id }) {
            let nextIndex = idx + 1
            if nextIndex < items.count {
                selectArticleWithExpansion(items[nextIndex], in: items)
            }
        } else {
            selectArticleWithExpansion(items[0], in: items)
        }
    }

    private func selectPreviousArticle(in items: [FeedItem]) {
        guard !items.isEmpty else { return }
        AppHaptics.tap()
        if let current = selectedArticle, let idx = items.firstIndex(where: { $0.id == current.id }) {
            let prevIndex = idx - 1
            if prevIndex >= 0 {
                selectArticleWithExpansion(items[prevIndex], in: items)
            }
        } else {
            selectArticleWithExpansion(items[0], in: items)
        }
    }

    private func handleSpacebarNavigation(in items: [FeedItem]) {
        guard !items.isEmpty else { return }
        guard let current = selectedArticle else {
            withAnimation(AppAnimation.slidingPill) {
                selectedArticle = items.first
            }
            return
        }
        let subsequent = items.drop(while: { $0.id != current.id }).dropFirst()
        if let nextUnread = subsequent.first(where: { !$0.isRead }) {
            selectArticleWithExpansion(nextUnread, in: items)
        } else {
            selectNextArticle(in: items)
        }
    }

    private func handleShiftSpacebarNavigation(in items: [FeedItem]) {
        selectPreviousArticle(in: items)
    }

    private func selectArticleWithExpansion(_ article: FeedItem, in items: [FeedItem]) {
        if let idx = items.firstIndex(where: { $0.id == article.id }), idx >= displayLimit {
            displayLimit = min(idx + 20, items.count)
        }
        withAnimation(AppAnimation.slidingPill) {
            selectedArticle = article
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func itemContextMenu(item: FeedItem) -> some View {
        Button {
            AppHaptics.tap()
            withAnimation(AppAnimation.quickFeedback) {
                store.toggleReadStatus(item)
            }
        } label: {
            Label(
                item.isRead ? String(localized: "Mark as Unread") : String(localized: "Mark as Read"),
                systemImage: item.isRead ? "circle" : "checkmark.circle"
            )
        }

        Button {
            AppHaptics.tap()
            withAnimation(AppAnimation.bouncy) {
                store.toggleBookmark(item)
            }
        } label: {
            Label(
                item.isBookmarked ? String(localized: "Remove Bookmark") : String(localized: "Add Bookmark"),
                systemImage: item.isBookmarked ? "star.fill" : "star"
            )
        }

        Divider()

        if let url = URL(string: item.link) {
            Button {
                let browser = ExternalBrowserOption(rawValue: preferredExternalBrowserRaw) ?? .systemDefault
                browser.open(url: url)
            } label: {
                Label(String(localized: "Open in Browser"), systemImage: "arrow.up.right.square")
            }
        }

        if item.isPodcast {
            Divider()

            Button {
                AudioPlayerService.shared.playNext(item)
            } label: {
                Label(String(localized: "Play Next"), systemImage: "text.badge.plus")
            }

            Button {
                AudioPlayerService.shared.addToQueue(item)
            } label: {
                Label(String(localized: "Add to Queue"), systemImage: "text.append")
            }
        }
    }

    // MARK: - Empty State (Editorial, Minimalist & Calm)

    @ViewBuilder
    private func emptyState(for item: SidebarItem) -> some View {
        VStack(spacing: 14) {
            if item == .unread {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                Text(String(localized: "All Caught Up"))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)

                Text(String(localized: "You have no unread articles. Enjoy your day!"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: emptyStateIcon(for: item))
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 2)

                Text(emptyStateTitle(for: item))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)

                Text(emptyStateText(for: item))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func emptyStateIcon(for item: SidebarItem) -> String {
        switch item {
        case .all: return "tray"
        case .unread: return "envelope.open"
        case .today: return "clock"
        case .bookmarks: return "star"
        case .podcasts: return "headphones"
        case .downloaded: return "arrow.down.circle"
        case .quickReads: return "bolt"
        case .longReads: return "book.closed"
        case .media: return "play.rectangle"
        case .folder: return "folder"
        case .feed: return "newspaper"
        }
    }

    private func emptyStateTitle(for item: SidebarItem) -> String {
        switch item {
        case .all: return String(localized: "No Articles")
        case .unread: return String(localized: "All Caught Up")
        case .today: return String(localized: "No Articles Today")
        case .bookmarks: return String(localized: "No Bookmarks")
        case .podcasts: return String(localized: "No Podcasts")
        case .downloaded: return String(localized: "No Downloads")
        case .quickReads: return String(localized: "No Quick Reads")
        case .longReads: return String(localized: "No Deep Reads")
        case .media: return String(localized: "No Media Articles")
        case .folder: return String(localized: "Folder is Empty")
        case .feed: return String(localized: "Feed is Empty")
        }
    }

    private func emptyStateText(for item: SidebarItem) -> String {
        switch item {
        case .all: return String(localized: "No articles yet. Start by adding a feed.")
        case .unread: return String(localized: "No unread articles.")
        case .today: return String(localized: "No articles published today.")
        case .bookmarks: return String(localized: "Star articles to save them for later.")
        case .podcasts: return String(localized: "Subscribe to podcast feeds to see episodes here.")
        case .downloaded: return String(localized: "Downloaded podcast episodes will appear here for offline playback.")
        case .quickReads: return String(localized: "Short articles (< 3 minutes) will appear here for quick reading.")
        case .longReads: return String(localized: "In-depth articles (7+ minutes) will appear here for deep reading.")
        case .media: return String(localized: "Articles containing YouTube videos or podcasts will appear here.")
        case .folder: return String(localized: "Move feeds into this folder from the sidebar.")
        case .feed: return String(localized: "No articles found in this feed.")
        }
    }
}

// MARK: - Feed Item Row (Calm, Editorial & GPU Composited)

struct FeedItemRow: View {

    @Environment(\.appTheme) private var theme
    @AppStorage(AppSettingsKeys.isCompactListMode) private var isCompactListMode = false
    let item: FeedItem
    var isSelected: Bool = false
    var feedTitle: String? = nil
    var feedURL: String? = nil
    var feedImageURL: String? = nil

    private static let relativeDateTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var formattedDate: String {
        guard let date = item.pubDate else { return "" }
        return Self.relativeDateTimeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private var mediaThumbnailURL: URL? {
        if let yt = item.youtubeThumbnailURL { return yt }
        if item.isPodcast, let img = feedImageURL, let url = URL(string: img) { return url }
        return nil
    }

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Main text column
            HStack(alignment: .top, spacing: 9) {
                // Unread indicator dot
                ZStack {
                    if !item.isRead {
                        Circle()
                            .fill(theme.unreadDotColor)
                            .frame(width: 7, height: 7)
                            .transition(.scale(scale: 1.3).combined(with: .opacity))
                    }
                }
                .frame(width: 8, height: 8)
                .padding(.top, isCompactListMode ? 4 : 5)
                .animation(AppAnimation.bouncy, value: item.isRead)

                VStack(alignment: .leading, spacing: isCompactListMode ? 2 : 4) {
                    // Title and Bookmark
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 13, weight: item.isRead ? .regular : .semibold))
                            .lineLimit(isCompactListMode ? 1 : 2)
                            .foregroundStyle(item.isRead ? .secondary : .primary)

                        if item.isBookmarked {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.bookmarkColor)
                                .transition(.scale(scale: 1.2).combined(with: .opacity))
                                .animation(AppAnimation.bouncy, value: item.isBookmarked)
                        }
                    }

                    // Content snippet
                    if !isCompactListMode && !item.snippet.isEmpty {
                        Text(item.snippet)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .lineSpacing(1.5)
                    }

                    // Metadata row
                    HStack(spacing: 8) {
                        if let feedTitle, !feedTitle.isEmpty {
                            HStack(spacing: 4) {
                                FaviconView(hostOrURL: feedURL ?? URL(string: item.link)?.host ?? item.link, size: 12)
                                Text(feedTitle)
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        }

                        if let author = item.author, !author.isEmpty {
                            Label(author, systemImage: "person")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        if !formattedDate.isEmpty {
                            Text(formattedDate)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        if item.isPodcast {
                            let player = AudioPlayerService.shared
                            let isPlayingThis = player.currentEpisode?.id == item.id && player.isPlaying
                            let isDownloaded = PodcastDownloadService.shared.isDownloaded(item.id)
                            HStack(spacing: 4) {
                                if isPlayingThis {
                                    EqualizerWaveformView(isPlaying: true, barWidth: 2, maxHeight: 9)
                                } else {
                                    Image(systemName: "headphones")
                                }
                                if let duration = item.formattedDuration {
                                    Text(duration)
                                }
                                if isDownloaded {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(AppTheme.Colors.success)
                                }
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isPlayingThis ? AppTheme.Colors.accent : Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(Capsule())
                        }

                        if item.isYouTube {
                            HStack(spacing: 4) {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundStyle(AppTheme.Colors.youtube)
                                Text(String(localized: "YouTube"))
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 1)
                }
            }

            // Media thumbnail
            if let mediaURL = mediaThumbnailURL {
                let thumbSize: CGFloat = isCompactListMode ? 36 : 46
                DownsampledImageView(
                    url: mediaURL,
                    targetSize: CGSize(width: thumbSize, height: thumbSize),
                    contentMode: .fill,
                    cornerRadius: AppTheme.Metrics.thumbnailCornerRadius
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Metrics.thumbnailCornerRadius, style: .continuous)
                        .stroke(AppTheme.Colors.hairlineBorder, lineWidth: 0.5)
                )
                .overlay(alignment: .center) {
                    if item.isPodcast || item.isYouTube {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(item.isYouTube ? AppTheme.Colors.youtube : .primary)
                                    .offset(x: 1)
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isCompactListMode ? 5 : 7)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
                    .fill(theme.cardSelected)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
                            .stroke(theme.cardSelectedBorder, lineWidth: 1.0)
                    )
            } else if isHovered {
                RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
                    .fill(theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
                            .stroke(AppTheme.Colors.hairlineBorder, lineWidth: 0.6)
                    )
            }
        }
        .scaleEffect(isPressed ? 0.985 : (isHovered && !isSelected ? 1.004 : 1.0))
        .animation(AppAnimation.hover, value: isHovered)
        .animation(AppAnimation.cardPress, value: isPressed)
        .animation(AppAnimation.slidingPill, value: isSelected)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
