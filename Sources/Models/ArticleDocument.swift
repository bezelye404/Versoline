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
        case .image, .rule:
            return ""
        }
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
