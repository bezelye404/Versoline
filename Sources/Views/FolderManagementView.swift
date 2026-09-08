import SwiftUI

struct FolderManagementView: View {

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var initialFolderId: UUID? = nil

    @State private var selectedFolderId: UUID?
    @State private var newFolderName: String = ""
    @State private var showNewFolderAlert: Bool = false
    @State private var renamingFolderId: UUID?
    @State private var renameText: String = ""
    @State private var editingSmartFolder: Folder?
    @State private var smartKeywordsText: String = ""
    @State private var feedFilterText: String = ""

    // Set of feed IDs currently assigned to the selected folder
    @State private var selectedFeedIds: Set<UUID> = []

    init(initialFolderId: UUID? = nil) {
        self.initialFolderId = initialFolderId
        _selectedFolderId = State(initialValue: initialFolderId)
    }

    private var selectedFolder: Folder? {
        store.folders.first(where: { $0.id == selectedFolderId })
    }

    private var filteredFeeds: [Feed] {
        if feedFilterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.feeds
        }
        let query = feedFilterText.lowercased()
        return store.feeds.filter { feed in
            feed.title.lowercased().contains(query) || feed.url.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            HSplitView {
                // Left Panel: Folder List
                foldersSidebar
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

                // Right Panel: Feed Assignment & Management
                feedAssignmentPane
                    .frame(minWidth: 380, idealWidth: 440, maxWidth: .infinity)
            }
            .navigationTitle(String(localized: "Folders & Feeds Management"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 480)
        .onAppear {
            if selectedFolderId == nil, let first = store.folders.first {
                selectFolder(first.id)
            } else if let initial = selectedFolderId {
                selectFolder(initial)
            }
        }
        .alert(String(localized: "New Folder"), isPresented: $showNewFolderAlert) {
            TextField(String(localized: "Folder Name"), text: $newFolderName)
            Button(String(localized: "Add")) {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let created = store.addFolder(name: trimmed)
                    selectFolder(created.id)
                    newFolderName = ""
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                newFolderName = ""
            }
        }
        .alert(String(localized: "Rename Folder"), isPresented: .init(
            get: { renamingFolderId != nil },
            set: { if !$0 { renamingFolderId = nil } }
        )) {
            TextField(String(localized: "Folder Name"), text: $renameText)
            Button(String(localized: "Save")) {
                if let folderId = renamingFolderId,
                   !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    store.renameFolder(folderId, name: renameText.trimmingCharacters(in: .whitespacesAndNewlines))
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
            Button(String(localized: "Save Rules")) {
                guard let folder = editingSmartFolder else { return }
                var parsed: [String] = []
                for part in smartKeywordsText.components(separatedBy: ",") {
                    let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { parsed.append(trimmed) }
                }
                store.updateFolderKeywords(folder.id, keywords: parsed.isEmpty ? nil : parsed)
                editingSmartFolder = nil
                smartKeywordsText = ""
            }
            Button(String(localized: "Clear Rules"), role: .destructive) {
                guard let folder = editingSmartFolder else { return }
                store.updateFolderKeywords(folder.id, keywords: nil)
                editingSmartFolder = nil
                smartKeywordsText = ""
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                editingSmartFolder = nil
                smartKeywordsText = ""
            }
        } message: {
            Text(String(localized: "Enter comma-separated keywords (e.g. apple, swift, ai). Any matching article across all feeds will be aggregated into this folder."))
        }
    }

    // MARK: - Left Panel: Folders Sidebar

    @ViewBuilder
    private var foldersSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Folders"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showNewFolderAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Add new folder"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if store.folders.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "No Folders Yet"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Create Folder")) {
                        showNewFolderAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                List(selection: $selectedFolderId) {
                    ForEach(store.folders) { folder in
                        folderRow(folder)
                            .tag(folder.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectFolder(folder.id)
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        let isSelected = selectedFolderId == folder.id
        let count = store.feedsInFolder(folder.id).count

        HStack(spacing: 8) {
            Image(systemName: folder.isSmartFolder ? "folder.badge.gearshape" : "folder")
                .foregroundStyle(folder.isSmartFolder ? Color.accentColor : Color.secondary)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                if folder.isSmartFolder {
                    Text(String(localized: "Smart Rules Active"))
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }

            Spacer()

            Text("\(count)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 2)
        .contextMenu {
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
                if selectedFolderId == folder.id {
                    if let first = store.folders.first {
                        selectFolder(first.id)
                    } else {
                        selectedFolderId = nil
                        selectedFeedIds.removeAll()
                    }
                }
            } label: {
                Label(String(localized: "Delete Folder"), systemImage: "trash")
            }
        }
    }

    // MARK: - Right Panel: Feed Assignment

    @ViewBuilder
    private var feedAssignmentPane: some View {
        if let folder = selectedFolder {
            VStack(spacing: 0) {
                // Header & Stats
                VStack(spacing: 12) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(folder.name)
                                    .font(.title3.weight(.bold))

                                if folder.isSmartFolder {
                                    Text(String(localized: "Smart"))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.tint)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }

                            Text(String(format: String(localized: "%d feeds assigned to this folder"), selectedFeedIds.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Action Buttons: Select All / Deselect All
                        HStack(spacing: 8) {
                            Button(String(localized: "Select All")) {
                                for feed in filteredFeeds {
                                    selectedFeedIds.insert(feed.id)
                                }
                                persistAssignment(for: folder.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(String(localized: "Deselect All")) {
                                for feed in filteredFeeds {
                                    selectedFeedIds.remove(feed.id)
                                }
                                persistAssignment(for: folder.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    // Feed Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField(String(localized: "Search feeds by name or URL..."), text: $feedFilterText)
                            .textFieldStyle(.plain)
                            .font(.callout)

                        if !feedFilterText.isEmpty {
                            Button {
                                feedFilterText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(7)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                }
                .padding(16)

                Divider()

                // Feeds Checklist
                if store.feeds.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "newspaper")
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "No feeds subscribed yet."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredFeeds.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "No matching feeds found."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredFeeds) { feed in
                            let isChecked = selectedFeedIds.contains(feed.id)
                            feedCheckboxRow(feed: feed, isChecked: isChecked, currentFolder: folder)
                        }
                    }
                    .listStyle(.inset)
                }
            }
        } else {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "folder")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Select a folder from the list to manage its feeds."))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func feedCheckboxRow(feed: Feed, isChecked: Bool, currentFolder: Folder) -> some View {
        Button {
            toggleFeed(feed.id, in: currentFolder.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary.opacity(0.6))

                FaviconView(hostOrURL: feed.url, size: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let folderId = feed.folderId, folderId != currentFolder.id {
                            let otherFolderName = store.folders.first(where: { $0.id == folderId })?.name ?? "Other"
                            Text(String(format: String(localized: "In \"%@\""), otherFolderName))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        } else if feed.folderId == nil {
                            Text(String(localized: "Uncategorized"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                        }

                        if let host = URL(string: feed.url)?.host {
                            Text(host)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Methods

    private func selectFolder(_ folderId: UUID) {
        selectedFolderId = folderId
        let feedsInThisFolder = store.feedsInFolder(folderId)
        selectedFeedIds = Set(feedsInThisFolder.map { $0.id })
    }

    private func toggleFeed(_ feedId: UUID, in folderId: UUID) {
        if selectedFeedIds.contains(feedId) {
            selectedFeedIds.remove(feedId)
        } else {
            selectedFeedIds.insert(feedId)
        }
        persistAssignment(for: folderId)
    }

    private func persistAssignment(for folderId: UUID) {
        store.setFeedsInFolder(folderId, feedIds: selectedFeedIds)
    }
}
