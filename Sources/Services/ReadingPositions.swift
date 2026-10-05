import Foundation

/// Where the reader was in each long article, so reopening it continues there. Only the most recent articles are
/// remembered (a few hundred small entries in the preferences), nothing leaves the Mac, and an article read to its end
/// or left near the top is forgotten.
@MainActor
final class ReadingPositions {

    static let shared = ReadingPositions()

    private struct Entry: Codable, Equatable {
        let link: String
        let block: Int
    }

    private let defaults: UserDefaults
    private let key: String
    private let limit: Int
    /// Oldest first; the last entry is the most recently read.
    private var entries: [Entry]

    init(defaults: UserDefaults = .standard, key: String = "readingPositions", limit: Int = 300) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
        entries = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    func position(for link: String) -> Int? {
        entries.last { $0.link == link }?.block
    }

    /// Remembers that block `block` of `blockCount` is at the top of the window.
    func save(link: String, block: Int, blockCount: Int) {
        entries.removeAll { $0.link == link }
        // Near the start or at the end there is nothing to come back to.
        if block >= 3, block < blockCount - 2 {
            entries.append(Entry(link: link, block: block))
            if entries.count > limit { entries.removeFirst(entries.count - limit) }
        }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }

    var count: Int { entries.count }
}
