import Testing
import Foundation
@testable import Versoline

@MainActor
struct FaviconSourceTests {

    @Test func theFeedHostIsTriedBeforeItsParentDomain() {
        #expect(FaviconService.hostsToTry(for: "feeds.example.com") == ["feeds.example.com", "example.com"])
        #expect(FaviconService.hostsToTry(for: "example.com") == ["example.com"])
    }

    @Test func iconsNamedByThePageAreFoundWithTouchIconsFirst() {
        let html = """
        <link rel="stylesheet" href="/style.css">
        <link rel="icon" href="/favicon-32.png">
        <link rel='apple-touch-icon' href='/touch.png'>
        <link rel="shortcut icon" href="https://cdn.example.com/icon.ico">
        """
        #expect(FaviconService.iconAddresses(inHTML: html, pageAddress: "https://example.com/") == [
            "https://example.com/touch.png",
            "https://example.com/favicon-32.png",
            "https://cdn.example.com/icon.ico",
        ])
        #expect(FaviconService.iconAddresses(inHTML: "<p>no icons</p>", pageAddress: "https://example.com/").isEmpty)
    }

    @Test func noThirdPartyIconServiceIsNamedInTheSources() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("duckduckgo"), "\(url.lastPathComponent) names an icon service")
        }
    }
}
