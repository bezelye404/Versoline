import SwiftUI

struct SidebarView: View {

    @Environment(FeedStore.self) private var store
    @Binding var selectedItem: SidebarItem?
    @Binding var selectedArticle: FeedItem?
    @State private var showAddFeed = false
    @State private var showFolderManagement = false
    @State private var managingFolderId: UUID?
    @State private var showAddFolder = false
    @State private var newFolderName = ""
    @State private var renamingFolderId: UUID?
    @State private var renameText = ""
    @State private var editingSmartFolder: Folder?
    @State private var smartKeywordsText = ""

    // Collapsible sections persistence
    @AppStorage("collapsedFolderIds") private var collapsedFolderIdsRaw: String = ""
    @AppStorage("isUncategorizedExpanded") private var isUncategorizedExpanded: Bool = true

    var body: some View {
        List(selection: $selectedItem) {
            librarySection
            foldersSection
            uncategorizedSection
            emptyStateSection
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 36)
                .background(.bar)
        }
        .sheet(isPresented: $showAddFeed) {
            AddFeedSheet()
        }
        .sheet(isPresented: $showFolderManagement) {
            FolderManagementView(initialFolderId: managingFolderId)
        }
        .onChange(of: showFolderManagement) { _, isShowing in
            if !isShowing {
                managingFolderId = nil
            }
        }
        .alert(String(localized: "New Folder"), isPresented: $showAddFolder) {
            TextField(String(localized: "Folder Name"), text: $newFolderName)
            Button(String(localized: "Add")) {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    store.addFolder(name: trimmed)
                    AppHaptics.notifySuccess()
                    newFolderName = ""
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text(String(localized: "Enter a name for the new folder."))
        }
        .alert(String(localized: "Rename Folder"), isPresented: .init(
            get: { renamingFolderId != nil },
            set: { if !$0 { renamingFolderId = nil } }
        )) {
            TextField(String(localized: "Folder Name"), text: $renameText)
            Button(String(localized: "Save")) {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if let folderId = renamingFolderId, !trimmed.isEmpty {
                    store.renameFolder(folderId, name: trimmed)
                    AppHaptics.notifySuccess()
                }
                renamingFolderId = nil
                renameText = ""
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                renamingFolderId = nil
                renameText = ""
            }
        }
        .alert(String(localized: "Smart Folder Rules"), isPresented: .init(
            get: { editingSmartFolder != nil },
            set: { if !$0 { editingSmartFolder = nil } }
        )) {
            TextField(String(localized: "Keywords (comma separated)"), text: $smartKeywordsText)
            Button(String(localized: "Save Rules"), action: saveSmartFolderRules)
            Button(String(localized: "Clear Rules"), role: .destructive, action: clearSmartFolderRules)
            Button(String(localized: "Cancel"), role: .cancel) {
                editingSmartFolder = nil
                smartKeywordsText = ""
            }
        } message: {
            Text(String(localized: "Enter comma-separated keywords (e.g. apple, swift, ai). Any matching article across all feeds will be aggregated into this folder."))
        }
        .onChange(of: selectedItem) { _, _ in
            selectedArticle = nil
            AppHaptics.tap()
        }
    }

    // MARK: - Library Section

    @ViewBuilder
    private var librarySection: some View {
        Section(String(localized: "Library")) {
            NavigationLink(value: SidebarItem.all) {
                sidebarRow(
                    title: String(localized: "All Articles"),
                    systemImage: "tray.full",
                    count: store.totalItemCount,
                    accentColor: .secondary
                )
            }

            NavigationLink(value: SidebarItem.unread) {
                sidebarRow(
                    title: String(localized: "Unread"),
                    systemImage: "envelope.badge",
                    count: store.totalUnreadCount(),
                    accentColor: AppTheme.Colors.unreadDot,
                    isProminent: store.totalUnreadCount() > 0
                )
            }

            NavigationLink(value: SidebarItem.today) {
                sidebarRow(
                    title: String(localized: "Today"),
                    systemImage: "clock",
                    count: store.todayItemsCount(),
                    accentColor: .secondary
                )
            }

            NavigationLink(value: SidebarItem.bookmarks) {
                sidebarRow(
                    title: String(localized: "Bookmarks"),
                    systemImage: "star",
                    count: store.bookmarkCount(),
                    accentColor: AppTheme.Colors.bookmark
                )
            }

            NavigationLink(value: SidebarItem.podcasts) {
                sidebarRow(
                    title: String(localized: "Podcasts"),
                    systemImage: "headphones",
                    count: store.podcastCount(),
                    accentColor: AppTheme.Colors.podcast
                )
            }

            let downloadedCount = store.downloadedItemsCount()
            if downloadedCount > 0 {
                NavigationLink(value: SidebarItem.downloaded) {
                    sidebarRow(
                        title: String(localized: "Downloaded"),
                        systemImage: "arrow.down.circle",
                        count: downloadedCount,
                        accentColor: AppTheme.Colors.success
                    )
                }
            }

            Button {
                managingFolderId = nil
                showFolderManagement = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    Text(String(localized: "Folders"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)

                    Spacer()

                    if !store.folders.isEmpty {
                        Text("\(store.folders.count)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.Colors.badgeText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(AppTheme.Colors.badgeBackground, in: Capsule())
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Row Helper

    @ViewBuilder
    private func sidebarRow(
        title: String,
        systemImage: String,
        count: Int,
        accentColor: Color,
        isProminent: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(accentColor)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: isProminent ? .semibold : .medium, design: .monospaced))
                    .foregroundStyle(isProminent ? AppTheme.Colors.activeBadgeText : AppTheme.Colors.badgeText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        isProminent ? AppTheme.Colors.activeBadgeBackground : AppTheme.Colors.badgeBackground,
                        in: Capsule()
                    )
                    .contentTransition(.numericText())
                    .animation(AppAnimation.bouncy, value: count)
            }
        }
    }

    private func isFolderExpanded(_ folderId: UUID) -> Bool {
        let set = Set(collapsedFolderIdsRaw.components(separatedBy: ",").filter { !$0.isEmpty })
        return !set.contains(folderId.uuidString)
    }

    private func toggleFolder(_ folderId: UUID) {
        AppHaptics.tap()
        withAnimation(AppAnimation.accordion) {
            var set = Set(collapsedFolderIdsRaw.components(separatedBy: ",").filter { !$0.isEmpty })
            if set.contains(folderId.uuidString) {
                set.remove(folderId.uuidString)
            } else {
                set.insert(folderId.uuidString)
            }
            collapsedFolderIdsRaw = set.joined(separator: ",")
        }
    }

    // MARK: - Folders Section

    @ViewBuilder
    private var foldersSection: some View {
        ForEach(store.folders) { folder in
            let expanded = isFolderExpanded(folder.id)
            Section {
                if expanded {
                    FolderStreamRow(folder: folder)
                        .dropDestination(for: String.self) { items, _ in
                            guard let idStr = items.first, let feedId = UUID(uuidString: idStr) else { return false }
                            withAnimation(AppAnimation.snappy) {
                                store.moveFeed(feedId, toFolder: folder.id)
                            }
                            AppHaptics.notifySuccess()
                            return true
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    ForEach(store.feedsInFolder(folder.id)) { feed in
                        NavigationLink(value: SidebarItem.feed(feed.id)) {
                            FeedRow(feed: feed)
                        }
                        .contextMenu { feedContextMenu(feed: feed) }
                        .draggable(feed.id.uuidString)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            } header: {
                folderHeader(for: folder)
            }
        }
    }

    // MARK: - Uncategorized Section

    @ViewBuilder
    private var uncategorizedSection: some View {
        let uncategorized = store.uncategorizedFeeds()
        if !uncategorized.isEmpty {
            Section {
                if isUncategorizedExpanded {
                    ForEach(uncategorized) { feed in
                        NavigationLink(value: SidebarItem.feed(feed.id)) {
                            FeedRow(feed: feed)
                        }
                        .contextMenu { feedContextMenu(feed: feed) }
                        .draggable(feed.id.uuidString)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            } header: {
                Button {
                    AppHaptics.tap()
                    withAnimation(AppAnimation.accordion) {
                        isUncategorizedExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                            .rotationEffect(.degrees(isUncategorizedExpanded ? 90 : 0))
                            .animation(AppAnimation.snappy, value: isUncategorizedExpanded)

                        Image(systemName: "tray")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text(store.folders.isEmpty ? String(localized: "Feeds") : String(localized: "Uncategorized"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(uncategorized.count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.Colors.badgeText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AppTheme.Colors.badgeBackground, in: Capsule())
                            .contentTransition(.numericText())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                .dropDestination(for: String.self) { items, _ in
                    guard let idStr = items.first, let feedId = UUID(uuidString: idStr) else { return false }
                    withAnimation(AppAnimation.snappy) {
                        store.moveFeed(feedId, toFolder: nil)
                    }
                    AppHaptics.notifySuccess()
                    return true
                }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateSection: some View {
        if store.feeds.isEmpty && store.folders.isEmpty {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(.tertiary)

                    Text(String(localized: "No feeds added yet"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(String(localized: "Add Feed")) {
                        showAddFeed = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Smart Folder Helpers

    private func saveSmartFolderRules() {
        guard let folder = editingSmartFolder else { return }
        var parsedKeywords: [String] = []
        for rawPart in smartKeywordsText.components(separatedBy: ",") {
            let trimmed = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parsedKeywords.append(trimmed)
            }
        }
        let finalKeywords: [String]? = parsedKeywords.isEmpty ? nil : parsedKeywords
        store.updateFolderKeywords(folder.id, keywords: finalKeywords)
        AppHaptics.notifySuccess()
        editingSmartFolder = nil
        smartKeywordsText = ""
    }

    private func clearSmartFolderRules() {
        guard let folder = editingSmartFolder else { return }
        store.updateFolderKeywords(folder.id, keywords: nil)
        AppHaptics.notifySuccess()
        editingSmartFolder = nil
        smartKeywordsText = ""
    }

    // MARK: - Folder Header

    @ViewBuilder
    private func folderHeader(for folder: Folder) -> some View {
        let expanded = isFolderExpanded(folder.id)
        let feedsCount = store.feedsInFolder(folder.id).count

        Button {
            toggleFolder(folder.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .animation(AppAnimation.snappy, value: expanded)

                Image(systemName: folder.isSmartFolder ? "folder.badge.gearshape" : "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(folder.isSmartFolder ? AppTheme.Colors.accent : Color.secondary)

                Text(folder.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if folder.isSmartFolder {
                    Text(String(localized: "Smart"))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(AppTheme.Colors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                if feedsCount > 0 {
                    Text("\(feedsCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.Colors.badgeText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AppTheme.Colors.badgeBackground, in: Capsule())
                        .contentTransition(.numericText())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .dropDestination(for: String.self) { items, _ in
            guard let idStr = items.first, let feedId = UUID(uuidString: idStr) else { return false }
            withAnimation(AppAnimation.snappy) {
                store.moveFeed(feedId, toFolder: folder.id)
            }
            AppHaptics.notifySuccess()
            return true
        }
        .contextMenu {
            Button {
                managingFolderId = folder.id
                showFolderManagement = true
            } label: {
                Label(String(localized: "Manage Feeds..."), systemImage: "folder.badge.gearshape")
            }

            Divider()

            Button {
                smartKeywordsText = folder.keywords?.joined(separator: ", ") ?? ""
                editingSmartFolder = folder
            } label: {
                Label(folder.isSmartFolder ? String(localized: "Edit Smart Rules...") : String(localized: "Set Smart Rules..."), systemImage: "sparkles")
            }

            Divider()

            Button {
                renameText = folder.name
                renamingFolderId = folder.id
            } label: {
                Label(String(localized: "Rename"), systemImage: "pencil")
            }

            Button(role: .destructive) {
                store.removeFolder(folder.id)
            } label: {
                Label(String(localized: "Delete Folder"), systemImage: "trash")
            }
        }
    }

    // MARK: - Feed Context Menu

    @ViewBuilder
    private func feedContextMenu(feed: Feed) -> some View {
        Button {
            Task { await store.refreshFeed(feed) }
        } label: {
            Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
        }

        if store.allRead(feedId: feed.id) {
            Button {
                store.markAllAsUnread(feedId: feed.id)
            } label: {
                Label(String(localized: "Mark All as Unread"), systemImage: "circle")
            }
        } else {
            Button {
                store.markAllAsRead(feedId: feed.id)
            } label: {
                Label(String(localized: "Mark All as Read"), systemImage: "checkmark.circle")
            }
        }

        Divider()

        if !store.folders.isEmpty || feed.folderId != nil {
            Menu(String(localized: "Move to Folder")) {
                ForEach(store.folders) { folder in
                    if feed.folderId != folder.id {
                        Button(folder.name) {
                            store.moveFeed(feed.id, toFolder: folder.id)
                        }
                    }
                }

                if feed.folderId != nil {
                    Divider()
                    Button(String(localized: "Remove from Folder")) {
                        store.moveFeed(feed.id, toFolder: nil)
                    }
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            if case .feed(let id) = selectedItem, id == feed.id {
                selectedItem = nil
                selectedArticle = nil
            }
            store.removeFeed(feed)
        } label: {
            Label(String(localized: "Delete Feed"), systemImage: "trash")
        }
    }
}

// MARK: - Folder Stream Row

struct FolderStreamRow: View {

    @Environment(FeedStore.self) private var store
    let folder: Folder

    var body: some View {
        NavigationLink(value: SidebarItem.folder(folder.id)) {
            HStack(spacing: 8) {
                Image(systemName: folder.isSmartFolder ? "sparkles" : "tray.2")
                    .font(.system(size: 13))
                    .foregroundStyle(folder.isSmartFolder ? AppTheme.Colors.accent : Color.secondary)
                    .frame(width: 18)

                Text(folder.isSmartFolder ? String(localized: "Smart Stream") : String(localized: "All in Folder"))
                    .font(.system(size: 13))

                Spacer()

                let count = store.itemsCountForFolder(folder.id)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.Colors.badgeText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(AppTheme.Colors.badgeBackground, in: Capsule())
                }
            }
        }
    }
}

// MARK: - Feed Row

struct FeedRow: View {

    @Environment(FeedStore.self) private var store
    let feed: Feed
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(hostOrURL: feed.url, size: 16)
                .frame(width: 18, height: 18)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(AppAnimation.hover, value: isHovered)

            VStack(alignment: .leading, spacing: 1) {
                Text(feed.title)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)

                if !feed.description.isEmpty {
                    Text(feed.description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            let unread = store.unreadCount(for: feed.id)
            if unread > 0 {
                Text("\(unread)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.Colors.activeBadgeText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(AppTheme.Colors.activeBadgeBackground, in: Capsule())
                    .contentTransition(.numericText())
                    .animation(AppAnimation.bouncy, value: unread)
            }
        }
        .padding(.vertical, 2)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
