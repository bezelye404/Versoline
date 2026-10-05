import Foundation
@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers

/// Puts bookmarked articles in Spotlight (Settings > General, off by default). The index is Spotlight's own, on this
/// Mac; Versoline keeps nothing extra and sends nothing anywhere. Only titles, summaries and links of bookmarks go in.
enum SpotlightIndex {

    static var domain: String { "\(AppInfo.identifier).bookmarks" }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppSettingsKeys.spotlightBookmarks)
    }

    /// What Spotlight shows and searches for one article.
    static func searchableItem(for item: FeedItem, feedTitle: String?) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = item.title
        attributes.contentDescription = item.snippet.isEmpty ? feedTitle : item.snippet
        attributes.contentURL = URL(string: item.link)
        attributes.authorNames = item.author.map { [$0] }
        attributes.contentCreationDate = item.pubDate
        attributes.keywords = [feedTitle].compactMap { $0 }
        let searchable = CSSearchableItem(uniqueIdentifier: item.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
        searchable.expirationDate = .distantFuture
        return searchable
    }

    /// The article a Spotlight result stands for.
    static func itemID(from activityInfo: [AnyHashable: Any]?) -> UUID? {
        (activityInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(UUID.init(uuidString:))
    }

    /// Makes the index match the bookmarks: the domain is cleared and the current bookmarks are added again.
    static func reindex(_ bookmarks: [(item: FeedItem, feedTitle: String?)]) {
        let index = CSSearchableIndex.default()
        let searchables = bookmarks.map { searchableItem(for: $0.item, feedTitle: $0.feedTitle) }
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            guard !searchables.isEmpty else { return }
            index.indexSearchableItems(searchables) { _ in }
        }
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }
}
