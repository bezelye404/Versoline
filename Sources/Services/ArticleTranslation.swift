import Foundation
import NaturalLanguage

/// Helpers for translating an article with Apple's on-device Translation framework: recognising the language, and
/// turning an `ArticleDocument` into pieces of text and back. The translation itself runs in the system, on the Mac;
/// nothing about the article is sent to a server or kept after the article is closed.
enum ArticleTranslation {

    /// One piece of text to translate. `id` 0 is the title; the others follow the order of the document.
    struct Piece: Equatable {
        let id: Int
        let text: String
    }

    // MARK: - Language

    /// The language the article is written in, or nil when it is not clear (short or mixed text).
    static func detectedLanguage(of document: ArticleDocument, title: String) -> Locale.Language? {
        var sample = title
        for block in document.blocks {
            let text = block.plainText
            if !text.isEmpty { sample += "\n" + text }
            if sample.count >= 1_200 { break }
        }
        guard sample.count >= 40 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(sample.prefix(1_200)))
        guard let best = recognizer.dominantLanguage,
              (recognizer.languageHypotheses(withMaximum: 1)[best] ?? 0) >= 0.7 else { return nil }
        return Locale.Language(identifier: best.rawValue)
    }

    /// Whether two languages are the same for the purpose of translating (`en-US` and `en-GB` are).
    static func isSameLanguage(_ lhs: Locale.Language, _ rhs: Locale.Language) -> Bool {
        guard let left = lhs.languageCode, let right = rhs.languageCode else { return lhs == rhs }
        return left == right
    }

    /// The language to translate into: the first language the user prefers.
    static var targetLanguage: Locale.Language {
        Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
    }

    // MARK: - Document to pieces and back

    /// Text of the title and of every translatable part of the document, in order. Code, rules and images without a
    /// caption have no text to translate.
    static func pieces(of document: ArticleDocument, title: String) -> [Piece] {
        var pieces: [Piece] = []
        var counter = 0
        func append(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { pieces.append(Piece(id: counter, text: trimmed)) }
            counter += 1
        }
        append(title)
        for block in document.blocks {
            switch block {
            case .heading(_, let text), .paragraph(let text), .quote(let text):
                append(String(text.characters))
            case .list(_, let items):
                for item in items { append(String(item.characters)) }
            case .image(_, _, let caption):
                if let caption { append(caption) }
            case .code, .rule:
                break
            }
        }
        return pieces
    }

    /// The document with the translated text in place of the original wherever there is a translation. Links and bold
    /// or italic runs inside a translated paragraph are lost: translating changes the words they belonged to.
    static func rebuild(_ document: ArticleDocument, with translations: [Int: String]) -> ArticleDocument {
        var counter = 0
        func next() -> Int { defer { counter += 1 }; return counter }
        func replaced(_ original: AttributedString) -> AttributedString {
            let id = next()
            guard let translated = translations[id], !translated.isEmpty else { return original }
            return AttributedString(translated)
        }

        _ = next()   // the title
        var blocks: [ArticleBlock] = []
        for block in document.blocks {
            switch block {
            case .heading(let level, let text): blocks.append(.heading(level: level, text: replaced(text)))
            case .paragraph(let text): blocks.append(.paragraph(replaced(text)))
            case .quote(let text): blocks.append(.quote(replaced(text)))
            case .list(let ordered, let items): blocks.append(.list(ordered: ordered, items: items.map { replaced($0) }))
            case .image(let url, let alt, let caption):
                if let caption {
                    let id = next()
                    blocks.append(.image(url: url, alt: alt, caption: translations[id].flatMap { $0.isEmpty ? nil : $0 } ?? caption))
                } else {
                    blocks.append(block)
                }
            case .code, .rule: blocks.append(block)
            }
        }
        return ArticleDocument(blocks: blocks)
    }
}
