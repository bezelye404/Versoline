import Testing
import Foundation
import MachO
@testable import Versoline

/// Guards the project's "low RAM" goal: a realistic library must stay cheap to hold in memory.
@Suite("Memory Budget Tests")
@MainActor
struct MemoryBudgetTests {

    private func physFootprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    private func makeLibrary(feeds feedCount: Int, itemsPerFeed: Int) -> ([Feed], [UUID: [FeedItem]]) {
        var feeds: [Feed] = []
        var items: [UUID: [FeedItem]] = [:]
        for f in 0..<feedCount {
            let feed = Feed(title: "Feed \(f)", url: "https://example.com/\(f)/feed.xml")
            feeds.append(feed)
            items[feed.id] = (0..<itemsPerFeed).map { i in
                FeedItem(feedId: feed.id, title: "Article title number \(i) of feed \(f) with some more words in it",
                         link: "https://example.com/\(f)/posts/\(i)",
                         itemDescription: String(repeating: "Snippet text ", count: 14),
                         pubDate: Date(timeIntervalSince1970: Double(1_700_000_000 + i * 3600)),
                         readingMinutes: 4)
            }
        }
        return (feeds, items)
    }

    @Test("A 3,500-item library loads into the store within the memory budget")
    func libraryFootprint() throws {
        let (feeds, items) = makeLibrary(feeds: 50, itemsPerFeed: 70)
        let ts = try TestStore { dir in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(FeedStore.StorageData(feeds: feeds, items: items, folders: [])).write(to: dir.appendingPathComponent("data.json"))
        }
        defer { ts.cleanup() }
        // Drop the store that was just built so only the reopen below is measured.
        _ = ts.store.items.count

        let before = physFootprint()
        let reopened = ts.reopen()
        let after = physFootprint()
        let deltaMB = Double(after - before) / 1_048_576
        print("MEMORY library 3500 items: +\(String(format: "%.1f", deltaMB)) MB, items=\(reopened.items.values.reduce(0) { $0 + $1.count })")

        #expect(reopened.items.values.reduce(0) { $0 + $1.count } == 3500)
        // Measured about 2 MB; the bound leaves headroom for machine differences and only catches order-of-magnitude regressions
        // (e.g. keeping article bodies on every item) without being flaky across machines.
        #expect(deltaMB < 15)
    }

    @Test("FeedItem stays small: no article body is held per item")
    func itemSize() {
        // Existing layout is ~250 bytes; the bound catches accidental large stored fields.
        #expect(MemoryLayout<FeedItem>.size <= 400)
    }
}
