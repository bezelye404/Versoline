import Testing
import Foundation
@testable import Versoline

@Suite("SocialFeedResolver URL Tests")
@MainActor
struct SocialFeedResolverTests {

    private let resolver = SocialFeedResolver.shared

    @Test("Subreddit input forms all resolve to the same feed URL", arguments: [
        "swift", "r/swift", "/r/swift", "https://www.reddit.com/r/swift",
        "reddit.com/r/swift/comments/abc", "https://old.reddit.com/r/swift", "  swift  ",
    ])
    func subredditNormalization(input: String) {
        #expect(resolver.buildRedditSubredditURL(subreddit: input) == "https://www.reddit.com/r/swift/.rss")
    }

    @Test("Subreddit sorting and time filter")
    func subredditSort() {
        #expect(resolver.buildRedditSubredditURL(subreddit: "swift", sort: .new) == "https://www.reddit.com/r/swift/new/.rss")
        #expect(resolver.buildRedditSubredditURL(subreddit: "swift", sort: .rising) == "https://www.reddit.com/r/swift/rising/.rss")
        #expect(resolver.buildRedditSubredditURL(subreddit: "swift", sort: .top) == "https://www.reddit.com/r/swift/top/.rss")
        #expect(
            resolver.buildRedditSubredditURL(subreddit: "swift", sort: .top, timeFilter: .week)
                == "https://www.reddit.com/r/swift/top/.rss?t=\(RedditTimeFilter.week.rawValue)"
        )
    }

    @Test("Empty subreddit or user yields an empty string")
    func emptyInput() {
        #expect(resolver.buildRedditSubredditURL(subreddit: "  ") == "")
        #expect(resolver.buildRedditUserURL(username: "") == "")
    }

    @Test("User input forms all resolve to the same feed URL", arguments: [
        "alice", "u/alice", "/u/alice", "user/alice", "/user/alice",
        "https://www.reddit.com/user/alice", "https://old.reddit.com/user/alice",
    ])
    func userNormalization(input: String) {
        #expect(resolver.buildRedditUserURL(username: input) == "https://www.reddit.com/user/alice/.rss")
    }

    @Test("User feed types")
    func userTypes() {
        #expect(resolver.buildRedditUserURL(username: "alice", type: .submitted) == "https://www.reddit.com/user/alice/submitted/.rss")
        #expect(resolver.buildRedditUserURL(username: "alice", type: .comments) == "https://www.reddit.com/user/alice/comments/.rss")
    }

    @Test("Reddit page links are converted to RSS without network access")
    func smartDetectReddit() async {
        #expect(await resolver.smartDetectAndResolve(url: "https://www.reddit.com/r/swift/") == "https://www.reddit.com/r/swift/.rss")
        #expect(await resolver.smartDetectAndResolve(url: "https://www.reddit.com/user/alice") == "https://www.reddit.com/user/alice/.rss")
        #expect(await resolver.smartDetectAndResolve(url: "https://www.reddit.com/r/swift/.rss") == "https://www.reddit.com/r/swift/.rss")
    }

    @Test("Non-social and invalid URLs are not resolved")
    func smartDetectOther() async {
        #expect(await resolver.smartDetectAndResolve(url: "https://example.com/feed") == nil)
        #expect(await resolver.smartDetectAndResolve(url: "not a url") == nil)
        #expect(await resolver.smartDetectAndResolve(url: "https://www.reddit.com/") == nil)
    }

    @Test("Existing YouTube feed URLs are returned unchanged")
    func smartDetectYouTubeFeed() async {
        let url = "https://www.youtube.com/feeds/videos.xml?channel_id=UC123"

        #expect(await resolver.smartDetectAndResolve(url: url) == url)
    }
}
