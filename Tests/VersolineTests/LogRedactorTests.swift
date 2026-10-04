import Testing
import Foundation
@testable import Versoline

@Suite("LogRedactor Tests")
@MainActor
struct LogRedactorTests {

    @Test("Query strings in URLs are removed, host and path stay")
    func queryRemoved() {
        let out = LogRedactor.redact("Fetching https://patreon.example.com/rss/123?auth=SECRET&k=v now")

        #expect(out == "Fetching https://patreon.example.com/rss/123?… now")
        #expect(!out.contains("SECRET"))
    }

    @Test("Credentials inside URLs are removed")
    func userInfoRemoved() {
        let out = LogRedactor.redact("https://alice:hunter2@example.com/feed.xml")

        #expect(out == "https://example.com/feed.xml")
    }

    @Test("The macOS account name is removed from paths")
    func homePath() {
        let out = LogRedactor.redact("No database at /Users/alice/Library/Containers/com.bezelye.Versoline/data.json")

        #expect(out == "No database at /Users/~/Library/Containers/com.bezelye.Versoline/data.json")
    }

    @Test("Ordinary text and question marks are untouched")
    func plainText() {
        #expect(LogRedactor.redact("Refresh finished? yes") == "Refresh finished? yes")
        #expect(LogRedactor.redact("Saved database to disk (1024 bytes)") == "Saved database to disk (1024 bytes)")
    }

    @Test("Export and copy output is redacted, the in-app entries are not")
    func exportIsRedacted() {
        // Distinctive values: other tests log UUIDs, which can contain short hex strings like "ABC".
        let logger = AppLogger.shared
        logger.log("Adding feed: https://example.com/f?token=ZTOKENVALUE", level: .info, category: .network,
                   details: "https://u:p@example.com/x?key=ZSECRETVALUE")

        let exported = logger.exportFormattedLogs()

        #expect(!exported.contains("ZTOKENVALUE"))
        #expect(!exported.contains("ZSECRETVALUE"))
        #expect(!exported.contains("u:p@"))
        #expect(logger.entries.last?.message.contains("token=ZTOKENVALUE") == true)
        logger.clear()
    }
}
