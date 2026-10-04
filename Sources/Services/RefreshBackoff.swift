import Foundation

/// Failing feeds are not asked again on every automatic refresh: after each failure the wait doubles, from 30 minutes
/// up to a day. A refresh the user starts by hand always tries every feed, and a success clears the record.
/// Kept in memory only: a restart gives every feed a fresh chance and nothing new is stored or synced.
struct RefreshBackoff: Equatable {
    private(set) var failures = 0
    private(set) var retryAfter = Date.distantPast

    static let firstDelay: TimeInterval = 30 * 60
    static let longestDelay: TimeInterval = 24 * 60 * 60

    static func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        let doublings = min(failures - 1, 16)
        return min(firstDelay * pow(2, Double(doublings)), longestDelay)
    }

    func isWaiting(at date: Date = Date()) -> Bool { date < retryAfter }

    mutating func recordFailure(at date: Date = Date()) {
        failures += 1
        retryAfter = date.addingTimeInterval(Self.delay(afterFailures: failures))
    }

    /// Network trouble on the user's side (offline, timeout, connection lost) says nothing about the feed, so it never
    /// counts against it; a missing page, a server error or unreadable XML does.
    static func countsAgainstFeed(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return true }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .dnsLookupFailed,
             .internationalRoamingOff, .dataNotAllowed, .cancelled, .cannotConnectToHost:
            return false
        default:
            return true
        }
    }
}
