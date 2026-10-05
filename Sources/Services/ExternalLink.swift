import Foundation

/// Addresses other apps hand to Versoline: `feed://` links from web pages and mail, and OPML files.
enum ExternalLink {

    enum Kind: Equatable {
        case feed(String)       // an address to add
        case opml(URL)          // a file to import
    }

    /// `feed://example.com/rss` and `feeds://...` mean "this is a feed" over http or https; `feed:https://...` wraps a
    /// full address. Anything else that is not a feed link gives nil.
    static func feedAddress(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        let text = url.absoluteString
        switch scheme {
        case "feed", "feeds":
            let rest = String(text.dropFirst(scheme.count + 1))
            if rest.lowercased().hasPrefix("http://") || rest.lowercased().hasPrefix("https://") { return rest }
            guard rest.hasPrefix("//"), rest.count > 2 else { return nil }
            return "https:" + rest   // feed:// historically meant http; almost every site redirects, https is the safe default
        default:
            return nil
        }
    }

    static func kind(of url: URL) -> Kind? {
        if let address = feedAddress(from: url) { return .feed(address) }
        if url.isFileURL, ["opml", "xml"].contains(url.pathExtension.lowercased()) { return .opml(url) }
        return nil
    }
}
