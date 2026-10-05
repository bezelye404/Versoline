import Foundation

extension FeedStore {

    // MARK: - Feed Management

    func addFeed(url: String, folderId: UUID? = nil) async {
        var targetURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetURL.isEmpty else { return }

        // Transparently resolve YouTube or Reddit links to valid RSS feeds
        if let resolvedURL = await SocialFeedResolver.shared.smartDetectAndResolve(url: targetURL) {
            targetURL = resolvedURL
        }

        if feeds.contains(where: { $0.url == targetURL }) {
            errorMessage = String(localized: "This feed has already been added.")
            AppLogger.shared.log("Feed already added: \(targetURL)", level: .warning, category: .ui)
            return
        }

        isLoading = true
        errorMessage = nil

        let newFeedId = UUID()
        AppLogger.shared.log("Adding feed: \(targetURL)", level: .info, category: .network)

        do {
            var fetched = try await Self.fetchFeed(url: targetURL, feedId: newFeedId)

            // Not a feed: the address may be a site or an article, so look for the feed it advertises.
            if fetched == nil, let discovered = await FeedDiscovery.findFeed(onPageAt: targetURL), discovered != targetURL {
                AppLogger.shared.log("Found feed for \(targetURL)", level: .info, category: .network, details: discovered)
                if feeds.contains(where: { $0.url == discovered }) {
                    errorMessage = String(localized: "This feed has already been added.")
                    isLoading = false
                    return
                }
                targetURL = discovered
                fetched = try await Self.fetchFeed(url: targetURL, feedId: newFeedId)
            }

            guard let result = fetched else {
                errorMessage = String(localized: "No RSS or Atom feed was found at this address.")
                AppLogger.shared.log("Parse failed for new feed: \(targetURL)", level: .error, category: .parser)
                isLoading = false
                return
            }

            let feed = Feed(
                id: newFeedId,
                title: result.title.isEmpty ? targetURL : result.title,
                url: targetURL,
                description: result.description,
                imageURL: result.imageURL,
                lastUpdated: Date(),
                folderId: folderId,
                updatedAt: Date()
            )

            // Adding is an edit: it must beat an older deletion of the same feed.
            tombstones.removeAll { $0.kind == .feed && $0.key == targetURL.lowercased() }
            feeds.append(feed)
            let cappedItems = result.items.sortedNewestFirst().prefix(Self.maxItemsPerFeed).map { item -> FeedItem in
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
            items[newFeedId] = cappedItems
            isLoading = false
            updateSmartCategoryCaches()
            save()
            SyncCoordinator.shared.notifyFeedAddedOrUpdated(feed)
            refreshStories()
            AppLogger.shared.log("Successfully added feed \"\(feed.title)\" with \(cappedItems.count) items", level: .info, category: .storage)
        } catch {
            let errorMsg = String(format: String(localized: "Failed to load feed: %@"), error.localizedDescription)
            errorMessage = errorMsg
            AppLogger.shared.log(errorMsg, level: .error, category: .network, details: targetURL)
            isLoading = false
        }
    }

    func removeFeed(_ feed: Feed) {
        AppLogger.shared.log("Removing feed \"\(feed.title)\"", level: .info, category: .storage)
        feeds.removeAll { $0.id == feed.id }
        items.removeValue(forKey: feed.id)
        let deletedAt = Date()
        tombstones.removeAll { $0.kind == .feed && $0.key == feed.url.lowercased() }
        tombstones.append(.feed(url: feed.url, at: deletedAt))
        updateSmartCategoryCaches()
        save()
        SyncCoordinator.shared.notifyFeedDeleted(url: feed.url, at: deletedAt)
    }

    func refreshFeed(_ feed: Feed) async {
        isLoading = true
        errorMessage = nil
        AppLogger.shared.log("Refreshing single feed: \"\(feed.title)\"", level: .info, category: .network)

        do {
            let result = try await Self.fetchFeed(url: feed.url, feedId: feed.id, etag: feed.etag, lastModified: feed.lastModifiedHeader)

            guard let result else {
                refreshBackoff[feed.id, default: RefreshBackoff()].recordFailure()
                isLoading = false
                return
            }

            refreshBackoff[feed.id] = nil
            applyFeedUpdate(feedId: feed.id, result: result)
            isLoading = false
            updateSmartCategoryCaches()
            save()
            refreshStories()
        } catch {
            let errorMsg = String(format: String(localized: "Refresh failed: %@"), error.localizedDescription)
            errorMessage = errorMsg
            AppLogger.shared.log(errorMsg, level: .error, category: .network, details: feed.url)
            isLoading = false
        }
    }

    func refreshAllFeeds(force: Bool = false) async {
        guard !feeds.isEmpty else { return }

        // Throttle: don't auto-refresh if refreshed within the last 15 minutes unless forced
        if !force, let last = lastRefreshDate, Date().timeIntervalSince(last) < 900 {
            AppLogger.shared.log("Skipping background refresh: refreshed \(Int(Date().timeIntervalSince(last)))s ago", level: .debug, category: .network)
            return
        }

        isLoading = true
        errorMessage = nil
        AppLogger.shared.log("Starting concurrent refresh for \(feeds.count) feeds (forced: \(force))", level: .info, category: .network)

        // Automatic refreshes leave out feeds that are waiting out a failure; a manual one tries everything.
        let now = Date()
        let feedsToRefresh = force ? self.feeds : self.feeds.filter { !(refreshBackoff[$0.id]?.isWaiting(at: now) ?? false) }
        if feedsToRefresh.count < feeds.count {
            AppLogger.shared.log("Skipping \(feeds.count - feedsToRefresh.count) failing feed(s) until their retry time", level: .debug, category: .network)
        }

        enum Outcome: Sendable {
            case updated(UUID, RSSParser.ParseResult)
            case failed(UUID, countsAgainstFeed: Bool)
        }

        await withTaskGroup(of: Outcome.self) { group in
            var running = 0
            var feedIterator = feedsToRefresh.makeIterator()

            while running > 0 || true {
                // Keep up to 4 concurrent network requests active
                while running < 4, let feed = feedIterator.next() {
                    running += 1
                    group.addTask {
                        do {
                            if feed.url.lowercased().contains("reddit.com") {
                                try? await Task.sleep(for: .milliseconds(500))
                            }
                            if let result = try await Self.fetchFeed(url: feed.url, feedId: feed.id, etag: feed.etag, lastModified: feed.lastModifiedHeader) {
                                return .updated(feed.id, result)
                            }
                            return .failed(feed.id, countsAgainstFeed: true)   // unreadable XML
                        } catch {
                            await AppLogger.shared.log("Error refreshing \"\(feed.title)\": \(error.localizedDescription)", level: .error, category: .network)
                            return .failed(feed.id, countsAgainstFeed: RefreshBackoff.countsAgainstFeed(error))
                        }
                    }
                }

                if running == 0 { break }

                if let finished = await group.next() {
                    running -= 1
                    switch finished {
                    case .updated(let feedId, let result):
                        refreshBackoff[feedId] = nil
                        self.applyFeedUpdate(feedId: feedId, result: result)
                    case .failed(let feedId, let countsAgainstFeed):
                        if countsAgainstFeed { refreshBackoff[feedId, default: RefreshBackoff()].recordFailure() }
                    }
                }
            }
        }

        lastRefreshDate = Date()
        isLoading = false
        invalidateItemCaches()
        updateSmartCategoryCaches()
        save()
        MemoryRelief.trim()
        applyAutomaticReadMarking()
        refreshStories()
        AppLogger.shared.log("All feeds refresh finished", level: .info, category: .network)
    }

    func applyFeedUpdate(feedId: UUID, result: RSSParser.ParseResult) {
        autoreleasepool {
            if result.isNotModified {
                if let index = feeds.firstIndex(where: { $0.id == feedId }) {
                    feeds[index].lastUpdated = Date()
                }
                AppLogger.shared.log("Feed not modified (HTTP 304): skipped parsing & updates", level: .debug, category: .network)
                return
            }

            let existingItems = items[feedId] ?? []
            let rules = FeedRules.stored
            let existingByLink = Dictionary(existingItems.map { ($0.link, $0) }, uniquingKeysWith: { first, _ in first })

            var updatedItems = result.items.map { item in
                var mutableItem = item
                if let existing = existingByLink[item.link] {
                    mutableItem = FeedItem(
                        id: existing.id,
                        feedId: item.feedId,
                        title: item.title,
                        link: item.link,
                        itemDescription: item.itemDescription,
                        pubDate: item.pubDate ?? existing.pubDate,
                        author: item.author ?? existing.author,
                        isRead: existing.isRead,
                        content: item.content,
                        isBookmarked: existing.isBookmarked,
                        audioURL: item.audioURL ?? existing.audioURL,
                        audioDuration: item.audioDuration ?? existing.audioDuration,
                        audioType: item.audioType ?? existing.audioType,
                        audioLength: item.audioLength ?? existing.audioLength,
                        playbackPosition: existing.playbackPosition,
                        isFinished: existing.isFinished,
                        readingMinutes: item.readingMinutes ?? existing.readingMinutes
                    )
                }

                // Save raw content to disk reader cache ONLY for new items so RAM remains lean
                let isNewItem = existingByLink[item.link] == nil
                if isNewItem, !rules.isEmpty { FeedRules.apply(rules, to: &mutableItem) }
                if let rawContent = mutableItem.content, !rawContent.isEmpty {
                    if isNewItem {
                        readerCache.saveToCache(urlString: mutableItem.link, content: rawContent, storeInMemory: false)
                    }
                    mutableItem.content = nil
                }
                if mutableItem.itemDescription.count > 180 {
                    mutableItem.itemDescription = String(mutableItem.itemDescription.prefix(180))
                }

                return mutableItem
            }

            // Always preserve existing bookmarked items that may have fallen off the feed XML
            let updatedLinks = Set(updatedItems.map { $0.link })
            let preservedBookmarks = existingItems.filter { $0.isBookmarked && !updatedLinks.contains($0.link) }
            if !preservedBookmarks.isEmpty {
                updatedItems.append(contentsOf: preservedBookmarks)
            }

            // Memory safety: Enforce maxItemsPerFeed cap for non-bookmarked items
            if updatedItems.count > Self.maxItemsPerFeed {
                let bookmarks = updatedItems.filter { $0.isBookmarked }
                let nonBookmarks = updatedItems
                    .filter { !$0.isBookmarked }
                    .sortedNewestFirst()
                    .prefix(Self.maxItemsPerFeed)
                updatedItems = (Array(nonBookmarks) + bookmarks).sortedNewestFirst()
            } else {
                updatedItems.sort { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            }

            items[feedId] = updatedItems

            if let index = feeds.firstIndex(where: { $0.id == feedId }) {
                feeds[index].lastUpdated = Date()
                if let etag = result.etag {
                    feeds[index].etag = etag
                }
                if let lastModified = result.lastModified {
                    feeds[index].lastModifiedHeader = lastModified
                }
                if !result.title.isEmpty {
                    feeds[index].title = result.title
                }
            }
        }
    }

    // MARK: - Network (nonisolated)

    nonisolated static func fetchFeed(
        url: String,
        feedId: UUID,
        etag: String? = nil,
        lastModified: String? = nil
    ) async throws -> RSSParser.ParseResult? {
        // A little more than the per-feed cap, so the cleanup of non-articles and duplicates still leaves enough.
        try await RSSParser.fetchAndParse(
            url: url, feedId: feedId, etag: etag, lastModified: lastModified, retainItems: maxItemsPerFeed + 30
        )
    }
}
