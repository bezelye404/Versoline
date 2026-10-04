import Testing
import Foundation
@testable import Versoline

/// Real news pages (Oct 2026) reduced to their structure by `scripts/make-reader-fixture.py`: the article paragraphs
/// are replaced by `ART-nn`, other long text by `OTH-nn`, short text (menus, buttons, bylines) is kept. A fixture
/// passes when every article paragraph survives, no other long text does, and known page furniture is gone.
struct ReaderFixtureTests {

    struct Case {
        let name: String
        /// Short strings that are page furniture on that site and must not reach the reader.
        let furniture: [String]
        /// Article-range paragraphs that are not article text after all and are rightly dropped.
        var notArticle: Set<String> = []
        /// Other long text that is kept on purpose (footnotes and the author box printed under the text).
        var allowedOther: Set<String> = []
    }

    static let cases: [Case] = [
        Case(name: "aa", furniture: ["Haberi Paylaş"]),
        // ART-08 and ART-09 are "related story" cards inside the article.
        Case(name: "bbc", furniture: ["Haberin sonu", "En çok okunanlar", "Okuma süresi", "Bildirdiği yer", "atlayın"], notArticle: ["ART-08", "ART-09"]),
        Case(name: "bianet", furniture: [], allowedOther: ["OTH-03", "OTH-04", "OTH-05", "OTH-06"]),
        Case(name: "birgun", furniture: []),
        Case(name: "diken", furniture: []),
        Case(name: "ensonhaber", furniture: []),
        Case(name: "hurriyet", furniture: ["Takip Edin", "anında haberdar", "Oluşturulma Tarihi", "tercih edilen"]),
        Case(name: "odatv", furniture: ["Odatv.com"]),
        Case(name: "sabah", furniture: ["Haber Girişi"]),
        Case(name: "sozcu", furniture: ["internet sitesinde yayınlanan"]),
        Case(name: "tg", furniture: ["Kaydet"]),
        Case(name: "trt", furniture: []),
    ]

    private static func fixture(_ name: String) throws -> String {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try String(contentsOf: directory.appendingPathComponent("\(name).html"), encoding: .utf8)
    }

    private static func markers(in text: String, prefix: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: "\(prefix)-\\d+") else { return [] }
        let ns = text as NSString
        return Set(regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) })
    }

    @Test(arguments: cases)
    func keepsTheArticleAndNothingElse(_ testCase: Case) throws {
        let page = try Self.fixture(testCase.name)
        let expected = Self.markers(in: page, prefix: "ART").subtracting(testCase.notArticle)
        #expect(!expected.isEmpty)

        let content = ArticleParser.mainContentHTML(from: page)
        #expect(content != nil, "\(testCase.name): no article found")
        let document = ArticleParser.parse(html: content ?? "", baseURL: URL(string: "https://example.com/"))
        // Image captions count as article text.
        let captions = document.blocks.compactMap { block -> String? in
            if case .image(_, _, let caption) = block { return caption }
            return nil
        }
        let text = ([document.plainText] + captions).joined(separator: "\n")

        let found = Self.markers(in: text, prefix: "ART")
        #expect(found == expected, "\(testCase.name): missing \(expected.subtracting(found).sorted()), extra \(found.subtracting(expected).sorted())")
        let leaked = Self.markers(in: text, prefix: "OTH").subtracting(testCase.allowedOther)
        #expect(leaked.isEmpty, "\(testCase.name): other page text leaked: \(leaked.sorted())")
        for item in testCase.furniture {
            #expect(!text.contains(item), "\(testCase.name): furniture kept: \(item)")
        }
    }
}

extension ReaderFixtureTests.Case: CustomTestStringConvertible {
    var testDescription: String { name }
}
