import Testing
import Foundation
@testable import Versoline

@Suite("Command Palette Tests")
struct CommandPaletteTests {

    private let feeds = [
        Feed(title: "Hacker News", url: "https://news.ycombinator.com/rss"),
        Feed(title: "İstanbul Haber", url: "https://haber.example.com/feed"),
        Feed(title: "Swift Blog", url: "https://swift.org/atom.xml"),
    ]
    private let folders = [Folder(name: "Tech News"), Folder(name: "Podcasts I Like")]

    private func entries() -> [PaletteEntry] {
        CommandPalette.entries(feeds: feeds, folders: folders)
    }

    @Test("Entries cover the lists, every folder and feed, and every command")
    func entryCoverage() {
        let all = entries()

        #expect(all.filter { if case .command = $0.kind { return true } else { return false } }.count == PaletteCommand.allCases.count)
        #expect(all.contains { $0.kind == .destination(.feed(feeds[0].id)) })
        #expect(all.contains { $0.kind == .destination(.folder(folders[0].id)) })
        #expect(all.contains { $0.kind == .destination(.unread) })
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test("An empty query returns the first entries up to the limit")
    func emptyQuery() {
        #expect(CommandPalette.filter(entries(), query: "", limit: 5).count == 5)
        #expect(CommandPalette.filter(entries(), query: "   ", limit: 5).count == 5)
    }

    @Test("Matching ignores case and diacritics")
    func caseAndDiacritics() {
        let hits = CommandPalette.filter(entries(), query: "istanbul")

        #expect(hits.first?.title == "İstanbul Haber")
        #expect(CommandPalette.filter(entries(), query: "SWIFT").first?.title == "Swift Blog")
    }

    @Test("Prefix matches rank above word-start matches above substrings")
    func ranking() {
        let sample = [
            PaletteEntry(id: "a", title: "Reading list", subtitle: nil, systemImage: "x", kind: .command(.refresh)),
            PaletteEntry(id: "b", title: "My Read later", subtitle: nil, systemImage: "x", kind: .command(.refresh)),
            PaletteEntry(id: "c", title: "Spread", subtitle: nil, systemImage: "x", kind: .command(.refresh)),
        ]

        let hits = CommandPalette.filter(sample, query: "read")

        #expect(hits.map(\.id) == ["a", "b", "c"])
    }

    @Test("The host name of a feed is searchable")
    func subtitleMatch() {
        let hits = CommandPalette.filter(entries(), query: "ycombinator")

        #expect(hits.first?.title == "Hacker News")
    }

    @Test("No match gives an empty list and the limit is respected")
    func noMatchAndLimit() {
        #expect(CommandPalette.filter(entries(), query: "zzzzzz").isEmpty)
        #expect(CommandPalette.filter(entries(), query: "e", limit: 3).count <= 3)
    }
}
