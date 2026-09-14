import SwiftUI

struct FeedListView: View {

    @Environment(FeedStore.self) private var store
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
        case .folder(let id): return store.folders.first(where: { $0.id == id })?.name ?? String(localized: "Folder")
        case .feed(let id): return store.feed(for: id)?.title ?? String(localized: "Feed")
        case nil: return ""
        }
    }

    private var showFeedName: Bool {
        switch selection {
        case .all, .bookmarks, .unread, .today, .podcasts, .downloaded, .folder: return true
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
            base = store.unreadItems()
        case .today:
            base = store.todayItems()
        case .bookmarks:
            base = store.bookmarkedItems()
        case .podcasts:
            base = store.podcastItems()
        case .downloaded:
            base = store.downloadedItems()
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
                } else if items.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40, weight: .ultraLight))
                            .foregroundStyle(.quaternary)
                        Text("No results found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(String(format: String(localized: "No articles matching \"%@\"."), searchText))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .searchable(text: $searchText, prompt: Text("Search Articles"))
                    .navigationTitle(title)
                } else {
                    VStack(spacing: 0) {
                        if !NetworkMonitor.shared.isConnected {
                            HStack(spacing: 6) {
                                Image(systemName: "wifi.slash")
                                    .font(.caption2)
                                Text(String(localized: "Offline Mode - Showing cached articles"))
                                    .font(.caption2.weight(.medium))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.1))
                            .foregroundStyle(.secondary)
                        }

                        let visibleItems: [FeedItem] = searchText.isEmpty ? Array(items.prefix(displayLimit)) : items

                        List(selection: Binding(
                            get: { selectedArticle },
                            set: { newSelection in
                                withAnimation(AppAnimation.slidingPill) {
                                    selectedArticle = newSelection
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
                                .tag(item)
                                .listRowBackground(EmptyView())
                                .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                                .listRowSeparator(.hidden)
                                .contextMenu {
                                    itemContextMenu(item: item)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        store.toggleReadStatus(item)
                                    } label: {
                                        Label(
                                            item.isRead ? String(localized: "Mark as Unread") : String(localized: "Mark as Read"),
                                            systemImage: item.isRead ? "circle" : "checkmark.circle"
                                        )
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        store.toggleBookmark(item)
                                    } label: {
                                        Label(
                                            item.isBookmarked ? String(localized: "Remove Bookmark") : String(localized: "Bookmark"),
                                            systemImage: item.isBookmarked ? "star.slash" : "star.fill"
                                        )
                                    }
                                    .tint(.orange)
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
                        .safeAreaInset(edge: .top) {
                            Color.clear.frame(height: 6)
                        }
                    .searchable(text: $searchText, prompt: Text("Search Articles"))
                    .navigationTitle(title)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            let unreadItems = items.filter { !$0.isRead }
                            if !unreadItems.isEmpty {
                                Button {
                                    store.markAllAsRead(items: unreadItems)
                                } label: {
                                    Label(String(localized: "Mark All as Read"), systemImage: "checkmark.circle")
                                }
                                .help(String(localized: "Mark All as Read in Current View"))
                            } else if case .feed(let feedId) = selection, !items.isEmpty {
                                Button {
                                    store.markAllAsUnread(feedId: feedId)
                                } label: {
                                    Label(String(localized: "Mark All as Unread"), systemImage: "circle")
                                }
                                .help(String(localized: "Mark All as Unread"))
                            }
                        }
                    }
                    .onChange(of: selectedArticle) { _, newItem in
                        if let newItem {
                            store.markAsRead(newItem)
                        }
                    }
                    .onChange(of: selection) {
                        displayLimit = 60
                    }
                    .background {
                        Group {
                            // Standard command shortcuts
                            Button("Toggle Read Status") {
                                if let selected = selectedArticle {
                                    store.toggleReadStatus(selected)
                                }
                            }
                            .keyboardShortcut("u", modifiers: .command)

                            // Power-User Single Key Shortcuts (J/K/M/S/O)
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
                                        store.toggleReadStatus(selected)
                                    }
                                }
                                .keyboardShortcut("m", modifiers: [])

                                Button("Toggle Bookmark Single Key") {
                                    if let selected = selectedArticle {
                                        store.toggleBookmark(selected)
                                    }
                                }
                                .keyboardShortcut("s", modifiers: [])

                                Button("Open In Browser Single Key") {
                                    if let selected = selectedArticle, let url = URL(string: selected.link) {
                                        let browser = ExternalBrowserOption(rawValue: preferredExternalBrowserRaw) ?? .systemDefault
                                        browser.open(url: url)
                                    }
                                }
                                .keyboardShortcut("o", modifiers: [])

                                Button("Space Paged Reading") {
                                    handleSpacebarNavigation(in: items)
                                }
                                .keyboardShortcut(.space, modifiers: [])

                                Button("Space Paged Reading Up") {
                                    handleShiftSpacebarNavigation(in: items)
                                }
                                .keyboardShortcut(.space, modifiers: [.shift])
                            }
                        }
                        .frame(width: 0, height: 0)
                        .opacity(0)
                    }
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text("Welcome")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Select a feed or category from the sidebar.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .id(selection)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity
        ))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selection)
    }

    // MARK: - Article Navigation

    private func selectNextArticle(in items: [FeedItem]) {
        guard !items.isEmpty else { return }
        guard let current = selectedArticle,
              let index = items.firstIndex(where: { $0.id == current.id }) else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selectedArticle = items.first
            }
            return
        }
        let nextIndex = min(index + 1, items.count - 1)
        if nextIndex >= displayLimit {
            displayLimit = min(displayLimit + 40, items.count)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selectedArticle = items[nextIndex]
        }
    }

    private func selectPreviousArticle(in items: [FeedItem]) {
        guard !items.isEmpty else { return }
        guard let current = selectedArticle,
              let index = items.firstIndex(where: { $0.id == current.id }) else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selectedArticle = items.first
            }
            return
        }
        let prevIndex = max(index - 1, 0)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selectedArticle = items[prevIndex]
        }
    }

    private func handleSpacebarNavigation(in items: [FeedItem]) {
        guard !items.isEmpty else { return }
        guard let current = selectedArticle else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selectedArticle = items.first
            }
            return
        }
        // Advance to next unread article if any, otherwise next article in list
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selectedArticle = article
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func itemContextMenu(item: FeedItem) -> some View {
        Button {
            store.toggleReadStatus(item)
        } label: {
            Label(
                item.isRead ? "Mark as Unread" : "Mark as Read",
                systemImage: item.isRead ? "circle" : "checkmark.circle"
            )
        }

        Button {
            store.toggleBookmark(item)
        } label: {
            Label(
                item.isBookmarked ? "Remove Bookmark" : "Add Bookmark",
                systemImage: item.isBookmarked ? "star.fill" : "star"
            )
        }

        Divider()

        if let url = URL(string: item.link) {
            Button {
                let browser = ExternalBrowserOption(rawValue: preferredExternalBrowserRaw) ?? .systemDefault
                browser.open(url: url)
            } label: {
                Label("Open in Browser", systemImage: "arrow.up.right.square")
            }
        }

        if item.isPodcast {
            Divider()

            Button {
                AudioPlayerService.shared.playNext(item)
            } label: {
                Label("Play Next", systemImage: "text.badge.plus")
            }

            Button {
                AudioPlayerService.shared.addToQueue(item)
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private func emptyState(for item: SidebarItem) -> some View {
        VStack(spacing: 14) {
            if item == .unread {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Color.accentColor.gradient)
                    .padding(.bottom, 2)

                Text(String(localized: "All Caught Up!"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(String(localized: "You have no unread articles. Enjoy your day!"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: emptyStateIcon(for: item))
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(.quaternary)

                Text(emptyStateText(for: item))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if item == .podcasts {
                Button {
                    showPodcastSearch = true
                } label: {
                    Label(String(localized: "Find Podcasts..."), systemImage: "waveform.and.magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 4)
                .sheet(isPresented: $showPodcastSearch) {
                    AddFeedSheet(initialTab: .podcastSearch)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }

    private func emptyStateIcon(for item: SidebarItem) -> String {
        switch item {
        case .all: return "tray"
        case .unread: return "envelope.open"
        case .today: return "clock"
        case .bookmarks: return "star"
        case .podcasts: return "headphones"
        case .downloaded: return "arrow.down.circle"
        case .folder: return "folder"
        case .feed: return "newspaper"
        }
    }

    private func emptyStateText(for item: SidebarItem) -> String {
        switch item {
        case .all: return String(localized: "No articles yet. Start by adding a feed.")
        case .unread: return String(localized: "No unread articles.")
        case .today: return String(localized: "No articles from today.")
        case .bookmarks: return String(localized: "No bookmarked articles yet.")
        case .podcasts: return String(localized: "No podcast episodes yet.")
        case .downloaded: return String(localized: "No downloaded episodes yet.")
        case .folder: return String(localized: "No articles in this folder yet.")
        case .feed: return String(localized: "No articles in this feed yet.")
        }
    }
}

// MARK: - Feed Item Row

struct FeedItemRow: View {

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
            HStack(alignment: .top, spacing: 10) {
                // Unread indicator bubble dot with bounce transition
                ZStack {
                    if !item.isRead {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: Color.accentColor.opacity(0.45), radius: 3)
                            .transition(.scale(scale: 1.4).combined(with: .opacity))
                    }
                }
                .frame(width: 10, height: 10)
                .padding(.top, isCompactListMode ? 4 : 5)
                .animation(AppAnimation.bouncy, value: item.isRead)

                VStack(alignment: .leading, spacing: isCompactListMode ? 2 : 4) {
                    // Title and Bookmark
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.title)
                            .font(.system(.body, design: .default, weight: item.isRead ? .regular : .semibold))
                            .lineLimit(isCompactListMode ? 1 : 2)
                            .foregroundStyle(item.isRead ? .secondary : .primary)

                        if item.isBookmarked {
                            Image(systemName: "star.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.orange)
                                .rotationEffect(.degrees(item.isBookmarked ? 0 : -35))
                                .scaleEffect(item.isBookmarked ? 1.0 : 0.5)
                                .transition(.scale(scale: 1.3).combined(with: .opacity))
                                .animation(AppAnimation.bouncy, value: item.isBookmarked)
                        }
                    }

                    // Content snippet
                    if !isCompactListMode && !item.snippet.isEmpty {
                        Text(item.snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .lineSpacing(2)
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
                                    EqualizerWaveformView(isPlaying: true, barWidth: 2, maxHeight: 10)
                                } else {
                                    Image(systemName: "headphones")
                                }
                                if let duration = item.formattedDuration {
                                    Text(duration)
                                }
                                if isDownloaded {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.green)
                                }
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isPlayingThis ? Color.accentColor : Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isPlayingThis ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                            .clipShape(Capsule())
                        }

                        if item.isYouTube {
                            HStack(spacing: 4) {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundStyle(.red)
                                Text("YouTube")
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 1)
                }
            }

            // Media thumbnail (if YouTube, podcast, or feed image exists)
            if let mediaURL = mediaThumbnailURL {
                let thumbSize: CGFloat = isCompactListMode ? 38 : 50
                AsyncImage(url: mediaURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Color.secondary.opacity(0.08)
                    }
                }
                .frame(width: thumbSize, height: thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
                .overlay(alignment: .center) {
                    if item.isPodcast || item.isYouTube {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(item.isYouTube ? .red : .primary)
                                    .offset(x: 1)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isCompactListMode ? 6 : 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: Color.accentColor.opacity(0.10), radius: 6, y: 2)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                    .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
            }
        }
        .scaleEffect(isPressed ? 0.98 : (isHovered && !isSelected ? 1.008 : 1.0))
        .animation(AppAnimation.hover, value: isHovered)
        .animation(AppAnimation.cardPress, value: isPressed)
        .animation(AppAnimation.slidingPill, value: isSelected)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
