import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @Environment(FeedStore.self) private var store
    @State private var selectedSidebarItem: SidebarItem?
    @State private var selectedArticle: FeedItem?
    @State private var showAddFeed = false
    @State private var addFeedTab: AddFeedTab = .customURL
    @State private var showConsole = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage(AppSettingsKeys.isCompactListMode) private var isCompactListMode = false

    // 30 minutes (1800 seconds) auto-refresh timer
    let autoRefreshTimer = Timer.publish(every: 1800, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selectedItem: $selectedSidebarItem, selectedArticle: $selectedArticle)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            } content: {
                FeedListView(selection: selectedSidebarItem, selectedArticle: $selectedArticle)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
            } detail: {
                ArticleDetailView(selectedItem: selectedArticle)
            }

            MiniPlayerView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task {
                        await store.refreshAllFeeds(force: true)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh all feeds")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isLoading)

                Menu {
                    Toggle("Compact Mode", isOn: $isCompactListMode)
                } label: {
                    Label("View Options", systemImage: "slider.horizontal.3")
                }
                .help("List View Options")

                Button {
                    addFeedTab = .customURL
                    showAddFeed = true
                } label: {
                    Label("Add Feed", systemImage: "plus")
                }
                .help("Add new feed")

                Menu {
                    Button {
                        addFeedTab = .curatedCatalog
                        showAddFeed = true
                    } label: {
                        Label("Browse Curated Catalog...", systemImage: "sparkles.rectangle.stack")
                    }

                    Button {
                        addFeedTab = .podcastSearch
                        showAddFeed = true
                    } label: {
                        Label("Find Podcasts (Search Engine)...", systemImage: "waveform.and.magnifyingglass")
                    }

                    Divider()

                    Button {
                        importOPML()
                    } label: {
                        Label("Import OPML...", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        exportOPML()
                    } label: {
                        Label("Export OPML...", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.feeds.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("More Options & OPML")

                Button {
                    showConsole = true
                } label: {
                    Label("Console", systemImage: "terminal")
                }
                .help("Developer Console (Cmd+Option+C)")
                .keyboardShortcut("c", modifiers: [.command, .option])
            }
        }
        .sheet(isPresented: $showAddFeed) {
            AddFeedSheet(initialTab: addFeedTab)
        }
        .sheet(isPresented: $showConsole) {
            ConsoleView()
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
        .onAppear {
            Task {
                await store.refreshAllFeeds()
            }
        }
        .onReceive(autoRefreshTimer) { _ in
            Task {
                await store.refreshAllFeeds()
            }
        }
    }

    // MARK: - OPML Import

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

    // MARK: - OPML Export

    private func exportOPML() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export OPML")
        panel.allowedContentTypes = [UTType(filenameExtension: "opml") ?? .xml]
        panel.nameFieldStringValue = "easyRSS_subscriptions.opml"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let opmlString = store.generateOPMLString()
        do {
            try opmlString.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            store.errorMessage = String(format: String(localized: "Error saving OPML file: %@"), error.localizedDescription)
        }
    }
}
