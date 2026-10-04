import Testing
import Foundation
@testable import Versoline

struct BionicReadingTests {
    private func boldText(_ text: AttributedString) -> [String] {
        text.runs.compactMap { run in
            guard run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true else { return nil }
            return String(text[run.range].characters)
        }
    }

    @Test func boldLengthsFollowWordLength() {
        #expect(BionicReading.boldLength(forWordLength: 1) == 0)
        #expect(BionicReading.boldLength(forWordLength: 3) == 1)
        #expect(BionicReading.boldLength(forWordLength: 5) == 2)
        #expect(BionicReading.boldLength(forWordLength: 8) == 3)
        #expect(BionicReading.boldLength(forWordLength: 12) == 6)
    }

    @Test func boldsWordPrefixes() {
        let result = BionicReading.apply(to: AttributedString("Reading is fun"))
        #expect(String(result.characters) == "Reading is fun")
        #expect(boldText(result) == ["Rea", "i", "f"])
    }

    @Test func leavesLinksAndCodeAlone() {
        var text = AttributedString("see this link and code")
        let linkRange = text.range(of: "link")!
        text[linkRange].link = URL(string: "https://example.com")
        let codeRange = text.range(of: "code")!
        text[codeRange].inlinePresentationIntent = .code
        let bold = boldText(BionicReading.apply(to: text))
        #expect(!bold.contains("l"))
        #expect(!bold.contains("c"))
        #expect(bold.contains("s"))
    }

    @Test func keepsExistingEmphasis() {
        var text = AttributedString("important")
        text.inlinePresentationIntent = .emphasized
        let result = BionicReading.apply(to: text)
        let first = result.runs.first
        #expect(first?.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        #expect(first?.inlinePresentationIntent?.contains(.emphasized) == true)
    }

    @Test func handlesTurkishAndEmpty() {
        #expect(String(BionicReading.apply(to: AttributedString("")).characters).isEmpty)
        let result = BionicReading.apply(to: AttributedString("çalışkan öğrenci"))
        #expect(boldText(result) == ["çal", "öğr"])
    }
}
