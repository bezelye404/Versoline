import Testing
import Foundation
@testable import Versoline

@MainActor
struct AnnotationTests {

    private func makeStore() -> (AnnotationStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("annotations-\(UUID().uuidString)", isDirectory: true)
        return (AnnotationStore(directory: directory), directory)
    }

    private let link = "https://news.example.com/story"

    @Test func blockKeysAreStableAndOnlyForText() {
        let paragraph = ArticleBlock.paragraph(AttributedString("A paragraph worth keeping."))
        #expect(paragraph.annotationKey == ArticleBlock.paragraph(AttributedString("A paragraph worth keeping.")).annotationKey)
        #expect(paragraph.annotationKey != ArticleBlock.paragraph(AttributedString("Another paragraph.")).annotationKey)
        #expect(ArticleBlock.code("let x = 1").annotationKey == nil)
        #expect(ArticleBlock.rule.annotationKey == nil)
        #expect(ArticleBlock.paragraph(AttributedString("ab")).annotationKey == nil)
        #expect(ArticleBlock.list(ordered: false, items: [AttributedString("one"), AttributedString("two")]).annotationKey != nil)
    }

    @Test func aHighlightCanBeToggledOnAndOff() {
        let (store, directory) = makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        store.toggleHighlight(link: link, title: "Story", key: "k1", excerpt: "A paragraph")
        #expect(store.byBlock(forArticle: link)["k1"]?.isHighlighted == true)
        #expect(store.hasAnnotations(forArticle: link))
        store.toggleHighlight(link: link, title: "Story", key: "k1", excerpt: "A paragraph")
        #expect(!store.hasAnnotations(forArticle: link))   // nothing left: the annotation is gone
    }

    @Test func aNoteKeepsTheHighlightAndGoesAwayWhenEmptied() {
        let (store, directory) = makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        store.toggleHighlight(link: link, title: "Story", key: "k1", excerpt: "A paragraph")
        store.setNote("  Check this later  ", link: link, title: "Story", key: "k1", excerpt: "A paragraph")
        #expect(store.byBlock(forArticle: link)["k1"]?.note == "Check this later")
        #expect(store.byBlock(forArticle: link)["k1"]?.isHighlighted == true)

        store.setNote("", link: link, title: "Story", key: "k1", excerpt: "A paragraph")
        #expect(store.byBlock(forArticle: link)["k1"]?.note == nil)
        #expect(store.byBlock(forArticle: link)["k1"]?.isHighlighted == true)

        store.toggleHighlight(link: link, title: "Story", key: "k1", excerpt: "A paragraph")
        #expect(store.annotatedLinks.isEmpty)
    }

    @Test func annotationsSurviveARestart() {
        let (store, directory) = makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        store.setNote("Remember", link: link, title: "Story", key: "k1", excerpt: "A paragraph")
        store.flush()

        let reopened = AnnotationStore(directory: directory)
        #expect(reopened.byBlock(forArticle: link)["k1"]?.note == "Remember")
        #expect(reopened.annotatedLinks == [link])
    }

    @Test func aStoreThatWasNeverReadDoesNotOverwriteTheFile() {
        let (store, directory) = makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        store.setNote("Remember", link: link, title: "Story", key: "k1", excerpt: "A paragraph")
        store.flush()

        AnnotationStore(directory: directory).flush()   // loaded nothing, so it must not write
        #expect(AnnotationStore(directory: directory).annotatedLinks == [link])
    }

    @Test func theMarkdownExportQuotesTheTextAndAddsTheNotes() {
        let (store, directory) = makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        store.toggleHighlight(link: link, title: "A Story", key: "k1", excerpt: "First highlighted paragraph")
        store.setNote("My note", link: link, title: "A Story", key: "k2", excerpt: "Second paragraph")
        let markdown = store.markdown(forArticle: link)
        #expect(markdown.hasPrefix("# A Story\n\(link)"))
        #expect(markdown.contains("> First highlighted paragraph"))
        #expect(markdown.contains("> Second paragraph\n\nMy note"))
        #expect(store.markdown(forArticle: "https://other.example.com/").isEmpty)
    }
}
