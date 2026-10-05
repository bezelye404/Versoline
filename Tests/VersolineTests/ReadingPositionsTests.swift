import Testing
import Foundation
@testable import Versoline

@MainActor
struct ReadingPositionsTests {

    private func positions(limit: Int = 300) -> (ReadingPositions, UserDefaults, String) {
        let suite = "ReadingPositionsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (ReadingPositions(defaults: defaults, key: "p", limit: limit), defaults, suite)
    }

    @Test func aPositionInTheMiddleIsRemembered() {
        let (store, defaults, suite) = positions(); defer { defaults.removePersistentDomain(forName: suite) }
        store.save(link: "a", block: 12, blockCount: 40)
        #expect(store.position(for: "a") == 12)
        #expect(store.position(for: "b") == nil)
    }

    @Test func theStartAndTheEndAreForgotten() {
        let (store, defaults, suite) = positions(); defer { defaults.removePersistentDomain(forName: suite) }
        store.save(link: "a", block: 12, blockCount: 40)
        store.save(link: "a", block: 1, blockCount: 40)       // back near the top
        #expect(store.position(for: "a") == nil)
        store.save(link: "a", block: 12, blockCount: 40)
        store.save(link: "a", block: 38, blockCount: 40)      // read to the end
        #expect(store.position(for: "a") == nil)
    }

    @Test func onlyTheMostRecentArticlesAreKept() {
        let (store, defaults, suite) = positions(limit: 3); defer { defaults.removePersistentDomain(forName: suite) }
        for name in ["a", "b", "c", "d"] { store.save(link: name, block: 10, blockCount: 40) }
        #expect(store.count == 3)
        #expect(store.position(for: "a") == nil)
        #expect(store.position(for: "d") == 10)
    }

    @Test func positionsSurviveARestart() {
        let (store, defaults, suite) = positions(); defer { defaults.removePersistentDomain(forName: suite) }
        store.save(link: "a", block: 12, blockCount: 40)
        let reopened = ReadingPositions(defaults: defaults, key: "p")
        #expect(reopened.position(for: "a") == 12)
    }
}
