import SwiftUI
import AppKit

struct SettingsView: View {

    private enum SettingsTab: Hashable {
        case general
        case reader
        case shortcuts
        case filters
        case storage
        case health
    }

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            ReaderSettingsTab()
                .tabItem {
                    Label("Reader", systemImage: "doc.text")
                }
                .tag(SettingsTab.reader)

            ShortcutsSettingsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(SettingsTab.shortcuts)

            FiltersSettingsTab()
                .tabItem {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .tag(SettingsTab.filters)

            StorageSettingsTab()
                .tabItem {
                    Label("Storage", systemImage: "internaldrive")
                }
                .tag(SettingsTab.storage)

            FeedHealthSettingsTab()
                .tabItem {
                    Label("Feed Health", systemImage: "heart.text.square")
                }
                .tag(SettingsTab.health)
        }
        .frame(width: 560, height: 490)
    }
}

// MARK: - 1. General Tab

private struct GeneralSettingsTab: View {

    @AppStorage(AppSettingsKeys.isCompactListMode) private var isCompactListMode = false
    @AppStorage(AppSettingsKeys.showFavicons) private var showFavicons = true
    @AppStorage(AppSettingsKeys.showMenuBarIcon) private var showMenuBarIcon = false
    @AppStorage(AppSettingsKeys.preferredExternalBrowser) private var preferredExternalBrowserRaw = ExternalBrowserOption.systemDefault.rawValue
    @AppStorage(AppSettingsKeys.offlinePrecacheEnabled) private var offlinePrecacheEnabled = false
    @AppStorage(AppSettingsKeys.isContentBlockerEnabled) private var isContentBlockerEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Compact Article List", isOn: $isCompactListMode)
                Text("Hides article snippet summaries in the list to fit more articles on screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show Site Favicons", isOn: $showFavicons)
                Text("Displays website logos next to feeds and article titles for quick visual recognition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
                Text("Keeps an easyRSS status icon in your macOS top menu bar with an unread badge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Web Browser & Privacy") {
                Toggle("Block Ads & Trackers (WebKit Content Blocker)", isOn: $isContentBlockerEnabled)
                Text("Enables native WebKit content blocking for live web browsing. Blocks advertising networks, analytics trackers, and popup scripts while keeping RSS feeds untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("External Browser") {
                Picker("Preferred Browser:", selection: $preferredExternalBrowserRaw) {
                    ForEach(ExternalBrowserOption.allCases) { browser in
                        Text(browser.title).tag(browser.rawValue)
                    }
                }
                Text("Choose which web browser opens when clicking 'Open in Browser'.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Offline Reading") {
                Toggle("Pre-cache Articles for Offline Access", isOn: $offlinePrecacheEnabled)
                Text("Pre-loads readable articles in the background so they are ready even without an internet connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }
}

// MARK: - 2. Reader Tab

private struct ReaderSettingsTab: View {

    @AppStorage(AppSettingsKeys.defaultReadingMode) private var defaultReadingModeRaw = ReadingViewMode.reader.rawValue
    @AppStorage(AppSettingsKeys.readerTheme) private var readerThemeRaw = ReaderTheme.system.rawValue
    @AppStorage(AppSettingsKeys.readerFontFamily) private var readerFontFamilyRaw = ReaderFontFamily.system.rawValue
    @AppStorage(AppSettingsKeys.readerFontSize) private var readerFontSize = 16
    @AppStorage(AppSettingsKeys.readerLineHeight) private var readerLineHeightRaw = ReaderLineHeight.normal.rawValue
    @AppStorage(AppSettingsKeys.autoReaderMode) private var autoReaderMode = false

    var body: some View {
        Form {
            Section("Default Mode") {
                Picker("Default Article View:", selection: $defaultReadingModeRaw) {
                    ForEach(ReadingViewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode.rawValue)
                    }
                }
                Text("Select whether articles initially open in Reader Mode or Web Browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme:", selection: $readerThemeRaw) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }

                Picker("Font Family:", selection: $readerFontFamilyRaw) {
                    ForEach(ReaderFontFamily.allCases) { font in
                        Text(font.title).tag(font.rawValue)
                    }
                }

                Picker("Line Spacing:", selection: $readerLineHeightRaw) {
                    ForEach(ReaderLineHeight.allCases) { lh in
                        Text(lh.title).tag(lh.rawValue)
                    }
                }

                Stepper(value: $readerFontSize, in: 12...32, step: 2) {
                    HStack {
                        Text("Font Size:")
                        Text("\(readerFontSize) px")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Automation") {
                Toggle("Automatically Open in Reader Mode", isOn: $autoReaderMode)
                Text("Automatically extracts full article body for feeds that only provide short summaries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }
}

// MARK: - 3. Shortcuts Tab

private struct ShortcutsSettingsTab: View {

    @AppStorage(AppSettingsKeys.enableSingleKeyShortcuts) private var enableSingleKeyShortcuts = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable Single-Key Navigation", isOn: $enableSingleKeyShortcuts)
                Text("Enables vim-style keyboard navigation (J, K, M, S, O) without holding Command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard Cheat Sheet") {
                shortcutRow(key: "J", description: "Next article")
                shortcutRow(key: "K", description: "Previous article")
                shortcutRow(key: "M", description: "Toggle Read / Unread status")
                shortcutRow(key: "S", description: "Toggle Bookmark (Star)")
                shortcutRow(key: "O / ↩", description: "Open article in preferred web browser")
                shortcutRow(key: "⌘ ⇧ R", description: "Toggle Reader Mode")
                shortcutRow(key: "⌘ R", description: "Refresh all feeds")
                shortcutRow(key: "⌘ ⌥ C", description: "Open Developer Debug Console")
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }

    private func shortcutRow(key: String, description: String) -> some View {
        HStack {
            Text(description)
                .font(.callout)
            Spacer()
            Text(key)
                .font(.system(.callout, design: .monospaced, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }
}

// MARK: - 4. Filters Tab

private struct FiltersSettingsTab: View {

    @AppStorage(AppSettingsKeys.mutedKeywords) private var mutedKeywordsRaw = ""
    @State private var newKeyword = ""

    private var keywords: [String] {
        mutedKeywordsRaw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Articles containing these keywords in their title or summary will be automatically hidden from your article lists.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                TextField("Add keyword to mute (e.g. spoiler, crypto)...", text: $newKeyword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addKeyword()
                    }

                Button("Add") {
                    addKeyword()
                }
                .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if keywords.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No muted keywords yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(keywords, id: \.self) { kw in
                        HStack {
                            Image(systemName: "nosign")
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.8))
                            Text(kw)
                                .font(.callout)
                            Spacer()
                            Button {
                                removeKeyword(kw)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(18)
    }

    private func addKeyword() {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = keywords
        if !current.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            current.append(trimmed)
            mutedKeywordsRaw = current.joined(separator: ",")
        }
        newKeyword = ""
    }

    private func removeKeyword(_ kw: String) {
        var current = keywords
        current.removeAll { $0 == kw }
        mutedKeywordsRaw = current.joined(separator: ",")
    }
}

// MARK: - 5. Storage Tab

private struct StorageSettingsTab: View {

    @Environment(FeedStore.self) private var store

    @AppStorage(AppSettingsKeys.autoCleanupDays) private var autoCleanupDays = 30
    @State private var showCleanupSuccess = false
    @State private var clearedFavicons = false
    @State private var clearedOfflineCache = false
    @State private var clearedPodcastDownloads = false

    private var formattedDatabaseSize: String {
        let bytes = store.databaseSizeBytes
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var formattedOfflineCacheSize: String {
        let bytes = store.offlineCacheSizeBytes
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var formattedPodcastDownloadSize: String {
        let bytes = PodcastDownloadService.shared.totalDownloadSizeBytes
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    var body: some View {
        Form {
            Section("Database Stats") {
                LabeledContent("Feeds:", value: "\(store.feeds.count)")
                LabeledContent("Folders:", value: "\(store.folders.count)")
                LabeledContent("Total Articles:", value: "\(store.totalItemCount)")
                LabeledContent("Database Size on Disk:", value: formattedDatabaseSize)
            }

            Section("Offline Article Cache") {
                LabeledContent("Cache Size on Disk:", value: formattedOfflineCacheSize)

                Button("Clear Offline Article Cache") {
                    store.clearOfflineCache()
                    clearedOfflineCache = true
                }

                if clearedOfflineCache {
                    Text("Offline article cache cleared successfully.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section("Downloaded Podcast Episodes") {
                LabeledContent("Downloads on Disk:", value: formattedPodcastDownloadSize)

                Button("Clear All Downloaded Episodes") {
                    PodcastDownloadService.shared.deleteAllDownloads()
                    clearedPodcastDownloads = true
                }
                .disabled(PodcastDownloadService.shared.totalDownloadSizeBytes == 0)

                if clearedPodcastDownloads {
                    Text("Downloaded episodes cleared successfully.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section("Automatic Cleanup") {
                Picker("Keep Read Articles:", selection: $autoCleanupDays) {
                    Text("Forever (Never clean)").tag(0)
                    Text("7 Days").tag(7)
                    Text("14 Days").tag(14)
                    Text("30 Days").tag(30)
                    Text("90 Days").tag(90)
                }

                Button("Clean Read Articles Older Than Selection Now") {
                    if autoCleanupDays > 0 {
                        store.autoCleanup(olderThanDays: autoCleanupDays)
                        showCleanupSuccess = true
                    }
                }
                .disabled(autoCleanupDays == 0)

                if showCleanupSuccess {
                    Text("Cleanup complete!")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section("Favicon Cache") {
                Button("Clear Favicon Disk Cache") {
                    FaviconService.shared.clearDiskCache()
                    clearedFavicons = true
                }

                if clearedFavicons {
                    Text("Favicon cache cleared successfully.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }
}

// MARK: - 6. Feed Health Tab

private struct FeedHealthSettingsTab: View {

    @Environment(FeedStore.self) private var store
    private var healthService = FeedHealthService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header Action Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Feed Health Diagnostics")
                        .font(.headline)
                    Text("Scan feeds for HTTP errors, dead links, or inactive sources.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if healthService.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                Button {
                    Task {
                        await healthService.scan(store: store)
                    }
                } label: {
                    Label(healthService.isScanning ? "Scanning..." : "Scan Feeds", systemImage: "arrow.clockwise")
                }
                .disabled(healthService.isScanning)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Summary bar if reports exist
            if !healthService.reports.isEmpty {
                let brokenCount = healthService.reports.filter {
                    if case .broken = $0.status { return true }
                    return false
                }.count
                let staleCount = healthService.reports.filter {
                    if case .stale = $0.status { return true }
                    return false
                }.count
                let healthyCount = healthService.reports.filter {
                    if case .healthy = $0.status { return true }
                    return false
                }.count

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("\(healthyCount) Healthy")
                            .font(.caption)
                    }

                    if staleCount > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(.orange).frame(width: 8, height: 8)
                            Text("\(staleCount) Stale (>6 mos)")
                                .font(.caption)
                        }
                    }

                    if brokenCount > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("\(brokenCount) Broken")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }

                        Spacer()

                        Button("Remove All Broken Feeds") {
                            healthService.removeAllBroken(store: store)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    } else {
                        Spacer()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))

                Divider()
            }

            // Report List
            if healthService.reports.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No Diagnostics Run Yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Click 'Scan Feeds' above to test feed accessibility, response times, and identify broken feeds.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(healthService.reports) { report in
                        HStack(spacing: 10) {
                            switch report.status {
                            case .healthy:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .stale(let days):
                                Image(systemName: "clock.badge.exclamationmark.fill")
                                    .foregroundStyle(.orange)
                                    .help("No articles in \(days) days")
                            case .broken(let reason):
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .help(reason)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.feedTitle)
                                    .font(.system(.body, weight: .medium))
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    Text(report.feedURL)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)

                                    if case .stale(let days) = report.status {
                                        Text("• Inactive for \(days) days")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    } else if case .broken(let reason) = report.status {
                                        Text("• \(reason)")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.red)
                                    }
                                }
                            }

                            Spacer()

                            if report.status.isProblematic {
                                Button {
                                    healthService.removeFeed(report, store: store)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove feed")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}
