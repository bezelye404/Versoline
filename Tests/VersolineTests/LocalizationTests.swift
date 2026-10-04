import Testing
import Foundation
@testable import Versoline

@Suite("Localization Tests")
struct LocalizationTests {

    private func strings(for language: String) throws -> [String: String] {
        let path = try #require(
            Bundle(for: BundleToken.self).path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language)
                ?? Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language)
        )
        return try #require(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    private func specifiers(in string: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:l{0,2}[dfiu]|@)"#)
        let range = NSRange(string.startIndex..., in: string)
        return regex.matches(in: string, range: range).compactMap { Range($0.range, in: string).map { String(string[$0]) } }.sorted()
    }

    @Test("English and Turkish define the same keys")
    func sameKeys() throws {
        let en = try strings(for: "en")
        let tr = try strings(for: "tr")

        #expect(Set(en.keys).subtracting(tr.keys).sorted() == [])
        #expect(Set(tr.keys).subtracting(en.keys).sorted() == [])
        #expect(en.count > 400)
    }

    @Test("Format specifiers match between languages")
    func sameSpecifiers() throws {
        let en = try strings(for: "en")
        let tr = try strings(for: "tr")

        let mismatched = try en.keys.filter { key in
            guard let english = en[key], let turkish = tr[key] else { return false }
            return try specifiers(in: english) != specifiers(in: turkish)
        }
        #expect(mismatched.sorted() == [])
    }

    @Test("No Turkish value is empty")
    func noEmptyValues() throws {
        let tr = try strings(for: "tr")

        #expect(tr.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }.keys.sorted() == [])
    }
}

private final class BundleToken {}
