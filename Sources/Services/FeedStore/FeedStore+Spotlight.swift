import Foundation

extension FeedStore {

    /// Brings Spotlight in line with the bookmarks when the setting is on (a few seconds after the last change, so
    /// several bookmarks in a row cause one update).
    func refreshSpotlight() {
        spotlightTask?.cancel()
        guard SpotlightIndex.isEnabled else { return }
        spotlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            let bookmarks = self.items.values.flatMap { $0 }.filter(\.isBookmarked)
                .map { (item: $0, feedTitle: self.cachedFeedMap[$0.feedId]?.title) }
            SpotlightIndex.reindex(bookmarks)
        }
    }

    /// Turning the setting on indexes the bookmarks; turning it off removes them from Spotlight.
    func spotlightSettingChanged(isOn: Bool) {
        if isOn { refreshSpotlight() } else { spotlightTask?.cancel(); SpotlightIndex.removeAll() }
    }

    /// Opens the article a Spotlight result stands for; returns nil when it is no longer in the library.
    func item(withID id: UUID) -> FeedItem? {
        items.values.lazy.flatMap { $0 }.first { $0.id == id }
    }

    /// The article with this link, for links that open from the widget.
    func item(withLink link: String) -> FeedItem? {
        items.values.lazy.flatMap { $0 }.first { $0.link == link }
    }
}
