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
