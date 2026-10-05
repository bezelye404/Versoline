import Testing
import Foundation
@testable import Versoline

struct AppInfoTests {

    @Test func onlyWebAddressesAreFetched() {
        #expect(AppInfo.isWebAddress(URL(string: "https://example.com/feed")!))
        #expect(AppInfo.isWebAddress(URL(string: "HTTP://example.com/feed")!))
        #expect(!AppInfo.isWebAddress(URL(string: "file:///etc/hosts")!))
        #expect(!AppInfo.isWebAddress(URL(string: "ftp://example.com/feed")!))
        #expect(!AppInfo.isWebAddress(URL(string: "feed://example.com/feed")!))
        #expect(!AppInfo.isWebAddress(URL(string: "https:///nohost")!))
    }

    @Test func aFeedAtANonWebAddressIsRefused() async {
        await #expect(throws: URLError.self) {
            _ = try await RSSParser.fetchAndParse(url: "file:///etc/hosts", feedId: UUID())
        }
    }

    @Test func userAgentsCarryTheRealVersionAndNoStaleBuild() {
        #expect(AppInfo.userAgent.hasPrefix("Versoline/"))
        #expect(!AppInfo.redditUserAgent.contains("build"))
        #expect(AppInfo.redditUserAgent.contains(AppInfo.repositoryURL.absoluteString))
    }
}
