import Testing
import Foundation
@testable import Versoline

struct ArticleTranslationTests {

    private func document() -> ArticleDocument {
        ArticleDocument(blocks: [
            .heading(level: 2, text: AttributedString("A heading")),
            .paragraph(AttributedString("First paragraph.")),
            .code("let x = 1"),
            .image(url: URL(string: "https://example.com/a.jpg")!, alt: "", caption: "A caption"),
            .image(url: URL(string: "https://example.com/b.jpg")!, alt: "", caption: nil),
            .list(ordered: false, items: [AttributedString("one"), AttributedString("two")]),
            .quote(AttributedString("A quote")),
            .rule,
            .paragraph(AttributedString("   ")),
        ])
    }

    @Test func piecesFollowTheDocumentAndSkipCodeRulesAndEmptyText() {
        let pieces = ArticleTranslation.pieces(of: document(), title: "The title")
        #expect(pieces.map(\.text) == ["The title", "A heading", "First paragraph.", "A caption", "one", "two", "A quote"])
        #expect(pieces.map(\.id) == [0, 1, 2, 3, 4, 5, 6])   // code and rules take no id; empty text does, and is left out
    }

    @Test func rebuildPutsTranslationsInPlaceAndKeepsEverythingElse() {
        let translations: [Int: String] = [0: "Başlık", 1: "Bir başlık", 2: "İlk paragraf.", 3: "Bir alt yazı", 4: "bir", 5: "iki", 6: "Bir alıntı"]
        let rebuilt = ArticleTranslation.rebuild(document(), with: translations)
        #expect(rebuilt.blocks.count == document().blocks.count)
        #expect(rebuilt.blocks[0].plainText == "Bir başlık")
        #expect(rebuilt.blocks[1].plainText == "İlk paragraf.")
        #expect(rebuilt.blocks[2] == .code("let x = 1"))
        if case .image(_, _, let caption) = rebuilt.blocks[3] { #expect(caption == "Bir alt yazı") } else { Issue.record("image lost") }
        #expect(rebuilt.blocks[4] == document().blocks[4])
        #expect(rebuilt.blocks[5].plainText == "bir\niki")
        #expect(rebuilt.blocks[6].plainText == "Bir alıntı")
        #expect(rebuilt.blocks[7] == .rule)
    }

    @Test func missingTranslationsKeepTheOriginalText() {
        let rebuilt = ArticleTranslation.rebuild(document(), with: [1: "Bir başlık"])
        #expect(rebuilt.blocks[0].plainText == "Bir başlık")
        #expect(rebuilt.blocks[1].plainText == "First paragraph.")
        #expect(ArticleTranslation.rebuild(document(), with: [:]) == document())
    }

    @Test func recognisesTheLanguageOfAnArticle() {
        let english = ArticleDocument(blocks: [
            .paragraph(AttributedString("The government said on Tuesday that talks with the opposition would resume next week after a long break.")),
            .paragraph(AttributedString("Officials declined to comment on reports that several ministers had threatened to resign over the proposal.")),
        ])
        let turkish = ArticleDocument(blocks: [
            .paragraph(AttributedString("Hükümet salı günü yaptığı açıklamada, muhalefetle yürütülen görüşmelerin uzun bir aradan sonra gelecek hafta yeniden başlayacağını bildirdi.")),
        ])
        #expect(ArticleTranslation.detectedLanguage(of: english, title: "Talks to resume next week")?.languageCode?.identifier == "en")
        #expect(ArticleTranslation.detectedLanguage(of: turkish, title: "Görüşmeler gelecek hafta başlıyor")?.languageCode?.identifier == "tr")
    }

    @Test func shortTextGivesNoLanguage() {
        let tiny = ArticleDocument(blocks: [.paragraph(AttributedString("Hello"))])
        #expect(ArticleTranslation.detectedLanguage(of: tiny, title: "Hi") == nil)
    }

    @Test func regionalVariantsAreTheSameLanguage() {
        #expect(ArticleTranslation.isSameLanguage(Locale.Language(identifier: "en-US"), Locale.Language(identifier: "en-GB")))
        #expect(!ArticleTranslation.isSameLanguage(Locale.Language(identifier: "en"), Locale.Language(identifier: "tr")))
    }
}
