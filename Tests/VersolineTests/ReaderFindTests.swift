import Testing
import Foundation
@testable import Versoline

struct ReaderFindTests {

    private func document() -> ArticleDocument {
        ArticleDocument(blocks: [
            .heading(level: 2, text: AttributedString("Şampiyonluk kutlaması")),
            .paragraph(AttributedString("Takım şampiyon oldu ve şampiyonluk kupası İstanbul'a geldi.")),
            .code("champion = true"),
            .list(ordered: false, items: [AttributedString("Birinci madde"), AttributedString("ŞAMPİYON olmak")]),
            .image(url: URL(string: "https://example.com/a.jpg")!, alt: "", caption: "Şampiyon takım"),
            .paragraph(AttributedString("Hiçbir ilgisi yok.")),
            .table(rows: [[AttributedString("Takım"), AttributedString("Durum")], [AttributedString("Galatasaray"), AttributedString("Şampiyon")]], hasHeader: true),
        ])
    }

    @Test func matchesFindEveryBlockThatContainsTheQuery() {
        let matches = ReaderFind.matches(in: document(), query: "şampiyon")
        #expect(matches == [
            ReaderFind.Match(block: 0, count: 1),
            ReaderFind.Match(block: 1, count: 2),
            ReaderFind.Match(block: 3, count: 1),
            ReaderFind.Match(block: 4, count: 1),
            ReaderFind.Match(block: 6, count: 1),
        ])
    }

    @Test func caseAccentsAndTheTurkishDotlessIDoNotMatter() {
        #expect(ReaderFind.matches(in: document(), query: "SAMPIYON").count == 5)
        #expect(ReaderFind.matches(in: document(), query: "istanbul").map(\.block) == [1])
        #expect(ReaderFind.matches(in: document(), query: "ISTANBUL").map(\.block) == [1])
    }

    @Test func shortAndEmptyQueriesAndCodeGiveNoMatches() {
        #expect(ReaderFind.matches(in: document(), query: "").isEmpty)
        #expect(ReaderFind.matches(in: document(), query: "ş").isEmpty)
        #expect(ReaderFind.matches(in: document(), query: "champion").isEmpty)   // only in a code block
    }

    @Test func highlightingMarksEachMatchAndLeavesTheTextAlone() {
        let text = AttributedString("Takım şampiyon oldu ve şampiyonluk geldi")
        var marked = 0
        let result = ReaderFind.highlighted(text, query: "ŞAMPİYON") { _ in marked += 1 }
        #expect(marked == 2)
        #expect(String(result.characters) == String(text.characters))
        #expect(ReaderFind.highlighted(text, query: "yokkelime") { _ in marked += 100 } == text)
        #expect(marked == 2)
    }
}
