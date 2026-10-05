import Testing
import Foundation
@testable import Versoline

@MainActor
struct FeedRuleTests {

    private let feedA = UUID()
    private let feedB = UUID()

    private func item(_ title: String, feed: UUID, snippet: String = "") -> FeedItem {
        FeedItem(feedId: feed, title: title, link: "https://news.example.com/\(UUID().uuidString)", itemDescription: snippet)
    }

    @Test func rulesMatchTitleOrSummaryIgnoringCaseAccentsAndTurkishI() {
        let rule = FeedRule(feedID: nil, keyword: "ŞAMPİYON", action: .markRead)
        #expect(rule.matches(item("Galatasaray şampiyon oldu", feed: feedA)))
        #expect(rule.matches(item("Maç sonu", feed: feedA, snippet: "SAMPIYON kim olacak")))
        #expect(!rule.matches(item("Borsa güne yükselişle başladı", feed: feedA)))
        #expect(!FeedRule(feedID: nil, keyword: "   ", action: .markRead).matches(item("anything", feed: feedA)))
    }

    @Test func aRuleForOneFeedLeavesTheOthersAlone() {
        let rule = FeedRule(feedID: feedA, keyword: "transfer", action: .bookmark)
        #expect(rule.matches(item("Transfer haberi", feed: feedA)))
        #expect(!rule.matches(item("Transfer haberi", feed: feedB)))
    }

    @Test func applyingMarksReadAndBookmarksOnce() {
        let rules = [FeedRule(feedID: nil, keyword: "spoiler", action: .markRead), FeedRule(feedID: nil, keyword: "deprem", action: .bookmark)]
        var spoiler = item("Dizi spoiler içerir", feed: feedA)
        #expect(FeedRules.apply(rules, to: &spoiler))
        #expect(spoiler.isRead && !spoiler.isBookmarked)
        #expect(!FeedRules.apply(rules, to: &spoiler))   // nothing left to change

        var quake = item("Deprem oldu", feed: feedA)
        #expect(FeedRules.apply(rules, to: &quake))
        #expect(quake.isBookmarked && !quake.isRead)
    }

    @Test func rulesRoundTripThroughTheirStoredForm() {
        let rules = [FeedRule(feedID: feedA, keyword: "x", action: .bookmark), FeedRule(feedID: nil, keyword: "y", action: .markRead)]
        #expect(FeedRules.decode(FeedRules.encode(rules)) == rules)
        #expect(FeedRules.decode("").isEmpty)
        #expect(FeedRules.decode("not json").isEmpty)
    }

    @Test func existingArticlesCanBeSwept() throws {
        let ts = try TestStore(); defer { ts.cleanup() }
        let feed = Feed(title: "News", url: "https://news.example.com/rss")
        ts.store.feeds.append(feed)
        ts.store.items[feed.id] = [item("Dizi spoiler içerir", feed: feed.id), item("Normal haber", feed: feed.id)]
        ts.store.updateCachedCounts()

        UserDefaults.standard.set(FeedRules.encode([FeedRule(feedID: nil, keyword: "spoiler", action: .markRead)]), forKey: FeedRules.defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: FeedRules.defaultsKey) }

        #expect(ts.store.applyRulesToExistingArticles() == 1)
        #expect(ts.store.totalUnreadCount() == 1)
        #expect(ts.store.applyRulesToExistingArticles() == 0)
    }

    @Test func newArticlesGetTheRulesWhenTheyArrive() throws {
        let ts = try TestStore(); defer { ts.cleanup() }
        let feed = Feed(title: "News", url: "https://news.example.com/rss")
        ts.store.feeds.append(feed)
        UserDefaults.standard.set(FeedRules.encode([FeedRule(feedID: feed.id, keyword: "deprem", action: .bookmark)]), forKey: FeedRules.defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: FeedRules.defaultsKey) }

        let arrived = [item("Deprem oldu", feed: feed.id), item("Borsa", feed: feed.id)]
        ts.store.applyFeedUpdate(feedId: feed.id, result: RSSParser.ParseResult(title: "News", description: "", imageURL: nil, items: arrived))

        let stored = try #require(ts.store.items[feed.id])
        #expect(stored.first { $0.title == "Deprem oldu" }?.isBookmarked == true)
        #expect(stored.first { $0.title == "Borsa" }?.isBookmarked == false)
    }
}
