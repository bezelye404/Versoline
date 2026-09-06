import SwiftUI

struct FeedListView: View {

    @Environment(FeedStore.self) private var store
    let selection: SidebarItem?
    @Binding var selectedArticle: FeedItem?
    @State private var searchText = ""
    @State private var showPodcastSearch = false

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
        case .feed(let id): return store.feed(for: id)?.title ?? String(localized: "Feed")
        case nil: return ""
        }
    }

    private var showFeedName: Bool {
        switch selection {
        case .all, .bookmarks, .unread, .today, .podcasts: return true
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
                let lowerDesc = item.itemDescription.lowercased()
                for kw in muted {
                    if lowerTitle.contains(kw) || lowerDesc.contains(kw) {
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
            $0.itemDescription.lowercased().contains(query) ||
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

                        List(selection: $selectedArticle) {
                        ForEach(items) { item in
                            FeedItemRow(
                                item: item,
                                feedTitle: showFeedName ? store.feed(for: item.feedId)?.title : nil,
                                feedURL: showFeedName ? store.feed(for: item.feedId)?.url : nil
                            )
                            .tag(item)
                            .contextMenu {
                                itemContextMenu(item: item)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .searchable(text: $searchText, prompt: Text("Search Articles"))
                    .navigationTitle(title)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            if case .feed(let feedId) = selection {
                                if store.allRead(feedId: feedId) {
                                    Button {
                                        store.markAllAsUnread(feedId: feedId)
                                    } label: {
                                        Label("Mark All as Unread", systemImage: "circle")
                                    }
                                    .help("Mark All as Unread")
                                } else {
                                    Button {
                                        store.markAllAsRead(feedId: feedId)
                                    } label: {
                                        Label("Mark All as Read", systemImage: "checkmark.circle")
                                    }
                                    .help("Mark All as Read")
                                }
                            }
                        }
                    }
                    .onChange(of: selectedArticle) { _, newItem in
                        if let newItem {
                            store.markAsRead(newItem)
                        }
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
    }

    // MARK: - Article Navigation

    private func selectNextArticle(in items: [FeedItem]) {
        guard !items.isEmpty else { return }
        guard let current = selectedArticle,
              let index = items.firstIndex(where: { $0.id == current.id }) else {
            selectedArticle = items.first
            return
        }
        let nextIndex = min(index + 1, items.count - 1)
        selectedArticle = items[nextIndex]
    }

    private func selectPreviousArticle(in items: [FeedItem]) {
        guard !items.isEmpty else { return }
        guard let current = selectedArticle,
              let index = items.firstIndex(where: { $0.id == current.id }) else {
            selectedArticle = items.first
            return
        }
        let prevIndex = max(index - 1, 0)
        selectedArticle = items[prevIndex]
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
    }

    // MARK: - Empty State

    @ViewBuilder
    private func emptyState(for item: SidebarItem) -> some View {
        VStack(spacing: 16) {
            Image(systemName: emptyStateIcon(for: item))
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.quaternary)

            Text(emptyStateText(for: item))
                .font(.subheadline)
                .foregroundStyle(.secondary)

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
        case .feed: return String(localized: "No articles in this feed yet.")
        }
    }
}

// MARK: - Feed Item Row

struct FeedItemRow: View {

    @AppStorage(AppSettingsKeys.isCompactListMode) private var isCompactListMode = false
    let item: FeedItem
    var feedTitle: String? = nil
    var feedURL: String? = nil

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

    var body: some View {
        VStack(alignment: .leading, spacing: isCompactListMode ? 2 : 6) {
            HStack(alignment: .top, spacing: 8) {
                // Unread indicator
                Circle()
                    .fill(item.isRead ? .clear : .blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, isCompactListMode ? 4 : 5)

                VStack(alignment: .leading, spacing: isCompactListMode ? 2 : 4) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(.body, design: .default, weight: item.isRead ? .regular : .semibold))
                            .lineLimit(isCompactListMode ? 1 : 2)
                            .foregroundStyle(item.isRead ? .secondary : .primary)

                        if item.isBookmarked {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    if !isCompactListMode && !item.snippet.isEmpty {
                        Text(item.snippet)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        if let feedTitle, !feedTitle.isEmpty {
                            HStack(spacing: 4) {
                                FaviconView(hostOrURL: feedURL ?? item.link, size: 12)
                                Text(feedTitle)
                            }
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.8))
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
                            HStack(spacing: 3) {
                                Image(systemName: isPlayingThis ? "waveform" : "headphones")
                                if let duration = item.formattedDuration {
                                    Text(duration)
                                }
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isPlayingThis ? Color.accentColor : Color.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(isPlayingThis ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
