import Foundation

@MainActor
@Observable
final class FeedHealthService {

    static let shared = FeedHealthService()

    enum HealthStatus: Hashable, Sendable {
        case healthy
        case stale(days: Int)
        case broken(reason: String)

        var isProblematic: Bool {
            switch self {
            case .healthy: return false
            case .stale, .broken: return true
            }
        }
    }

    struct FeedHealthReport: Identifiable, Hashable, Sendable {
        let id: UUID
        let feedTitle: String
        let feedURL: String
        let status: HealthStatus
        let lastItemDate: Date?
    }

    var reports: [FeedHealthReport] = []
    var isScanning: Bool = false

    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        return URLSession(configuration: config)
    }()

    private init() {}

    func scan(store: FeedStore) async {
        isScanning = true
        reports = []
        AppLogger.shared.log("Starting Feed Health Diagnostics scan for \(store.feeds.count) feeds...", level: .info, category: .network)

        // Snapshot feed metadata on main thread first
        let feedSnapshots: [(feed: Feed, latestDate: Date?)] = store.feeds.map { feed in
            let latestDate = store.itemsForFeed(feed.id).first?.pubDate
            return (feed, latestDate)
        }

        let maxConcurrent = 6
        var newReports: [FeedHealthReport] = []

        await withTaskGroup(of: FeedHealthReport.self) { group in
            var iterator = feedSnapshots.makeIterator()

            // Seed initial pool
            for _ in 0..<maxConcurrent {
                if let next = iterator.next() {
                    group.addTask {
                        await self.checkFeed(next.feed, latestDate: next.latestDate)
                    }
                }
            }

            // As each finishes, add the next
            for await report in group {
                newReports.append(report)
                if let next = iterator.next() {
                    group.addTask {
                        await self.checkFeed(next.feed, latestDate: next.latestDate)
                    }
                }
            }
        }

        self.reports = newReports.sorted { (a, b) -> Bool in
            a.status.isProblematic && !b.status.isProblematic
        }
        self.isScanning = false
        AppLogger.shared.log("Feed Health Diagnostics complete. \(newReports.filter { $0.status.isProblematic }.count) issues found.", level: .info, category: .network)
    }

    private func checkFeed(_ feed: Feed, latestDate: Date?) async -> FeedHealthReport {
        var status: HealthStatus = .healthy

        if let latestDate {
            let daysOld = Calendar.current.dateComponents([.day], from: latestDate, to: Date()).day ?? 0
            if daysOld > 180 {
                status = .stale(days: daysOld)
            }
        }

        // Quick HTTP validation
        if let url = URL(string: feed.url) {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 6

            do {
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...399).contains(http.statusCode) {
                    status = .broken(reason: "HTTP \(http.statusCode)")
                }
            } catch {
                // Fallback to GET with Range 0-512 in case server rejects HEAD
                var getReq = URLRequest(url: url)
                getReq.setValue("bytes=0-512", forHTTPHeaderField: "Range")
                getReq.timeoutInterval = 6
                if let (_, getResp) = try? await session.data(for: getReq),
                   let http = getResp as? HTTPURLResponse, (200...399).contains(http.statusCode) {
                    // Healthy
                } else {
                    status = .broken(reason: error.localizedDescription)
                }
            }
        } else {
            status = .broken(reason: "Invalid URL")
        }

        return FeedHealthReport(
            id: feed.id,
            feedTitle: feed.title,
            feedURL: feed.url,
            status: status,
            lastItemDate: latestDate
        )
    }

    func removeFeed(_ report: FeedHealthReport, store: FeedStore) {
        if let feed = store.feed(for: report.id) {
            store.removeFeed(feed)
            reports.removeAll { $0.id == report.id }
        }
    }

    func removeAllBroken(store: FeedStore) {
        let broken = reports.filter {
            if case .broken = $0.status { return true }
            return false
        }
        for report in broken {
            removeFeed(report, store: store)
        }
    }
}
