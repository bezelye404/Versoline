import Testing
import Foundation
import AppKit
import SwiftUI
@testable import Versoline

@MainActor
struct WidgetSnapshotTests {

    private func item(_ title: String, feed: UUID = UUID(), minutesAgo: Double, read: Bool = false, link: String? = nil, audio: String? = nil) -> FeedItem {
        FeedItem(feedId: feed, title: title, link: link ?? "https://example.com/\(title)", pubDate: Date().addingTimeInterval(-minutesAgo * 60), isRead: read, audioURL: audio)
    }

    private func make(_ items: [FeedItem], refs: [UUID: FeedStore.StoryRef] = [:], muted: [String] = [], limit: Int = 8, palette: String = "slate") -> WidgetSnapshot {
        WidgetUpdater.makeSnapshot(items: items, feedTitles: [:], storyRefs: refs, unreadCount: items.filter { !$0.isRead }.count,
                                   mutedKeywords: muted, palette: palette, limit: limit)
    }

    @Test func unreadArticlesAreListedNewestFirst() {
        let snapshot = make([item("old", minutesAgo: 90), item("new", minutesAgo: 5), item("read", minutesAgo: 1, read: true)])
        #expect(snapshot.headlines.map(\.title) == ["new", "old"])
        #expect(snapshot.unreadCount == 2)
    }

    @Test func topStoriesComeFirst() {
        let top = item("top", minutesAgo: 600)
        let refs = [top.id: FeedStore.StoryRef(story: 0, sources: 3, isLead: true)]
        let snapshot = make([item("fresh", minutesAgo: 1), top], refs: refs)
        #expect(snapshot.headlines.map(\.title) == ["top", "fresh"])
        #expect(snapshot.headlines.first?.isTopStory == true)
    }

    @Test func storiesToldByTwoFeedsOrOlderThanADayAreNotTop() {
        let two = item("two", minutesAgo: 600)
        let stale = item("stale", minutesAgo: 60 * 30)
        let member = item("member", minutesAgo: 700)
        let refs = [
            two.id: FeedStore.StoryRef(story: 0, sources: 2, isLead: true),
            stale.id: FeedStore.StoryRef(story: 1, sources: 4, isLead: true),
            member.id: FeedStore.StoryRef(story: 2, sources: 3, isLead: false),
        ]
        let snapshot = make([two, stale, member], refs: refs)
        #expect(snapshot.headlines.allSatisfy { !$0.isTopStory })
    }

    @Test func mutedKeywordsAndPodcastsAreLeftOut() {
        let snapshot = make([item("Election night", minutesAgo: 1), item("Quiet news", minutesAgo: 2), item("Episode", minutesAgo: 3, audio: "https://example.com/a.mp3")], muted: ["election"])
        #expect(snapshot.headlines.map(\.title) == ["Quiet news"])
    }

    @Test func listIsLimitedAndKeepsTheBestOnes() {
        let snapshot = make((0..<200).map { item("a\($0)", minutesAgo: Double(($0 * 37) % 200)) }, limit: 5)
        #expect(snapshot.headlines.count == 5)
        let dates = snapshot.headlines.compactMap(\.date)
        #expect(dates == dates.sorted(by: >))
        #expect(snapshot.headlines.first?.title == "a0")   // the newest item (0 minutes ago)
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
        // A palette change alone is a change the widget has to show.
        #expect(make([item("two", minutesAgo: 1)], palette: "sepia").write(directory: directory) == true)
    }

    @Test func articleLinksRoundTripThroughTheOpenURL() throws {
        let link = "https://example.com/a?id=1&x=2#frag"
        let url = try #require(WidgetSnapshot.openURL(forArticleLink: link))
        #expect(url.scheme == "versoline")
        #expect(WidgetSnapshot.articleLink(from: url) == link)
        #expect(WidgetSnapshot.articleLink(from: URL(string: "https://example.com/open?link=x")!) == nil)
    }

    @Test func oldSnapshotsWithoutAPaletteStillLoad() throws {
        let json = #"{"generatedAt":"2026-10-07T00:00:00Z","unreadCount":3,"headlines":[]}"#
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetSnapshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(json.utf8).write(to: WidgetSnapshot.fileURL(directory: directory)!)
        #expect(WidgetSnapshot.load(directory: directory)?.unreadCount == 3)
        #expect(WidgetSnapshot.load(directory: directory)?.palette == "slate")
    }
}

/// The widget carries its own copy of the palette colors; these checks keep it in step with the app.
@MainActor
struct WidgetPaletteTests {

    private func resolved(_ color: Color, dark: Bool) -> WidgetPalette.RGB {
        var result = WidgetPalette.RGB(red: 0, green: 0, blue: 0)
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            let ns = NSColor(color).usingColorSpace(.sRGB)!
            result = WidgetPalette.RGB(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent)
        }
        return result
    }

    private func close(_ lhs: WidgetPalette.RGB, _ rhs: WidgetPalette.RGB) -> Bool {
        abs(lhs.red - rhs.red) < 0.011 && abs(lhs.green - rhs.green) < 0.011 && abs(lhs.blue - rhs.blue) < 0.011
    }

    @Test func namesMatchTheAppsPalettes() {
        #expect(WidgetPalette.names == AppColorPalette.allCases.map(\.rawValue))
    }

    @Test func colorsMatchTheApp() {
        for palette in AppColorPalette.allCases {
            let shared = WidgetPalette.named(palette.rawValue)
            #expect(close(shared.background.light, resolved(palette.listBackground, dark: false)), "\(palette) light background")
            #expect(close(shared.background.dark, resolved(palette.listBackground, dark: true)), "\(palette) dark background")
            guard palette != .monochrome else { continue }   // drawn with the primary text color; checked by hand
            #expect(close(shared.accent.light, resolved(palette.accentColor, dark: false)), "\(palette) accent")
            #expect(close(shared.bookmark.light, resolved(palette.bookmarkColor, dark: false)), "\(palette) bookmark")
        }
    }

    @Test func unknownNamesFallBackToSlate() {
        #expect(WidgetPalette.named("nope") == WidgetPalette.named("slate"))
        #expect(WidgetPalette.named(nil) == WidgetPalette.named("slate"))
    }
}
