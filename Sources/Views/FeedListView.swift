import SwiftUI

struct FeedListView: View {

    @Environment(FeedStore.self) private var store
    let selection: SidebarItem?
    @Binding var selectedArticle: FeedItem?
    @State private var searchText = ""

    private var title: String {
        switch selection {
        case .all: return String(localized: "All Articles", bundle: .module)
        case .unread: return String(localized: "Unread", bundle: .module)
        case .today: return String(localized: "Today", bundle: .module)
        case .bookmarks: return String(localized: "Bookmarks", bundle: .module)
        case .feed(let id): return store.feed(for: id)?.title ?? String(localized: "Feed", bundle: .module)
        case nil: return ""
        }
    }

    private var showFeedName: Bool {
        switch selection {
        case .all, .bookmarks, .unread, .today: return true
        default: return false
        }
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
        case .feed(let id):
            base = store.itemsForFeed(id)
        case nil:
            base = []
        }

        if searchText.isEmpty {
            return base
        }

        let query = searchText.lowercased()
        return base.filter {
            $0.title.lowercased().contains(query) ||
            $0.itemDescription.lowercased().contains(query) ||
            ($0.author?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        Group {
            if selection != nil {
                if allItems.isEmpty && searchText.isEmpty {
                    emptyState(for: selection!)
                } else if allItems.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40, weight: .ultraLight))
                            .foregroundStyle(.quaternary)
                        Text("No results found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(String(format: String(localized: "No articles matching \"%@\".", bundle: .module), searchText))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .searchable(text: $searchText, prompt: Text("Search Articles", bundle: .module))
                    .navigationTitle(title)
                } else {
                    List(selection: $selectedArticle) {
                        ForEach(allItems) { item in
                            FeedItemRow(
                                item: item,
                                feedTitle: showFeedName ? store.feed(for: item.feedId)?.title : nil
                            )
                            .tag(item)
                            .contextMenu {
                                itemContextMenu(item: item)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .searchable(text: $searchText, prompt: Text("Search Articles", bundle: .module))
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
                        Button("Toggle Read Status") {
                            if let selected = selectedArticle {
                                store.toggleReadStatus(selected)
                            }
                        }
                        .keyboardShortcut("u", modifiers: .command)
                        .hidden()
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

    @ViewBuilder
    private func emptyState(for item: SidebarItem) -> some View {
        let (icon, message): (String, String) = switch item {
        case .all: ("tray", String(localized: "No articles yet. Start by adding a feed.", bundle: .module))
        case .bookmarks: ("star", String(localized: "No bookmarked articles yet.", bundle: .module))
        case .feed: ("doc.text.magnifyingglass", String(localized: "No articles in this feed yet.", bundle: .module))
        case .unread: ("envelope.badge", String(localized: "No unread articles.", bundle: .module))
        case .today: ("clock", String(localized: "No articles from today.", bundle: .module))
        }

        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }

    @ViewBuilder
    private func itemContextMenu(item: FeedItem) -> some View {
        Button {
            store.toggleBookmark(item)
        } label: {
            Label(
                item.isBookmarked ? "Remove Bookmark" : "Add Bookmark",
                systemImage: item.isBookmarked ? "star.slash" : "star"
            )
        }

        Button {
            store.toggleReadStatus(item)
        } label: {
            Label(
                item.isRead ? "Mark as Unread" : "Mark as Read",
                systemImage: item.isRead ? "circle" : "checkmark.circle"
            )
        }

        if let url = URL(string: item.link) {
            Divider()
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
        }
    }
}

// MARK: - Feed Item Row

struct FeedItemRow: View {

    @AppStorage("isCompactListMode") private var isCompactListMode = false
    let item: FeedItem
    var feedTitle: String? = nil

    private var formattedDate: String {
        guard let date = item.pubDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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

                    if !isCompactListMode && !item.itemDescription.isEmpty {
                        Text(stripHTML(item.itemDescription))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        if let feedTitle, !feedTitle.isEmpty {
                            Label(feedTitle, systemImage: "dot.radiowaves.up.forward")
                                .font(.caption2)
                                .foregroundStyle(.blue.opacity(0.7))
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
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func stripHTML(_ html: String) -> String {
        // Quick regex-based strip for performance
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
