import Foundation

@MainActor
@Observable
final class FeedHealthService {

    static let shared = FeedHealthService()

    enum HealthStatus: Hashable {
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

    struct FeedHealthReport: Identifiable, Hashable {
        let id: UUID
        let feedTitle: String
        let feedURL: String
        let status: HealthStatus
        let lastItemDate: Date?
    }

    var reports: [FeedHealthReport] = []
    var isScanning: Bool = false

    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        return URLSession(configuration: config)
    }()

    private init() {}

    func scan(store: FeedStore) async {
        isScanning = true
        reports = []
        AppLogger.shared.log("Starting Feed Health Diagnostics scan for \(store.feeds.count) feeds...", level: .info, category: .network)

        var newReports: [FeedHealthReport] = []

        for feed in store.feeds {
            let items = store.itemsForFeed(feed.id)
            let latestDate = items.first?.pubDate

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

            newReports.append(FeedHealthReport(
                id: feed.id,
                feedTitle: feed.title,
                feedURL: feed.url,
                status: status,
                lastItemDate: latestDate
            ))
        }

        self.reports = newReports.sorted { (a, b) -> Bool in
            a.status.isProblematic && !b.status.isProblematic
        }
        self.isScanning = false
        AppLogger.shared.log("Feed Health Diagnostics complete. \(newReports.filter { $0.status.isProblematic }.count) issues found.", level: .info, category: .network)
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
