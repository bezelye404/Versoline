import Testing
import Foundation
@testable import Versoline

struct RefreshBackoffTests {

    @Test func waitDoublesFromThirtyMinutesUpToADay() {
        let minutes = (1...9).map { RefreshBackoff.delay(afterFailures: $0) / 60 }
        #expect(minutes == [30, 60, 120, 240, 480, 960, 1440, 1440, 1440])
        #expect(RefreshBackoff.delay(afterFailures: 0) == 0)
        #expect(RefreshBackoff.delay(afterFailures: 500) == RefreshBackoff.longestDelay)
    }

    @Test func aFailedFeedWaitsUntilItsRetryTime() {
        var backoff = RefreshBackoff()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!backoff.isWaiting(at: start))

        backoff.recordFailure(at: start)
        #expect(backoff.failures == 1)
        #expect(backoff.isWaiting(at: start.addingTimeInterval(29 * 60)))
        #expect(!backoff.isWaiting(at: start.addingTimeInterval(31 * 60)))

        backoff.recordFailure(at: start.addingTimeInterval(31 * 60))
        #expect(backoff.isWaiting(at: start.addingTimeInterval(31 * 60 + 59 * 60)))
        #expect(!backoff.isWaiting(at: start.addingTimeInterval(31 * 60 + 61 * 60)))
    }

    @Test func offlineAndTimeoutsNeverCountAgainstAFeed() {
        for code in [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .dnsLookupFailed, .cancelled] {
            #expect(!RefreshBackoff.countsAgainstFeed(URLError(code)), "\(code)")
        }
    }

    @Test func serverAndFeedProblemsCountAgainstAFeed() {
        #expect(RefreshBackoff.countsAgainstFeed(URLError(.badServerResponse)))
        #expect(RefreshBackoff.countsAgainstFeed(URLError(.secureConnectionFailed)))
        #expect(RefreshBackoff.countsAgainstFeed(NSError(domain: "VersolineNetwork", code: 429)))
    }
}
