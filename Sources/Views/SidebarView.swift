import SwiftUI
import Charts

struct SidebarView: View {

    @Environment(FeedStore.self) private var store
    @Environment(\.appTheme) private var theme
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
    @AppStorage("isPinnedExpanded") private var isPinnedExpanded: Bool = true
    @AppStorage("isSmartStreamsExpanded") private var isSmartStreamsExpanded: Bool = true
    @AppStorage("isUncategorizedExpanded") private var isUncategorizedExpanded: Bool = true
    @AppStorage(AppSettingsKeys.showReadingTimeStreams) private var showReadingTimeStreams = false
    @AppStorage(AppSettingsKeys.groupSimilarStories) private var groupSimilarStories = true

    var body: some View {
        List(selection: $selectedItem) {
            librarySection
            pinnedSection
            smartStreamsSection
            foldersSection
            uncategorizedSection
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 16, for: .scrollContent)
        .background(theme.windowBackground)
        .sheet(isPresented: $showAddFeed, onDismiss: {
            CuratedFeedManager.shared.clearMemory()
        }) {
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
        .onChange(of: store.activeSmartCategories) { _, active in
            if case .smartCategory(let cat) = selectedItem, !active.contains(cat) {
                selectedItem = .all
            }
        }
    }

    // MARK: Library Section
    //
    // Four everyday lists, then Podcasts / Videos / Downloaded only when there is such media.
    // Only "Unread" carries a count and a colour; everything else is quiet. Folder management and
    // Reading Insights are menu bar commands, not sidebar rows.

    @ViewBuilder
    private var librarySection: some View {
        Section(String(localized: "Library")) {
            NavigationLink(value: SidebarItem.unread) {
                sidebarRow(
                    title: String(localized: "Unread"),
                    systemImage: "envelope.badge",
                    count: store.totalUnreadCount(),
                    accentColor: theme.unreadDotColor,
                    isProminent: store.totalUnreadCount() > 0
                )
            }

            NavigationLink(value: SidebarItem.today) {
                sidebarRow(title: String(localized: "Today"), systemImage: "clock", count: nil, accentColor: .secondary)
            }

            NavigationLink(value: SidebarItem.calendar) {
                sidebarRow(title: String(localized: "Calendar"), systemImage: "calendar", count: nil, accentColor: .secondary)
            }

            // Only when some story is told by several of the user's feeds.
            if groupSimilarStories, store.topStoryCount() > 0 {
                NavigationLink(value: SidebarItem.topStories) {
                    sidebarRow(title: String(localized: "Top Stories"), systemImage: "square.stack.3d.up", count: nil, accentColor: .secondary)
                }
            }

            NavigationLink(value: SidebarItem.bookmarks) {
                sidebarRow(title: String(localized: "Bookmarks"), systemImage: "star", count: nil, accentColor: .secondary)
            }

            // Only once there is a highlight or a note somewhere.
            if !AnnotationStore.shared.annotatedLinks.isEmpty {
                NavigationLink(value: SidebarItem.highlights) {
                    sidebarRow(title: String(localized: "Highlights"), systemImage: "highlighter", count: nil, accentColor: .secondary)
                }
            }

            NavigationLink(value: SidebarItem.all) {
                sidebarRow(title: String(localized: "All Articles"), systemImage: "tray.full", count: nil, accentColor: .secondary)
            }

            // Media rows only exist when there is media, flat like the other rows (no extra level).
            if store.count(for: .podcasts) > 0 {
                NavigationLink(value: SidebarItem.podcasts) {
                    sidebarRow(title: String(localized: "Podcasts"), systemImage: "headphones", count: nil, accentColor: .secondary)
                }
            }
            if store.count(for: .videos) > 0 {
                NavigationLink(value: SidebarItem.videos) {
                    sidebarRow(title: String(localized: "Videos"), systemImage: "play.rectangle", count: nil, accentColor: .secondary)
                }
            }
            if store.downloadedItemsCount() > 0 {
                NavigationLink(value: SidebarItem.downloaded) {
                    sidebarRow(title: String(localized: "Downloaded"), systemImage: "arrow.down.circle", count: nil, accentColor: .secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var pinnedSection: some View {
        let pinned = store.pinnedFeeds()
        if !pinned.isEmpty {
            Section {
                if isPinnedExpanded {
                    ForEach(pinned) { feed in
                        NavigationLink(value: SidebarItem.feed(feed.id)) {
                            FeedRow(feed: feed, isInsidePinnedSection: true)
                        }
                        .contextMenu { feedContextMenu(feed: feed) }
                        .draggable(feed.id.uuidString)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    .onMove { indices, newOffset in
                        withAnimation(AppAnimation.snappy) {
                            store.reorderPinnedFeeds(fromOffsets: indices, toOffset: newOffset)
                        }
                    }
                }
            } header: {
                Button {
                    AppHaptics.tap()
                    withAnimation(AppAnimation.accordion) {
                        isPinnedExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                            .rotationEffect(.degrees(isPinnedExpanded ? 90 : 0))
                            .animation(AppAnimation.snappy, value: isPinnedExpanded)

                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.accentColor)

                        Text(String(localized: "Pinned"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        headerCount(pinned.count)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                .dropDestination(for: String.self) { items, _ in
                    guard let idStr = items.first, let feedId = UUID(uuidString: idStr) else { return false }
                    withAnimation(AppAnimation.snappy) {
                        store.setFeedPinned(feedId, isPinned: true)
                    }
                    AppHaptics.notifySuccess()
                    return true
                }
            }
        }
    }

    // MARK: Smart Streams Section

    @ViewBuilder
    private var smartStreamsSection: some View {
        let activeCategories = store.activeSmartCategories
        let showQuick = showReadingTimeStreams && store.count(for: .quickReads) > 0
        let showLong = showReadingTimeStreams && store.count(for: .longReads) > 0
        let totalCount = activeCategories.count + (showQuick ? 1 : 0) + (showLong ? 1 : 0)

        if totalCount > 0 {
            Section {
                if isSmartStreamsExpanded {
                    if showQuick {
                        NavigationLink(value: SidebarItem.quickReads) {
                            sidebarRow(
                                title: String(localized: "Quick Reads (<3m)"),
                                systemImage: "bolt",
                                count: store.count(for: .quickReads),
                                accentColor: .secondary
                            )
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if showLong {
                        NavigationLink(value: SidebarItem.longReads) {
                            sidebarRow(
                                title: String(localized: "Deep Reads (>7m)"),
                                systemImage: "book.closed",
                                count: store.count(for: .longReads),
                                accentColor: .secondary
                            )
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    ForEach(activeCategories) { category in
                        NavigationLink(value: SidebarItem.smartCategory(category)) {
                            sidebarRow(
                                title: category.displayName,
                                systemImage: category.systemImage,
                                count: store.smartCategoryCount(category),
                                accentColor: .secondary
                            )
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            } header: {
                Button {
                    AppHaptics.tap()
                    withAnimation(AppAnimation.accordion) {
                        isSmartStreamsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                            .rotationEffect(.degrees(isSmartStreamsExpanded ? 90 : 0))
                            .animation(AppAnimation.snappy, value: isSmartStreamsExpanded)

                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.accentColor)

                        Text(String(localized: "Smart Streams"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        headerCount(totalCount)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
        }
    }

    // MARK: Row Helper

    // Section headers sit outside the list rows' content inset, so their counts need the same trailing space as
    // the badges in the rows below to line up with them.
    private func headerCount(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.trailing, 11)
    }

    @ViewBuilder
    private func sidebarRow(
        title: String,
        systemImage: String,
        count: Int?,
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

            if let count, count > 0 {
                if isProminent {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.activeBadgeText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(theme.activeBadgeBackground, in: Capsule())
                        .animation(AppAnimation.bouncy, value: count)
                } else {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .animation(AppAnimation.bouncy, value: count)
                }
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

    // MARK: Uncategorized Section

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

                        headerCount(uncategorized.count)
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

    // MARK: Folder Header

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
                    .foregroundStyle(folder.isSmartFolder ? theme.accentColor : Color.secondary)

                Text(folder.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if folder.isSmartFolder {
                    Text(String(localized: "Smart"))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.accentColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(theme.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                if feedsCount > 0 {
                    headerCount(feedsCount)
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

    // MARK: Feed Context Menu

    @ViewBuilder
    private func feedContextMenu(feed: Feed) -> some View {
        Button {
            withAnimation(AppAnimation.snappy) {
                store.togglePin(feedId: feed.id)
            }
            AppHaptics.tap()
        } label: {
            Label(
                feed.isPinned ? String(localized: "Unpin Feed") : String(localized: "Pin Feed"),
                systemImage: feed.isPinned ? "pin.slash" : "pin"
            )
        }

        Divider()

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

// MARK: Folder Stream Row
