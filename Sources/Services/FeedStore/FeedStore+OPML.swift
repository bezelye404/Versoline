import Foundation

extension FeedStore {

    // MARK: - OPML Import/Export

    func importOPML(data: Data) async {
        let manager = OPMLManager()
        let opmlFeeds = manager.parse(data: data)

        isLoading = true
        errorMessage = nil
        AppLogger.shared.log("Importing OPML with \(opmlFeeds.count) discovered feed links", level: .info, category: .storage)

        for opmlFeed in opmlFeeds {
            var folderId: UUID?
            if let folderName = opmlFeed.folderName, !folderName.isEmpty {
                if let existing = folders.first(where: { $0.name == folderName }) {
                    folderId = existing.id
                } else {
                    let newFolder = Folder(name: folderName, updatedAt: Date())
                    folders.append(newFolder)
                    folderId = newFolder.id
                }
            }

            guard !feeds.contains(where: { $0.url == opmlFeed.xmlUrl }) else { continue }

            let feedId = UUID()

            do {
                if let result = try await Self.fetchFeed(url: opmlFeed.xmlUrl, feedId: feedId) {
                    let feed = Feed(
                        id: feedId,
                        title: result.title.isEmpty ? opmlFeed.title : result.title,
                        url: opmlFeed.xmlUrl,
                        description: result.description,
                        imageURL: result.imageURL,
                        lastUpdated: Date(),
                        folderId: folderId,
                        updatedAt: Date()
                    )
                    let parsed = result.items.map { item -> FeedItem in
                        var m = item
                        if let rawContent = m.content, !rawContent.isEmpty {
                            readerCache.saveToCache(urlString: m.link, content: rawContent, storeInMemory: false)
                        }
                        if m.itemDescription.count > 180 {
                            m.itemDescription = String(m.itemDescription.prefix(180))
                        }
                        m.content = nil
                        return m
                    }
                    let capped = (parsed.count > Self.maxItemsPerFeed ? Array(parsed.prefix(Self.maxItemsPerFeed)) : parsed)
                        .sortedNewestFirst()
                    tombstones.removeAll { $0.kind == .feed && $0.key == opmlFeed.xmlUrl.lowercased() }
                    feeds.append(feed)
                    items[feedId] = capped
                }
            } catch {
                let feed = Feed(
                    id: feedId,
                    title: opmlFeed.title,
                    url: opmlFeed.xmlUrl,
                    folderId: folderId,
                    updatedAt: Date()
                )
                tombstones.removeAll { $0.kind == .feed && $0.key == opmlFeed.xmlUrl.lowercased() }
                feeds.append(feed)
            }
        }

        isLoading = false
        updateSmartCategoryCaches()
        save()
        SyncCoordinator.shared.notifyFeedsOrFoldersChanged()
        AppLogger.shared.log("OPML import finished. Total feeds now: \(feeds.count)", level: .info, category: .storage)
    }

    func generateOPMLString() -> String {
        OPMLManager.generate(feeds: feeds, folders: folders)
    }
}
