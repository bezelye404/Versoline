import Foundation

/// Facts about the running app, read from its bundle so nothing has to be kept in sync by hand.
enum AppInfo {

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The bundle identifier: `com.bezelye.Versoline`, or `.dev` for the Debug build.
    static var identifier: String {
        Bundle.main.bundleIdentifier ?? "com.bezelye.Versoline"
    }

    /// Where everything the app keeps lives: `~/Library/Application Support/Versoline`, inside the app's sandbox
    /// container. Not created here.
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Versoline", isDirectory: true)
    }

    /// Feeds, article pages and images are only ever fetched over the web. A feed or OPML file naming a `file:` or
    /// other address is refused rather than read.
    static func isWebAddress(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host?.isEmpty == false
    }

    static let repositoryURL = URL(string: "https://github.com/bezelye404/Versoline")!

    /// Announces the app to the servers it reads feeds from.
    static var userAgent: String {
        "Versoline/\(version) (Macintosh; Mac OS X)"
    }

    /// Reddit asks API clients for a descriptive agent that says where to read about them.
    static var redditUserAgent: String {
        "Versoline/\(version) (macOS; \(identifier); +\(repositoryURL.absoluteString))"
    }

    /// Some news sites refuse requests that do not look like a browser. Used only to fetch an article page the user
    /// has opened, or a page that names a channel's feed.
    static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}
