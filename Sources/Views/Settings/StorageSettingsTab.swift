import SwiftUI
import AppKit
import WebKit

struct StorageSettingsTab: View {

    @Environment(FeedStore.self) private var store

    @AppStorage(AppSettingsKeys.autoCleanupDays) private var autoCleanupDays = 30
    @State private var showCleanupSuccess = false
    @State private var clearedFavicons = false
    @State private var clearedImageCache = false
    @State private var clearedOfflineCache = false
    @State private var clearedPodcastDownloads = false
    @State private var clearedWebCache = false
    @State private var showResetConfirmation = false
    @State private var resetCompleted = false

    private var formattedImageCacheSize: String {
        let bytes = ImageDownsampleCache.shared.diskCacheSizeBytes
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

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

            Section("Image & Thumbnail Cache") {
                LabeledContent("Cache Size on Disk:", value: formattedImageCacheSize)

                Button("Clear Image & Thumbnail Cache") {
                    ImageDownsampleCache.shared.clearDiskCache()
                    clearedImageCache = true
                }

                if clearedImageCache {
                    Text("Image cache cleared successfully.")
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

            Section("Web & Browser Cache") {
                Button("Clear Web & Browser Disk Cache") {
                    let types = WKWebsiteDataStore.allWebsiteDataTypes()
                    WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
                        DispatchQueue.main.async {
                            clearedWebCache = true
                        }
                    }
                    URLCache.shared.removeAllCachedResponses()
                }

                if clearedWebCache {
                    Text("Web and browser cache cleared successfully.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section("Factory Reset") {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset All Data & Settings...", systemImage: "trash.fill")
                        .foregroundStyle(.red)
                }

                Text("Permanently removes all feeds, articles, folders, bookmarks, offline data, and restores all settings to default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if resetCompleted {
                    Text("All data and settings have been reset.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .padding(10)
        .alert("Reset All Data and Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset Everything", role: .destructive) {
                store.resetAllDataAndSettings()
                resetCompleted = true
            }
        } message: {
            Text("This will permanently delete all feeds, articles, bookmarks, folders, offline downloads, and restore all settings to their default values. This action cannot be undone.")
        }
    }
}

// MARK: - 6. Feed Health Tab
