import SwiftUI

struct SidebarView: View {

    @Environment(FeedStore.self) private var store
    @Binding var selectedItem: SidebarItem?
    @Binding var selectedArticle: FeedItem?
    @State private var showAddFeed = false
    @State private var showAddFolder = false
    @State private var newFolderName = ""
    @State private var renamingFolderId: UUID?
    @State private var renameText = ""

    var body: some View {
        List(selection: $selectedItem) {
            // Smart Lists
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
            }

            // Folders with feeds
            ForEach(store.folders) { folder in
                Section {
                    ForEach(store.feedsInFolder(folder.id)) { feed in
                        NavigationLink(value: SidebarItem.feed(feed.id)) {
                            FeedRow(feed: feed)
                        }
                        .contextMenu { feedContextMenu(feed: feed) }
                    }
                } header: {
                    Text(folder.name)
                        .contextMenu {
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
            }

            // Uncategorized feeds
            let uncategorized = store.uncategorizedFeeds()
            if !uncategorized.isEmpty {
                Section(store.folders.isEmpty ? "Feeds" : "Uncategorized") {
                    ForEach(uncategorized) { feed in
                        NavigationLink(value: SidebarItem.feed(feed.id)) {
                            FeedRow(feed: feed)
                        }
                        .contextMenu { feedContextMenu(feed: feed) }
                    }
                }
            }

            // Empty state
            if store.feeds.isEmpty && store.folders.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "newspaper")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.tertiary)

                        Text("No feeds added yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button("Add Feed") {
                            showAddFeed = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("easyRSS")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
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
        .onChange(of: selectedItem) { _, _ in
            selectedArticle = nil
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

// MARK: - Feed Row

struct FeedRow: View {

    @Environment(FeedStore.self) private var store
    let feed: Feed

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
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
