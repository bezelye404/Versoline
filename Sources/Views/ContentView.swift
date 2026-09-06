import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @Environment(FeedStore.self) private var store
    @State private var selectedSidebarItem: SidebarItem?
    @State private var selectedArticle: FeedItem?
    @State private var showAddFeed = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedItem: $selectedSidebarItem, selectedArticle: $selectedArticle)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            FeedListView(selection: selectedSidebarItem, selectedArticle: $selectedArticle)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
        } detail: {
            ArticleDetailView(selectedItem: selectedArticle)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }

                Button {
                    Task {
                        await store.refreshAllFeeds()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh all feeds")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isLoading)

                Button {
                    showAddFeed = true
                } label: {
                    Label("Add Feed", systemImage: "plus")
                }
                .help("Add new feed")

                Menu {
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
                .help("Import/Export OPML")
            }
        }
        .sheet(isPresented: $showAddFeed) {
            AddFeedSheet()
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
    }

    // MARK: - OPML Import

    private func importOPML() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select OPML File", bundle: .module)
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
                store.errorMessage = String(format: String(localized: "Error reading OPML file: %@", bundle: .module), error.localizedDescription)
            }
        }
    }

    // MARK: - OPML Export

    private func exportOPML() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export OPML", bundle: .module)
        panel.allowedContentTypes = [UTType(filenameExtension: "opml") ?? .xml]
        panel.nameFieldStringValue = "easyRSS_subscriptions.opml"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let opmlString = store.generateOPMLString()
        do {
            try opmlString.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            store.errorMessage = String(format: String(localized: "Error saving OPML file: %@", bundle: .module), error.localizedDescription)
        }
    }
}
