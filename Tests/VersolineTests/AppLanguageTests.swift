import Testing
import Foundation
@testable import Versoline

struct AppLanguageTests {

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "AppLanguageTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func noOverrideMeansSystem() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(AppLanguage.current(defaults: defaults, bundleIdentifier: name) == .system)
    }

    @Test func appliedLanguageIsReadBack() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        AppLanguage.turkish.apply(defaults: defaults)
        #expect(AppLanguage.current(defaults: defaults, bundleIdentifier: name) == .turkish)
        AppLanguage.english.apply(defaults: defaults)
        #expect(AppLanguage.current(defaults: defaults, bundleIdentifier: name) == .english)
    }

    @Test func systemRemovesTheOverride() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        AppLanguage.turkish.apply(defaults: defaults)
        AppLanguage.system.apply(defaults: defaults)
        #expect(AppLanguage.current(defaults: defaults, bundleIdentifier: name) == .system)
    }

    @Test func regionalCodesMapToTheirLanguage() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["tr-TR"], forKey: "AppleLanguages")
        #expect(AppLanguage.current(defaults: defaults, bundleIdentifier: name) == .turkish)
    }
}
