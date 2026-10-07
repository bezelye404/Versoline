import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import CoreSpotlight

@MainActor
struct ContentView: View {

    @Environment(FeedStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedSidebarItem: SidebarItem?
    @State private var selectedArticle: FeedItem?
    @State private var showAddFeed = false
    @State private var addFeedTab: AddFeedTab = .customURL
    @State private var addFeedInitialURL: String?
    @State private var showFindInArticle = false
    @State private var showConsole = false
    @State private var showShortcutsHelp = false
    @State private var showReadingStats = false
    @State private var showCommandPalette = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showAddFolder = false
    @State private var newFolderName = ""
    @State private var showFolderManagement = false
    @AppStorage(AppSettingsKeys.isCompactListMode) private var isCompactListMode = false
    @AppStorage(AppSettingsKeys.showDockBadge) private var showDockBadge = false
    @AppStorage(AppSettingsKeys.appColorPalette) private var appColorPaletteRaw = AppColorPalette.slate.rawValue

    private var detailShowsPlayingEpisode: Bool {
        guard let playing = AudioPlayerService.shared.currentEpisode, let selected = selectedArticle else { return false }
        return playing.id == selected.id
    }

    @AppStorage(AppSettingsKeys.mutedKeywords) private var mutedKeywordsRaw = ""

    private var widgetState: WidgetState {
        WidgetState(unread: store.totalUnreadCount(), items: store.cachedTotalItemCount, stories: store.storyRefs.count,
                    palette: appColorPaletteRaw, muted: mutedKeywordsRaw)
    }

    private var currentTheme: AppColorPalette {
        AppColorPalette(rawValue: appColorPaletteRaw) ?? .slate
    }

    var body: some View {
        VStack(spacing: 0) {
            if LegacyMigration.shared.showImportNotification {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Text("Versoline (formerly easyRSS): your subscriptions and data were imported.")
                        .font(.subheadline)
                    Spacer()
                    Button {
                        LegacyMigration.shared.dismissNotification()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.12))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color.green.opacity(0.2)),
                    alignment: .bottom
                )
            }

            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selectedItem: $selectedSidebarItem, selectedArticle: $selectedArticle)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                    .background(currentTheme.windowBackground)
            } content: {
                Group {
                    if store.feeds.isEmpty {
                        WelcomeView(
                            addByURL: { addFeedTab = .customURL; showAddFeed = true },
                            browseCatalog: { addFeedTab = .curatedCatalog; showAddFeed = true },
                            importOPML: { importOPML() }
                        )
                    } else if selectedSidebarItem == .calendar {
                        CalendarView(selectedArticle: $selectedArticle)
                    } else {
                        FeedListView(selection: selectedSidebarItem, selectedArticle: $selectedArticle)
                    }
                }
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
                .background(currentTheme.listBackground)
            } detail: {
                ArticleDetailView(selectedItem: selectedArticle, onSelectArticle: { selectedArticle = $0 }, showFind: $showFindInArticle)
                    .background(currentTheme.detailBackground)
            }
            .toolbarBackground(currentTheme.windowBackground, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)

            // The episode page already has the full player, so the bar would only repeat it.
            if !detailShowsPlayingEpisode {
                MiniPlayerView(onNavigateToArticle: { item in
                    if let feed = store.feed(for: item.feedId) {
                        selectedSidebarItem = .feed(feed.id)
                    } else if item.isPodcast {
                        selectedSidebarItem = .podcasts
                    } else if item.isYouTube {
                        selectedSidebarItem = .videos
                    } else {
                        selectedSidebarItem = .all
                    }
                    selectedArticle = item
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AppAnimation.pageReveal, value: detailShowsPlayingEpisode)
        .environment(\.appTheme, currentTheme)
        .tint(currentTheme.accentColor)
        .background(currentTheme.windowBackground)
        .background(WindowThemeBridge(backgroundColor: currentTheme.windowBackground))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    AppHaptics.tap()
                    Task {
                        await store.refreshAllFeeds(force: true)
                    }
                } label: {
                    Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                }
                .help(String(localized: "Refresh all feeds"))
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isLoading)

                // One button for the common case; the arrow lists the other ways to add something.
                // OPML, folders, console and shortcuts live in the menu bar.
                Menu {
                    ForEach([AddFeedTab.customURL, .curatedCatalog, .podcastSearch, .socialFeeds]) { tab in
                        Button {
                            addFeedTab = tab
                            showAddFeed = true
                        } label: {
                            Label(tab.title, systemImage: tab.iconName)
                        }
                    }
                } label: {
                    Label(String(localized: "Add"), systemImage: "plus")
                } primaryAction: {
                    addFeedTab = .customURL
                    showAddFeed = true
                }
                .help(String(localized: "Add a feed"))
            }
        }
        .focusedSceneValue(\.appActions, AppActions(
            addFeed: { tab in addFeedTab = tab; showAddFeed = true },
            newFolder: { showAddFolder = true },
            manageFolders: { showFolderManagement = true },
            importOPML: { importOPML() },
            exportOPML: { exportOPML() },
            exportBackup: { exportBackup() },
            restoreBackup: { restoreBackup() },
            markOlderAsRead: { confirmMarkOlderAsRead(days: $0) },
            showReadingInsights: { showReadingStats = true },
            showShortcuts: { showShortcutsHelp = true },
            showConsole: { showConsole = true },
            toggleFocusMode: { toggleFocusMode() },
            showCommandPalette: { setPalette(true) },
            findInArticle: { showFindInArticle.toggle() },
            hasFeeds: !store.feeds.isEmpty
        ))
        .overlay(alignment: .top) {
            if showCommandPalette {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture { setPalette(false) }
                    CommandPaletteView(
                        entries: CommandPalette.entries(feeds: store.feeds, folders: store.folders),
                        onSelect: { entry in
                            setPalette(false)
                            run(entry)
                        },
                        onDismiss: { setPalette(false) }
                    )
                    .padding(.top, 64)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showReadingStats) {
            ReadingStatsSheet()
        }
        .sheet(isPresented: $showAddFeed, onDismiss: {
            CuratedFeedManager.shared.clearMemory()
        }) {
            AddFeedSheet(initialTab: addFeedTab, initialURL: addFeedInitialURL)
        }
        .sheet(isPresented: $showFolderManagement) {
            FolderManagementView()
        }
        .alert(String(localized: "New Folder"), isPresented: $showAddFolder) {
            TextField(String(localized: "Folder Name"), text: $newFolderName)
            Button(String(localized: "Add")) {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    store.addFolder(name: trimmed)
                    newFolderName = ""
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text(String(localized: "Enter a name for the new folder."))
        }
        .sheet(isPresented: $showConsole) {
            ConsoleView()
        }
        .sheet(isPresented: $showShortcutsHelp) {
            KeyboardShortcutsHelpView()
        }
        .overlay {
            if let video = store.fullscreenVideo {
                FullscreenVideoModal(
                    videoID: video.videoID,
                    title: video.title,
                    link: video.link,
                    onClose: {
                        withAnimation(AppAnimation.pageReveal) {
                            store.fullscreenVideo = nil
                            VideoPlayerService.shared.isFullscreen = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(999)
            }
        }
        .alert(String(localized: "Library Problem"), isPresented: .init(
            get: { store.startupRecoveryNotice != nil },
            set: { if !$0 { store.startupRecoveryNotice = nil } }
        )) {
            Button("OK", role: .cancel) {
                store.startupRecoveryNotice = nil
            }
        } message: {
            if let msg = store.startupRecoveryNotice {
                Text(msg)
            }
        }
        .alert("Error", isPresented: .init(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                store.errorMessage = nil
            }
        } message: {
            if let msg = store.errorMessage {
                Text(msg)
            }
        }
        // Refreshes only while the app is in front: once when it becomes active (the store throttles to
        // every 15 minutes) and then every 30 minutes. `task(id:)` cancels the loop when the app is
        // deactivated or hidden, so nothing polls in the background.
        .onOpenURL { openExternal($0) }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let id = SpotlightIndex.itemID(from: activity.userInfo), let item = store.item(withID: id) else { return }
            selectedSidebarItem = .bookmarks
            selectedArticle = item
        }
        .onChange(of: showAddFeed) { _, isShown in if !isShown { addFeedInitialURL = nil } }
        .task(id: DockBadgeState(count: store.totalUnreadCount(), enabled: showDockBadge)) {
            DockBadge.update(unreadCount: store.totalUnreadCount(), enabled: showDockBadge)
        }
        .task { FeedStore.current = store }
        .task(id: widgetState) {
            // A pause, so a refresh or a run of "mark as read" writes the snapshot once, not for every change.
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            WidgetUpdater.update(store: store)
        }
        // Leaving the app must not strand the widget up to five seconds behind.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            WidgetUpdater.update(store: store)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            WidgetUpdater.update(store: store)
        }
        .task {
            guard Benchmark.isRequested else { return }
            await Benchmark.run(store: store) { item, list, article in
                if list { selectedSidebarItem = .feed(item.feedId) }
                if article { selectedArticle = item }
            } showCalendar: {
                selectedSidebarItem = .calendar
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !Benchmark.skipRefresh else { return }
            await store.refreshAllFeeds()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1800))
                guard !Task.isCancelled else { break }
                await store.refreshAllFeeds()
            }
        }
    }

    // MARK: Focus mode and command palette

    private func toggleFocusMode() {
        withAnimation(AppAnimation.pageReveal) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    private func setPalette(_ visible: Bool) {
        withAnimation(AppAnimation.pageReveal) {
            showCommandPalette = visible
        }
    }

    private func run(_ entry: PaletteEntry) {
        switch entry.kind {
        case .destination(let item):
            selectedSidebarItem = item
        case .command(let command):
            switch command {
            case .refresh: Task { await store.refreshAllFeeds(force: true) }
            case .addFeed: addFeedTab = .customURL; showAddFeed = true
            case .newFolder: showAddFolder = true
            case .importOPML: importOPML()
            case .exportOPML: exportOPML()
            case .exportBackup: exportBackup()
            case .restoreBackup: restoreBackup()
            case .markOlderWeekAsRead: confirmMarkOlderAsRead(days: 7)
            case .findInArticle: showFindInArticle.toggle()
            case .readingInsights: showReadingStats = true
            case .shortcuts: showShortcutsHelp = true
            case .focusMode: toggleFocusMode()
            case .toggleCompact: isCompactListMode.toggle()
            }
        }
    }

    private func importOPML() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select OPML File")
        panel.allowedContentTypes = [
            UTType(filenameExtension: "opml") ?? .xml,
            .xml
        ]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                let data = try Data(contentsOf: url)
                await store.importOPML(data: data)
            } catch {
                store.errorMessage = String(format: String(localized: "Error reading OPML file: %@"), error.localizedDescription)
            }
        }
    }

    private func openExternal(_ url: URL) {
        switch ExternalLink.kind(of: url) {
        case .feed(let address):
            addFeedTab = .customURL
            addFeedInitialURL = address
            showAddFeed = true
        case .opml(let file):
            let alert = NSAlert()
            alert.messageText = String(format: String(localized: "Import subscriptions from %@?"), file.lastPathComponent)
            alert.informativeText = String(localized: "The feeds in the file are added to your library. Feeds you already have are skipped.")
            alert.addButton(withTitle: String(localized: "Import"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            Task {
                do {
                    await store.importOPML(data: try Data(contentsOf: file))
                } catch {
                    store.errorMessage = String(format: String(localized: "Error reading OPML file: %@"), error.localizedDescription)
                }
            }
        case nil:
            openFromWidget(url)
        }
    }

    /// `versoline://open?link=...` from the widget shows that article; `versoline://unread` shows the Unread list.
    private func openFromWidget(_ url: URL) {
        guard url.scheme == WidgetSnapshot.urlScheme else { return }
        if url.host == "unread" {
            selectedSidebarItem = .unread
        } else if let link = WidgetSnapshot.articleLink(from: url), let item = store.item(withLink: link) {
            selectedSidebarItem = .all
            selectedArticle = item
        }
    }

    // MARK: Backup

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Backup")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Versoline Backup \(Date().formatted(.iso8601.year().month().day())).json"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.backupData().write(to: url, options: .atomic)
        } catch {
            store.errorMessage = String(format: String(localized: "Could not save the backup: %@"), error.localizedDescription)
        }
    }

    private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select a Backup")
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let envelope: LibraryBackup.Envelope
        do {
            envelope = try LibraryBackup.read(Data(contentsOf: url))
        } catch {
            store.errorMessage = error.localizedDescription
            return
        }

        let summary = LibraryBackup.summary(of: envelope)
        let alert = NSAlert()
        alert.messageText = String(localized: "Replace your library with this backup?")
        alert.informativeText = String(
            format: String(localized: "The backup from %@ has %d feeds and %d articles. Your current library is kept as data.json.before-restore in the Versoline folder."),
            summary.createdAt.formatted(date: .abbreviated, time: .shortened), summary.feeds, summary.articles
        )
        alert.addButton(withTitle: String(localized: "Restore"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        selectedArticle = nil
        selectedSidebarItem = nil
        store.restoreBackup(envelope)
        selectedSidebarItem = .unread
    }

    private func confirmMarkOlderAsRead(days: Int) {
        let count = store.unreadItems(olderThanDays: days).count
        let alert = NSAlert()
        if count == 0 {
            alert.messageText = String(localized: "Nothing to mark")
            alert.informativeText = String(localized: "There are no unread articles that old.")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
            return
        }
        alert.messageText = String(format: String(localized: "Mark %d articles as read?"), count)
        alert.informativeText = String(format: String(localized: "Unread articles published more than %d days ago will be marked as read. Bookmarks stay as they are."), days)
        alert.addButton(withTitle: String(localized: "Mark as Read"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.markOlderThanAsRead(days: days)
    }

    private func exportOPML() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export OPML")
        panel.allowedContentTypes = [UTType(filenameExtension: "opml") ?? .xml]
        panel.nameFieldStringValue = "versoline_subscriptions.opml"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let opmlString = store.generateOPMLString()
        do {
            try opmlString.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            store.errorMessage = String(format: String(localized: "Error saving OPML file: %@"), error.localizedDescription)
        }
    }
}

/// What the widget shows depends on these; any change schedules a snapshot update.
private struct WidgetState: Hashable {
    let unread: Int
    let items: Int
    let stories: Int
    let palette: String
    let muted: String
}

private struct DockBadgeState: Hashable {
    let count: Int
    let enabled: Bool
}

private struct WindowThemeBridge: NSViewRepresentable {
    let backgroundColor: Color

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            applyWindowTheme(view: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyWindowTheme(view: nsView)
    }

    private func applyWindowTheme(view: NSView) {
        guard let window = view.window else { return }
        window.backgroundColor = NSColor(backgroundColor)
        window.titlebarAppearsTransparent = true
    }
}

