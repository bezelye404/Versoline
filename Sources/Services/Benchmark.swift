import Foundation
import Darwin
import AppKit

/// A repeatable memory check: `scripts/benchmark.sh` starts the app with `--benchmark`, which opens a dozen articles
/// one after another in the reader and writes the app's memory footprint after each step to a JSON file.
///
/// It runs on a throw-away copy of the library, so reading the articles never changes read or bookmark state, and it
/// does nothing unless the launch argument is present. Nothing is sent anywhere; the result is a local file.
@MainActor
enum Benchmark {

    static let isRequested = CommandLine.arguments.contains("--benchmark")

    private static func argument(_ name: String) -> String? {
        CommandLine.arguments.first { $0.hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) }
    }

    static var articleCount: Int { argument("benchmark-count").flatMap(Int.init) ?? 12 }
    static var secondsPerArticle: Double { argument("benchmark-seconds").flatMap(Double.init) ?? 3 }

    /// What each step does: `both` (default) switches to the article's feed and opens it, `list` only switches the
    /// list, `article` only opens the article, `mark-only` marks it read without showing it, `none` does nothing
    /// (a control: the footprint should stay flat). Used to find out which part of the app holds on to memory.
    static var mode: String { argument("benchmark-mode") ?? "both" }

    /// The benchmark leaves the feed refresh out by default: its network timing would move the numbers around. Add
    /// `--benchmark-refresh` to measure with it.
    static let skipRefresh = isRequested && !CommandLine.arguments.contains("--benchmark-refresh")

    /// Keeps the app open this long after the last step, so `footprint -p` can be run on it.
    static var holdSeconds: Double { argument("benchmark-hold").flatMap(Double.init) ?? 0 }

    static let resultURL = FileManager.default.temporaryDirectory.appendingPathComponent("benchmark.json")

    struct Sample: Codable {
        let label: String
        let footprintMB: Double
        let peakMB: Double
        let webKitStarted: Bool
    }

    struct Result: Codable {
        let articles: Int
        let items: Int
        let feeds: Int
        let samples: [Sample]
    }

    /// Copy of a library in a temporary folder, for the store to use instead of the real one. The script can leave a
    /// `benchmark-library.json` in the app's temporary folder (a Release build has its own, possibly empty, library);
    /// otherwise the app's own library is copied.
    static func scratchLibrary() -> URL? {
        let provided = FileManager.default.temporaryDirectory.appendingPathComponent("benchmark-library.json")
        let source = FileManager.default.fileExists(atPath: provided.path) ? provided : AppInfo.supportDirectory.appendingPathComponent("data.json")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VersolineBenchmark-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: source, to: directory.appendingPathComponent("data.json"))
        return directory
    }

    /// Memory the system charges to this process (the number `footprint` and Activity Monitor's "Memory" column report).
    static func footprintMB() -> Double { memoryMB().current }

    /// Current and highest footprint so far, in MB.
    static func memoryMB() -> (current: Double, peak: Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return (0, 0) }
        return (Double(info.phys_footprint) / 1_048_576, Double(info.ledger_phys_footprint_peak) / 1_048_576)
    }

    /// One text article per feed, round-robin, newest first. Podcasts and videos are left out: they start players.
    static func pickArticles(from store: FeedStore, count: Int) -> [FeedItem] {
        var picked: [FeedItem] = []
        var seen = Set<UUID>()
        var depth = 0
        while picked.count < count, depth < 5 {
            for feed in store.feeds where picked.count < count {
                let candidates = (store.items[feed.id] ?? []).sortedNewestFirst().filter { !$0.isPodcast && !$0.isYouTube }
                if depth < candidates.count, seen.insert(candidates[depth].id).inserted { picked.append(candidates[depth]) }
            }
            depth += 1
        }
        return picked
    }

    /// Lets the benchmark move the calendar view to another day (mode `calendar`).
    @MainActor @Observable
    final class CalendarDriver {
        static let shared = CalendarDriver()
        var day: Date?
    }

    /// Runs the whole sequence, writes the result and quits.
    static func run(store: FeedStore, show: @escaping (FeedItem, _ list: Bool, _ article: Bool) -> Void, showCalendar: @escaping () -> Void = {}) async {
        var samples: [Sample] = []
        func record(_ label: String) {
            let memory = memoryMB()
            samples.append(Sample(label: label, footprintMB: (memory.current * 10).rounded() / 10, peakMB: (memory.peak * 10).rounded() / 10, webKitStarted: WebView.isWebKitInUse))
        }

        try? await Task.sleep(for: .seconds(15))   // launch work (favicons, content blocker, cache cleanup) settles
        record("idle")

        if mode == "calendar" {
            // Walk the calendar back through the library, a few days per step, and measure after each third step.
            showCalendar()
            for step in 0..<articleCount {
                CalendarDriver.shared.day = Calendar.current.date(byAdding: .day, value: -step * 3, to: Date())
                try? await Task.sleep(for: .seconds(secondsPerArticle))
                if (step + 1) % 3 == 0 || step == articleCount - 1 { record("after \(step + 1) days") }
            }
            try? await Task.sleep(for: .seconds(2))
            record("final")
            let items = store.items.values.reduce(0) { $0 + $1.count }
            let result = Result(articles: articleCount, items: items, feeds: store.feeds.count, samples: samples)
            if let data = try? JSONEncoder().encode(result) { try? data.write(to: resultURL, options: .atomic) }
            if holdSeconds > 0 { try? await Task.sleep(for: .seconds(holdSeconds)) }
            NSApplication.shared.terminate(nil)
            return
        }

        let articles = pickArticles(from: store, count: articleCount)
        if mode == "mark-only-small", let first = articles.first {
            show(first, true, false)   // a short list on screen while items elsewhere are marked read
            try? await Task.sleep(for: .seconds(2))
        }
        for (index, item) in articles.enumerated() {
            if mode == "none" { /* control: only time passes */ } else if mode.hasPrefix("mark-only") { store.markAsRead(item) } else { show(item, mode != "article", mode != "list") }
            try? await Task.sleep(for: .seconds(secondsPerArticle))
            if (index + 1) % 3 == 0 || index == articles.count - 1 { record("after \(index + 1) articles") }
        }

        try? await Task.sleep(for: .seconds(2))
        record("final")
        MemoryRelief.trim()   // how much of the heap is only free pages that were never handed back
        try? await Task.sleep(for: .seconds(2))
        record("after heap trim")

        let result = Result(articles: articles.count, items: store.items.values.reduce(0) { $0 + $1.count }, feeds: store.feeds.count, samples: samples)
        if let data = try? JSONEncoder().encode(result) { try? data.write(to: resultURL, options: .atomic) }
        if holdSeconds > 0 { try? await Task.sleep(for: .seconds(holdSeconds)) }
        NSApplication.shared.terminate(nil)
    }
}
