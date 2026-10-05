import Testing
import Foundation
import CoreSpotlight
@testable import Versoline

struct SpotlightIndexTests {

    @Test func aBookmarkBecomesASearchableItemWithItsTitleSummaryAndLink() {
        var item = FeedItem(feedId: UUID(), title: "A story", link: "https://news.example.com/story", itemDescription: "What happened.", pubDate: Date(timeIntervalSince1970: 1_800_000_000))
        item.author = "A. Writer"
        let searchable = SpotlightIndex.searchableItem(for: item, feedTitle: "News")
        #expect(searchable.uniqueIdentifier == item.id.uuidString)
        #expect(searchable.domainIdentifier == SpotlightIndex.domain)
        #expect(searchable.attributeSet.title == "A story")
        #expect(searchable.attributeSet.contentDescription == "What happened.")
        #expect(searchable.attributeSet.contentURL == URL(string: "https://news.example.com/story"))
        #expect(searchable.attributeSet.authorNames == ["A. Writer"])
        #expect(searchable.attributeSet.keywords == ["News"])
    }

    @Test func withoutASummaryTheFeedNameDescribesIt() {
        let item = FeedItem(feedId: UUID(), title: "A story", link: "https://news.example.com/story")
        #expect(SpotlightIndex.searchableItem(for: item, feedTitle: "News").attributeSet.contentDescription == "News")
    }

    @Test func aSpotlightResultMapsBackToItsArticle() {
        let id = UUID()
        #expect(SpotlightIndex.itemID(from: [CSSearchableItemActivityIdentifier: id.uuidString]) == id)
        #expect(SpotlightIndex.itemID(from: [CSSearchableItemActivityIdentifier: "nonsense"]) == nil)
        #expect(SpotlightIndex.itemID(from: nil) == nil)
    }
}
