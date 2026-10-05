import Foundation

/// Finding words inside the article being read: which paragraphs contain them and where, so the reader can tint the
/// matches and step from one paragraph to the next. Case, accents and the Turkish dotless i do not matter.
enum ReaderFind {

    /// Queries shorter than this match too much to be useful.
    static let minimumLength = 2

    struct Match: Equatable {
        let block: Int
        let count: Int
    }

    /// The text of a block as it is searched: one string per visible piece (list items are separate).
    private static func texts(of block: ArticleBlock) -> [String] {
        switch block {
        case .heading(_, let text), .paragraph(let text), .quote(let text): return [String(text.characters)]
        case .list(_, let items): return items.map { String($0.characters) }
        case .image(_, _, let caption): return caption.map { [$0] } ?? []
        case .code, .rule: return []
        }
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        let haystack = StoryClusterer.fold(text)
        guard !needle.isEmpty, haystack.count >= needle.count else { return 0 }
        var count = 0
        var searchStart = haystack.startIndex
        while let found = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            count += 1
            searchStart = found.upperBound
        }
        return count
    }

    static func normalised(_ query: String) -> String {
        StoryClusterer.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The blocks that contain the query, in reading order, with how many times.
    static func matches(in document: ArticleDocument, query: String) -> [Match] {
        let needle = normalised(query)
        guard needle.count >= minimumLength else { return [] }
        var result: [Match] = []
        for (index, block) in document.blocks.enumerated() {
            let count = texts(of: block).reduce(0) { $0 + occurrences(of: needle, in: $1) }
            if count > 0 { result.append(Match(block: index, count: count)) }
        }
        return result
    }

    /// The text with every match given a background. Matching works on folded text; the folding keeps one character
    /// per character, so positions carry over. If it ever did not, the text is returned unchanged.
    static func highlighted(_ text: AttributedString, query: String, apply: (inout AttributedSubstring) -> Void) -> AttributedString {
        let needle = normalised(query)
        guard needle.count >= minimumLength else { return text }
        let plain = String(text.characters)
        let folded = StoryClusterer.fold(plain)
        guard folded.count == plain.count else { return text }

        var result = text
        var searchStart = folded.startIndex
        while let found = folded.range(of: needle, range: searchStart..<folded.endIndex) {
            let from = folded.distance(from: folded.startIndex, to: found.lowerBound)
            let length = folded.distance(from: found.lowerBound, to: found.upperBound)
            let start = result.index(result.startIndex, offsetByCharacters: from)
            let end = result.index(start, offsetByCharacters: length)
            apply(&result[start..<end])
            searchStart = found.upperBound
        }
        return result
    }
}
