import Foundation

extension FeedStore {

    // MARK: - Persistence

    struct StorageData: Codable {
        let feeds: [Feed]
        let items: [UUID: [FeedItem]]
        let folders: [Folder]?
        var tombstones: [Tombstone]? = nil
    }

    func flushPendingSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        guard !loadFailed else { return }
        let data = StorageData(feeds: feeds, items: items, folders: folders, tombstones: tombstones)
        Self.performSave(data: data, to: saveURL)
    }

    func save(immediate: Bool = false, updateCounts: Bool = true) {
        if updateCounts {
            updateCachedCounts()
        }

        guard !loadFailed else {
            AppLogger.shared.log("Save skipped: database could not be loaded, keeping the original file untouched", level: .warning, category: .storage)
            return
        }

        let dir = saveURL

        if immediate {
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
            let data = StorageData(feeds: feeds, items: items, folders: folders, tombstones: tombstones)
            Self.performSave(data: data, to: dir)
            return
        }

        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800)) // 800ms debounce
            guard !Task.isCancelled else { return }
            let data = StorageData(feeds: self.feeds, items: self.items, folders: self.folders, tombstones: self.tombstones)
            Task.detached(priority: .utility) {
                Self.performSave(data: data, to: dir)
            }
        }
    }

    nonisolated static func performSave(data: StorageData, to directory: URL) {
        autoreleasepool {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            // Avoid .prettyPrinted for compact file size (~35% reduction) and faster encoding

            do {
                let jsonData = try encoder.encode(data)
                let fileURL = directory.appendingPathComponent("data.json")
                try jsonData.write(to: fileURL, options: .atomic)
                Task { @MainActor in
                    AppLogger.shared.log("Saved database to disk (\(jsonData.count) bytes)", level: .debug, category: .storage)
                }
            } catch {
                Task { @MainActor in
                    AppLogger.shared.log("Save error: \(error.localizedDescription)", level: .error, category: .storage)
                }
            }
        }
    }

    func load() {
        autoreleasepool {
            let fileURL = saveURL.appendingPathComponent("data.json")
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                AppLogger.shared.log("No existing database file found at \(fileURL.path)", level: .info, category: .storage)
                return
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let storage = try decoder.decode(StorageData.self, from: data)
                backupDatabase(fileURL)
                self.feeds = storage.feeds
                self.folders = storage.folders ?? []
                let cutoff = Date().addingTimeInterval(-SyncMerge.tombstoneLifetime)
                self.tombstones = (storage.tombstones ?? []).filter { $0.deletedAt > cutoff }

                var sanitizedItems: [UUID: [FeedItem]] = [:]
                for (feedId, feedItems) in storage.items {
                    let processed = feedItems.map { item -> FeedItem in
                        var cleaned = item
                        // Older versions stored items without a link (podcasts identified only by guid). They all
                        // shared the identity "", so reading or bookmarking one affected the rest. Give each its own.
                        if cleaned.link.isEmpty {
                            cleaned.link = cleaned.audioURL ?? "urn:versoline:item:\(cleaned.id.uuidString)"
                        }
                        if cleaned.title.contains("&") || cleaned.title.contains("<") {
                            cleaned.title = cleaned.title.strippingHTML()
                        }
                        if cleaned.readingMinutes == nil, let rawContent = cleaned.content, !rawContent.isEmpty {
                            cleaned.readingMinutes = FeedItem.estimateReadingMinutes(from: rawContent)
                        }
                        if let rawContent = cleaned.content, !rawContent.isEmpty {
                            readerCache.saveToCache(urlString: cleaned.link, content: rawContent, storeInMemory: false, overwrite: false)
                            cleaned.content = nil
                        }
                        if cleaned.itemDescription.count > 180 {
                            let cleanDesc = cleaned.itemDescription.strippingHTML()
                            cleaned.itemDescription = cleanDesc.count > 180 ? String(cleanDesc.prefix(180)) : cleanDesc
                        }
                        // Clean up any legacy items where an image enclosure was saved as audioURL
                        if !cleaned.isPodcast && cleaned.audioURL != nil {
                            cleaned.audioURL = nil
                            cleaned.audioType = nil
                            cleaned.audioLength = nil
                            cleaned.audioDuration = nil
                        }
                        cleaned.content = nil
                        return cleaned
                    }

                    // Enforce maxItemsPerFeed cap while preserving all bookmarked items
                    if processed.count > Self.maxItemsPerFeed {
                        let bookmarks = processed.filter { $0.isBookmarked }
                        let nonBookmarks = processed
                            .filter { !$0.isBookmarked }
                            .sortedNewestFirst()
                            .prefix(Self.maxItemsPerFeed)
                        sanitizedItems[feedId] = (Array(nonBookmarks) + bookmarks).sortedNewestFirst()
                    } else {
                        sanitizedItems[feedId] = processed.sortedNewestFirst()
                    }
                }
                self.items = sanitizedItems
                self.updateCachedCounts()
                self.updateSmartCategoryCaches()

                let totalItemsCount = self.items.values.reduce(0) { $0 + $1.count }
                AppLogger.shared.log(
                    "Loaded database: \(feeds.count) feeds, \(folders.count) folders, \(totalItemsCount) articles",
                    level: .info,
                    category: .storage
                )
            } catch {
                AppLogger.shared.log("Database load error: \(error.localizedDescription)", level: .error, category: .storage)
                quarantineDatabase(fileURL)
            }
        }
    }

    /// Keeps the last successfully loaded database as `data.json.bak`.
    func backupDatabase(_ fileURL: URL) {
        let backupURL = fileURL.appendingPathExtension("bak")
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: backupURL.path) {
                try fm.removeItem(at: backupURL)
            }
            try fm.copyItem(at: fileURL, to: backupURL)
        } catch {
            AppLogger.shared.log("Could not write database backup: \(error.localizedDescription)", level: .warning, category: .storage)
        }
    }

    /// Copies an unreadable database to `data.json.corrupt-<date>` and blocks saving so
    /// the original is never overwritten by an empty library.
    func quarantineDatabase(_ fileURL: URL) {
        loadFailed = true
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let corruptURL = fileURL.deletingLastPathComponent().appendingPathComponent("data.json.corrupt-\(stamp)")
        do {
            try FileManager.default.copyItem(at: fileURL, to: corruptURL)
            AppLogger.shared.log("Unreadable database preserved at \(corruptURL.lastPathComponent)", level: .error, category: .storage)
        } catch {
            AppLogger.shared.log("Could not preserve unreadable database: \(error.localizedDescription)", level: .error, category: .storage)
        }
        startupRecoveryNotice = String(localized: "Your library could not be read. The original file was kept and nothing will be overwritten. To restore it, put a copy of data.json.bak in the Versoline folder as data.json and restart.")
    }
}
