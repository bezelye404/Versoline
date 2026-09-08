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
        .navigationTitle("easyRSS")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    managingFolderId = nil
                    showFolderManagement = true
                } label: {
                    Label("Folders", systemImage: "folder.badge.gearshape")
                }
                .help("Manage folders and feeds")

                Button {
                    showAddFolder = true
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                .help("Add new folder")
            }
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
        .alert("New Folder", isPresented: $showAddFolder) {
            TextField("Folder Name", text: $newFolderName)
            Button("Add") {
                if !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.addFolder(name: newFolderName.trimmingCharacters(in: .whitespaces))
                    newFolderName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text("Enter a name for the new folder.")
        }
        .alert("Rename Folder", isPresented: .init(
            get: { renamingFolderId != nil },
            set: { if !$0 { renamingFolderId = nil } }
        )) {
            TextField("Folder Name", text: $renameText)
            Button("Save") {
                if let folderId = renamingFolderId,
                   !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.renameFolder(folderId, name: renameText.trimmingCharacters(in: .whitespaces))
                }
                renamingFolderId = nil
                renameText = ""
            }
            Button("Cancel", role: .cancel) {
                renamingFolderId = nil
                renameText = ""
            }
        }
        .alert("Smart Folder Rules", isPresented: .init(
            get: { editingSmartFolder != nil },
            set: { if !$0 { editingSmartFolder = nil } }
        )) {
            TextField("Keywords (comma separated)", text: $smartKeywordsText)
            Button("Save Rules", action: saveSmartFolderRules)
            Button("Clear Rules", role: .destructive, action: clearSmartFolderRules)
            Button("Cancel", role: .cancel) {
                editingSmartFolder = nil
                smartKeywordsText = ""
            }
        } message: {
            Text("Enter comma-separated keywords (e.g. apple, swift, ai). Any matching article across all feeds will be aggregated into this folder.")
        }
        .onChange(of: selectedItem) { _, _ in
            selectedArticle = nil
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var librarySection: some View {
        Section("Library") {
            NavigationLink(value: SidebarItem.all) {
                Label("All Articles", systemImage: "tray.full")
                    .badge(store.totalItemCount)
            }

            NavigationLink(value: SidebarItem.unread) {
                Label("Unread", systemImage: "envelope.badge")
                    .badge(store.totalUnreadCount())
            }

            NavigationLink(value: SidebarItem.today) {
                Label("Today", systemImage: "clock")
                    .badge(store.todayItemsCount())
            }

            NavigationLink(value: SidebarItem.bookmarks) {
                Label("Bookmarks", systemImage: "star")
                    .badge(store.bookmarkCount())
            }

            NavigationLink(value: SidebarItem.podcasts) {
                Label("Podcasts", systemImage: "headphones")
                    .badge(store.podcastCount())
            }

            let downloadedCount = store.downloadedItemsCount()
            if downloadedCount > 0 {
                NavigationLink(value: SidebarItem.downloaded) {
                    Label("Downloaded", systemImage: "arrow.down.circle")
                        .badge(downloadedCount)
                }
            }

            Button {
                managingFolderId = nil
                showFolderManagement = true
            } label: {
                HStack {
                    Label("Folders", systemImage: "folder")
                        .foregroundStyle(.primary)

                    Spacer()

                    if !store.folders.isEmpty {
                        Text("\(store.folders.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        }
    }

    private func isFolderExpanded(_ folderId: UUID) -> Bool {
        let set = Set(collapsedFolderIdsRaw.components(separatedBy: ",").filter { !$0.isEmpty })
        return !set.contains(folderId.uuidString)
    }

    private func toggleFolder(_ folderId: UUID) {
        withAnimation(.easeInOut(duration: 0.18)) {
            var set = Set(collapsedFolderIdsRaw.components(separatedBy: ",").filter { !$0.isEmpty })
            if set.contains(folderId.uuidString) {
                set.remove(folderId.uuidString)
            } else {
                set.insert(folderId.uuidString)
            }
            collapsedFolderIdsRaw = set.joined(separator: ",")
        }
    }

    @ViewBuilder
    private var foldersSection: some View {
        ForEach(store.folders) { folder in
            Section {
                if isFolderExpanded(folder.id) {
                    FolderStreamRow(folder: folder)
                        .dropDestination(for: String.self) { items, _ in
                            guard let idStr = items.first, let feedId = UUID(uuidString: idStr) else { return false }
                            withAnimation(.easeInOut(duration: 0.18)) {
                                store.moveFeed(feedId, toFolder: folder.id)
                            }
                            return true
                        }

                    ForEach(store.feedsInFolder(folder.id)) { feed in
                        NavigationLink(value: SidebarItem.feed(feed.id)) {
                            FeedRow(feed: feed)
                        }
                        .contextMenu { feedContextMenu(feed: feed) }
                        .draggable(feed.id.uuidString)
                    }
                }
            } header: {
                folderHeader(for: folder)
            }
        }
    }

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
                    }
                }
            } header: {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isUncategorizedExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isUncategorizedExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)

                        Image(systemName: "tray")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        Text(store.folders.isEmpty ? String(localized: "Feeds") : String(localized: "Uncategorized"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(uncategorized.count)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                .dropDestination(for: String.self) { items, _ in
                    guard let idStr = items.first, let feedId = UUID(uuidString: idStr) else { return false }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.moveFeed(feedId, toFolder: nil)
                    }
                    return true
                }
            }
        }
    }

    @ViewBuilder
    private var emptyStateSection: some View {
        if store.feeds.isEmpty && store.folders.isEmpty {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)

                    Text("No feeds added yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("Add Feed") {
                            showAddFeed = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
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
        editingSmartFolder = nil
        smartKeywordsText = ""
    }

    private func clearSmartFolderRules() {
        guard let folder = editingSmartFolder else { return }
        store.updateFolderKeywords(folder.id, keywords: nil)
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
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)

                Image(systemName: folder.isSmartFolder ? "folder.badge.gearshape" : "folder")
                    .font(.system(size: 13))
                    .foregroundStyle(folder.isSmartFolder ? Color.accentColor : Color.secondary)

                Text(folder.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                if folder.isSmartFolder {
                    Text("Smart")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                if feedsCount > 0 {
                    Text("\(feedsCount)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .dropDestination(for: String.self) { items, _ in
            guard let idStr = items.first, let feedId = UUID(uuidString: idStr) else { return false }
            withAnimation(.easeInOut(duration: 0.18)) {
                store.moveFeed(feedId, toFolder: folder.id)
            }
            return true
        }
        .contextMenu {
            Button {
                managingFolderId = folder.id
                showFolderManagement = true
            } label: {
                Label("Manage Feeds...", systemImage: "folder.badge.gearshape")
            }

            Divider()

            Button {
                smartKeywordsText = folder.keywords?.joined(separator: ", ") ?? ""
                editingSmartFolder = folder
            } label: {
                Label(folder.isSmartFolder ? "Edit Smart Rules..." : "Set Smart Rules...", systemImage: "sparkles")
            }

            Divider()

            Button {
                renameText = folder.name
                renamingFolderId = folder.id
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                store.removeFolder(folder.id)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    // MARK: - Feed Context Menu

    @ViewBuilder
    private func feedContextMenu(feed: Feed) -> some View {
        Button {
            Task { await store.refreshFeed(feed) }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }

        if store.allRead(feedId: feed.id) {
            Button {
                store.markAllAsUnread(feedId: feed.id)
            } label: {
                Label("Mark All as Unread", systemImage: "circle")
            }
        } else {
            Button {
                store.markAllAsRead(feedId: feed.id)
            } label: {
                Label("Mark All as Read", systemImage: "checkmark.circle")
            }
        }

        Divider()

        // Move to folder submenu
        if !store.folders.isEmpty || feed.folderId != nil {
            Menu("Move to Folder") {
                ForEach(store.folders) { folder in
                    if feed.folderId != folder.id {
                        Button(folder.name) {
                            store.moveFeed(feed.id, toFolder: folder.id)
                        }
                    }
                }

                if feed.folderId != nil {
                    Divider()
                    Button("Remove from Folder") {
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
            Label("Delete Feed", systemImage: "trash")
        }
    }
}

// MARK: - Folder Stream Row

struct FolderStreamRow: View {

    @Environment(FeedStore.self) private var store
    let folder: Folder

    var body: some View {
        NavigationLink(value: SidebarItem.folder(folder.id)) {
            if folder.isSmartFolder {
                Label("Smart Stream", systemImage: "sparkles")
                    .badge(store.itemsCountForFolder(folder.id))
            } else {
                Label("All in Folder", systemImage: "tray.2")
                    .badge(store.itemsCountForFolder(folder.id))
            }
        }
    }
}

// MARK: - Feed Row

struct FeedRow: View {

    @Environment(FeedStore.self) private var store
    let feed: Feed

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(hostOrURL: feed.url, size: 16)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(feed.title)
                    .font(.system(.body, design: .default, weight: .medium))
                    .lineLimit(1)

                if !feed.description.isEmpty {
                    Text(feed.description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            let unread = store.unreadCount(for: feed.id)
            if unread > 0 {
                Text("\(unread)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.secondary, in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}
