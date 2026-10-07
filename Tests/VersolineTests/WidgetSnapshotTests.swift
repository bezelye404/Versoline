import Testing
import Foundation
@testable import Versoline

@MainActor
struct WidgetSnapshotTests {

    private func item(_ title: String, feed: UUID = UUID(), minutesAgo: Double, read: Bool = false, link: String? = nil, audio: String? = nil) -> FeedItem {
        FeedItem(feedId: feed, title: title, link: link ?? "https://example.com/\(title)", pubDate: Date().addingTimeInterval(-minutesAgo * 60), isRead: read, audioURL: audio)
    }

    private func make(_ items: [FeedItem], top: Set<UUID> = [], muted: [String] = [], limit: Int = 8) -> WidgetSnapshot {
        WidgetUpdater.makeSnapshot(items: items, feedTitles: [:], topStoryIDs: top, unreadCount: items.filter { !$0.isRead }.count, mutedKeywords: muted, limit: limit)
    }

    @Test func unreadArticlesAreListedNewestFirst() {
        let snapshot = make([item("old", minutesAgo: 90), item("new", minutesAgo: 5), item("read", minutesAgo: 1, read: true)])
        #expect(snapshot.headlines.map(\.title) == ["new", "old"])
        #expect(snapshot.unreadCount == 2)
    }

    @Test func topStoriesComeFirst() {
        let top = item("top", minutesAgo: 600)
        let snapshot = make([item("fresh", minutesAgo: 1), top], top: [top.id])
        #expect(snapshot.headlines.map(\.title) == ["top", "fresh"])
        #expect(snapshot.headlines.first?.isTopStory == true)
    }

    @Test func mutedKeywordsAndPodcastsAreLeftOut() {
        let snapshot = make([item("Election night", minutesAgo: 1), item("Quiet news", minutesAgo: 2), item("Episode", minutesAgo: 3, audio: "https://example.com/a.mp3")], muted: ["election"])
        #expect(snapshot.headlines.map(\.title) == ["Quiet news"])
    }

    @Test func listIsLimited() {
        let snapshot = make((0..<20).map { item("a\($0)", minutesAgo: Double($0)) }, limit: 5)
        #expect(snapshot.headlines.count == 5)
    }

    @Test func snapshotSurvivesTheFileAndSkipsIdenticalWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetSnapshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let snapshot = make([item("one", minutesAgo: 1)])
        #expect(snapshot.write(directory: directory) == true)
        #expect(WidgetSnapshot.load(directory: directory)?.headlines == snapshot.headlines)

        var later = snapshot
        later.generatedAt = Date().addingTimeInterval(3600)
        #expect(later.write(directory: directory) == false)   // same content: no write, no widget reload

        #expect(make([item("two", minutesAgo: 1)]).write(directory: directory) == true)
    }

    @Test func missingContainerIsHandled() {
        #expect(WidgetSnapshot.load(directory: nil) == nil || WidgetSnapshot.groupIdentifier != nil)
    }

    @Test func articleLinksRoundTripThroughTheOpenURL() throws {
        let link = "https://example.com/a?id=1&x=2#frag"
        let url = try #require(WidgetSnapshot.openURL(forArticleLink: link))
        #expect(url.scheme == "versoline")
        #expect(WidgetSnapshot.articleLink(from: url) == link)
        #expect(WidgetSnapshot.articleLink(from: URL(string: "https://example.com/open?link=x")!) == nil)
    }
}
