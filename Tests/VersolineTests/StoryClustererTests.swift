import Testing
import Foundation
@testable import Versoline

struct StoryClustererTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ title: String, feed: UUID = UUID(), hoursAgo: Double = 1, snippet: String = "", audio: String? = nil) -> FeedItem {
        FeedItem(feedId: feed, title: title, link: "https://news.example.com/\(UUID().uuidString)",
                 itemDescription: snippet, pubDate: now.addingTimeInterval(-hoursAgo * 3600), audioURL: audio)
    }

    private func stories(_ items: [FeedItem]) -> [StoryClusterer.Story] {
        StoryClusterer.stories(in: items, now: now)
    }

    // MARK: Words

    @Test func stemsDropApostropheSuffixesStopWordsAndShortWords() {
        #expect(StoryClusterer.stems(of: "Yemen'de hükümet güçleri ile Husiler arasında") == ["yemen", "hukum", "gucle", "husil", "arasi"])
        #expect(StoryClusterer.stems(of: "Husilere Husilerin Husiler") == ["husil", "husil", "husil"])
        #expect(StoryClusterer.stems(of: "ON KİŞİ İSTİFA ETTİ") == ["kisi", "istif"])   // upper case, dotted and dotless i
    }

    @Test func numbersAreKept() {
        #expect(StoryClusterer.stems(of: "3 Filistinli öldü").contains("3"))
    }

    // MARK: Stories

    @Test func theSameStoryFromSeveralFeedsIsOneStory() {
        let a = item("İran Petrol Bakanı Paknejad istifa etti")
        let b = item("İran Petrol Bakanı Muhsin Paknejad istifa etti")
        let c = item("Paknejad istifa etti: İran'ın petrol bakanı görevden ayrıldı")
        let other = item("Beşiktaş'ta Serdal Adalı yeniden başkan seçildi")
        let found = stories([a, b, c, other])
        #expect(found.count == 1)
        #expect(Set(found[0].memberIDs) == [a.id, b.id, c.id])
        #expect(found[0].feedCount == 3)
    }

    @Test func differentStoriesStayApart() {
        let items = [
            item("Adana'da 4,1 büyüklüğünde deprem"),
            item("Beşiktaş'ta Serdal Adalı yeniden başkan seçildi"),
            item("Tesla'nın üçüncü çeyrek teslimatları beklentileri aştı"),
        ]
        #expect(stories(items).isEmpty)
    }

    @Test func storiesTooFarApartInTimeAreNotMerged() {
        let early = item("Adana'da şiddetli deprem meydana geldi", hoursAgo: 60)
        let late = item("Adana'da şiddetli deprem meydana geldi", hoursAgo: 1)
        #expect(stories([early, late]).isEmpty)
        #expect(stories([item("Adana'da şiddetli deprem meydana geldi", hoursAgo: 5), late]).count == 1)
    }

    @Test func differentNumbersAreDifferentEvents() {
        let a = item("Maden ocağında göçük: 5 işçi hayatını kaybetti")
        let b = item("Maden ocağında göçük: 1 işçi hayatını kaybetti")
        #expect(stories([a, b]).isEmpty)
        #expect(stories([a, item("Maden ocağında göçük: 5 işçi öldü")]).count == 1)
    }

    @Test func undatedOldAndAudioItemsAreLeftOut() {
        let dated = item("Adana'da şiddetli deprem meydana geldi")
        var undated = item("Adana'da şiddetli deprem meydana geldi")
        undated.pubDate = nil
        let old = item("Adana'da şiddetli deprem meydana geldi", hoursAgo: 200)
        let podcast = item("Adana'da şiddetli deprem meydana geldi", audio: "https://cdn.example.com/a.mp3")
        #expect(stories([dated, undated, old, podcast]).isEmpty)
    }

    @Test func theLeadIsThePreferredFeedsItemOtherwiseTheMostInformative() {
        let pinned = UUID()
        let short = item("Adana'da şiddetli deprem meydana geldi", snippet: "Kısa")
        let long = item("Adana'da şiddetli deprem meydana geldi", snippet: "AFAD'ın verdiği bilgiye göre deprem sabah saatlerinde meydana geldi ve çevre illerden de hissedildi.")
        #expect(stories([short, long])[0].leadID == long.id)

        let favourite = item("Adana'da şiddetli deprem meydana geldi", feed: pinned, snippet: "")
        var settings = StoryClusterer.Settings()
        settings.preferredFeeds = [pinned]
        #expect(StoryClusterer.stories(in: [short, long, favourite], now: now, settings: settings)[0].leadID == favourite.id)
    }

    @Test func manySourcesComeFirst() {
        let big = (0..<4).map { _ in item("İran Petrol Bakanı Paknejad istifa etti") }
        let small = (0..<2).map { _ in item("Beşiktaş'ta Serdal Adalı yeniden başkan seçildi") }
        let found = stories(small + big)
        #expect(found.map(\.feedCount) == [4, 2])
    }

    @Test func aBigLibraryIsFast() {
        let words = ["deprem", "enflasyon", "seçim", "borsa", "maç", "yangın", "toplantı", "yasa", "faiz", "dolar"]
        let items = (0..<1500).map { n in
            item("\(words[n % 10]) haberi \(n % 97) \(words[(n / 7) % 10]) son durum \(n)", hoursAgo: Double(n % 60))
        }
        let start = Date()
        _ = stories(items)
        #expect(Date().timeIntervalSince(start) < 3)
    }
}

@MainActor
struct StoryGroupingStoreTests {

    private func makeStore() throws -> TestStore { try TestStore() }

    /// Lets the background grouping finish (the test yields so the main actor can apply the result).
    private func waitForStories(in store: FeedStore) async {
        let deadline = Date().addingTimeInterval(5)
        while store.storyRefs.isEmpty, Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private func items(in store: FeedStore, feeds: Int = 3, title: String = "İran Petrol Bakanı Paknejad istifa etti") -> [FeedItem] {
        (0..<feeds).map { n in
            let feed = Feed(title: "Feed \(n)", url: "https://feed\(n).example.com/rss")
            store.feeds.append(feed)
            let item = FeedItem(feedId: feed.id, title: title, link: "https://feed\(n).example.com/a", itemDescription: String(repeating: "x", count: n * 10),
                                pubDate: Date().addingTimeInterval(-Double(n) * 600))
            store.items[feed.id] = [item]
            return item
        }
    }

    @Test func listsShowOneRowPerStoryAndKeepTheOpenArticle() async throws {
        let ts = try makeStore(); defer { ts.cleanup() }
        let store = ts.store
        let all = items(in: store)
        let loner = FeedItem(feedId: all[0].feedId, title: "Tesla'nın üçüncü çeyrek teslimatları beklentileri aştı", link: "https://feed0.example.com/b", pubDate: Date())
        store.items[all[0].feedId]?.append(loner)
        store.refreshStories()
        await waitForStories(in: store)

        let list = all + [loner]
        let collapsed = store.collapsingStories(in: list, keeping: nil)
        #expect(collapsed.count == 2)
        #expect(collapsed.contains { $0.id == loner.id })
        #expect(collapsed.contains { $0.id == all[2].id })   // the longest summary leads

        let keptOpen = store.collapsingStories(in: list, keeping: all[0].id)
        #expect(keptOpen.contains { $0.id == all[0].id })
        #expect(store.storySourceCount(for: all[1]) == 3)
        #expect(store.storySourceCount(for: loner) == nil)
        #expect(store.otherItemsInStory(of: all[0]).count == 2)
    }

    @Test func readingTheLeadReadsTheStory() async throws {
        let ts = try makeStore(); defer { ts.cleanup() }
        let store = ts.store
        let all = items(in: store)
        store.refreshStories()
        await waitForStories(in: store)

        store.markAsRead(all[2])
        #expect(store.items.values.flatMap { $0 }.allSatisfy { $0.isRead })
    }

    @Test func topStoriesNeedThreeFeeds() async throws {
        let ts = try makeStore(); defer { ts.cleanup() }
        let store = ts.store
        let all = items(in: store, feeds: 3)
        store.refreshStories()
        await waitForStories(in: store)
        #expect(store.topStoryCount() == 1)
        #expect(store.topStoryItems().map(\.id) == [all[2].id])

        let ts2 = try makeStore(); defer { ts2.cleanup() }
        _ = items(in: ts2.store, feeds: 2)
        ts2.store.refreshStories()
        try? await Task.sleep(for: .milliseconds(500))
        #expect(ts2.store.topStoryCount() == 0)
    }
}
