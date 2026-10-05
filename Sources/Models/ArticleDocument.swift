import Foundation

// MARK: - Article document
//
// A cleaned article as a short list of blocks. The native reader renders these with plain SwiftUI text
// and images, so reading an article needs no web view (and none of WebKit's extra processes).

enum ArticleBlock: Equatable, Sendable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case quote(AttributedString)
    case list(ordered: Bool, items: [AttributedString])
    case code(String)
    case image(url: URL, alt: String, caption: String?)
    case table(rows: [[AttributedString]], hasHeader: Bool)
    case rule

    /// Visible text of a text-bearing block, empty for images and rules.
    var plainText: String {
        switch self {
        case .heading(_, let text), .paragraph(let text), .quote(let text):
            return String(text.characters)
        case .list(_, let items):
            return items.map { String($0.characters) }.joined(separator: "\n")
        case .code(let code):
            return code
        case .table(let rows, _):
            return rows.map { $0.map { String($0.characters) }.joined(separator: "\t") }.joined(separator: "\n")
        case .image, .rule:
            return ""
        }
    }
}

extension ArticleBlock {
    /// A stable key for the text of a heading, paragraph, quote or list, used to attach a highlight or a note to it.
    /// It is a hash of the text, so it survives reloading the article but not an edit of the text by the publisher.
    var annotationKey: String? {
        switch self {
        case .heading, .paragraph, .quote, .list, .table:
            let text = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 3 else { return nil }
            return Self.fnv1a(text)
        case .code, .image, .rule:
            return nil
        }
    }

    private static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }
}

struct ArticleDocument: Equatable, Sendable {
    var blocks: [ArticleBlock]

    var isEmpty: Bool { blocks.isEmpty }

    /// All article text, one blank line between blocks. Used for read-aloud and quote cards.
    var plainText: String {
        blocks.map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    var wordCount: Int {
        plainText.split(whereSeparator: { $0.isWhitespace }).count
    }
}
