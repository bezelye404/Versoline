import Foundation

// MARK: - Command palette (⌘K): jump to anything, run any command
//
// Pure model: building the entries and matching a query involve no UI, so they are unit-tested.

enum PaletteCommand: String, CaseIterable, Sendable {
    case refresh, addFeed, newFolder, importOPML, exportOPML, exportBackup, restoreBackup, markOlderWeekAsRead, readingInsights, shortcuts, focusMode, toggleCompact

    var title: String {
        switch self {
        case .refresh: return String(localized: "Refresh")
        case .addFeed: return String(localized: "Add Feed...")
        case .newFolder: return String(localized: "New Folder...")
        case .importOPML: return String(localized: "Import OPML...")
        case .exportOPML: return String(localized: "Export OPML...")
        case .exportBackup: return String(localized: "Export Backup...")
        case .restoreBackup: return String(localized: "Restore Backup...")
        case .markOlderWeekAsRead: return String(localized: "Mark Articles Older Than a Week as Read")
        case .readingInsights: return String(localized: "Reading Insights")
        case .shortcuts: return String(localized: "Keyboard Shortcuts")
        case .focusMode: return String(localized: "Focus Mode")
        case .toggleCompact: return String(localized: "Compact Mode")
        }
    }

    var systemImage: String {
        switch self {
        case .refresh: return "arrow.clockwise"
        case .addFeed: return "plus"
        case .newFolder: return "folder.badge.plus"
        case .importOPML: return "square.and.arrow.down"
        case .exportOPML: return "square.and.arrow.up"
        case .exportBackup: return "externaldrive.badge.plus"
        case .restoreBackup: return "externaldrive.badge.checkmark"
        case .markOlderWeekAsRead: return "checkmark.circle"
        case .readingInsights: return "chart.bar.xaxis"
        case .shortcuts: return "keyboard"
        case .focusMode: return "rectangle.expand.vertical"
        case .toggleCompact: return "list.bullet"
        }
    }
}

struct PaletteEntry: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case destination(SidebarItem)
        case command(PaletteCommand)
    }

    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let kind: Kind
}

enum CommandPalette {

    /// Everything the palette can offer for the current library.
    static func entries(feeds: [Feed], folders: [Folder]) -> [PaletteEntry] {
        var result: [PaletteEntry] = []

        let lists: [(SidebarItem, String, String)] = [
            (.unread, String(localized: "Unread"), "envelope.badge"),
            (.today, String(localized: "Today"), "clock"),
            (.topStories, String(localized: "Top Stories"), "square.stack.3d.up"),
            (.bookmarks, String(localized: "Bookmarks"), "star"),
            (.highlights, String(localized: "Highlights"), "highlighter"),
            (.all, String(localized: "All Articles"), "tray.full"),
            (.podcasts, String(localized: "Podcasts"), "headphones"),
            (.videos, String(localized: "Videos"), "play.rectangle"),
        ]
        for (item, title, icon) in lists {
            result.append(PaletteEntry(id: "list-\(title)", title: title, subtitle: nil, systemImage: icon, kind: .destination(item)))
        }
        for folder in folders {
            result.append(PaletteEntry(id: "folder-\(folder.id)", title: folder.name, subtitle: String(localized: "Folder"),
                                       systemImage: "folder", kind: .destination(.folder(folder.id))))
        }
        for feed in feeds {
            result.append(PaletteEntry(id: "feed-\(feed.id)", title: feed.title, subtitle: URL(string: feed.url)?.host,
                                       systemImage: "dot.radiowaves.up.forward", kind: .destination(.feed(feed.id))))
        }
        for command in PaletteCommand.allCases {
            result.append(PaletteEntry(id: "command-\(command.rawValue)", title: command.title, subtitle: nil,
                                       systemImage: command.systemImage, kind: .command(command)))
        }
        return result
    }

    /// Entries matching `query`, best match first. An empty query returns the first `limit` entries.
    /// Matching ignores case and diacritics, using locale-independent folding so that "SWIFT" matches "Swift"
    /// even on a Turkish system ("istanbul" finds "İstanbul"); a title that starts with the
    /// query ranks above one where a word starts with it, which ranks above a plain substring.
    static func filter(_ entries: [PaletteEntry], query: String, limit: Int = 12) -> [PaletteEntry] {
        let needle = fold(query)
        guard !needle.isEmpty else { return Array(entries.prefix(limit)) }

        var scored: [(entry: PaletteEntry, score: Int, index: Int)] = []
        for (index, entry) in entries.enumerated() {
            let title = fold(entry.title)
            let subtitle = fold(entry.subtitle ?? "")
            var score = 0
            if title.hasPrefix(needle) {
                score = 3
            } else if title.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) {
                score = 2
            } else if title.contains(needle) {
                score = 1
            } else if subtitle.contains(needle) {
                score = 1
            }
            if score > 0 { scored.append((entry, score, index)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return scored.prefix(limit).map(\.entry)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ı", with: "i")   // typing "i" should find "ı" as well
            .trimmingCharacters(in: .whitespaces)
    }
}
