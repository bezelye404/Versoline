import Foundation

/// Finds the RSS or Atom feed of a web site from its address, so pasting `example.com` or an article link works
/// like pasting the feed URL. The page the user typed is fetched directly from their Mac; nothing else is contacted
/// except the site's own common feed paths when the page does not advertise a feed.
enum FeedDiscovery {

    struct Candidate: Equatable {
        let url: URL
        let title: String?
    }

    private static let linkTag = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: [.caseInsensitive])
    private static let attribute = try? NSRegularExpression(
        pattern: #"([a-zA-Z_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#
    )
    private static let feedTypes: Set<String> = [
        "application/rss+xml", "application/atom+xml", "application/rdf+xml", "application/xml", "text/xml",
    ]

    /// Feeds a page advertises with `<link rel="alternate" type="application/rss+xml" href="...">`, in page order,
    /// without comment feeds and duplicates. Relative addresses are resolved against `baseURL`.
    static func candidates(inHTML html: String, baseURL: URL) -> [Candidate] {
        guard let linkTag, let attribute else { return [] }
        let source = html as NSString
        var found: [Candidate] = []
        var seen = Set<String>()

        for match in linkTag.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let tag = source.substring(with: match.range) as NSString
            var values: [String: String] = [:]
            for pair in attribute.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                let name = tag.substring(with: pair.range(at: 1)).lowercased()
                for group in 2...4 where pair.range(at: group).location != NSNotFound {
                    values[name] = tag.substring(with: pair.range(at: group))
                    break
                }
            }
            guard let rel = values["rel"]?.lowercased(), rel.split(separator: " ").contains("alternate"),
                  let type = values["type"]?.lowercased(), feedTypes.contains(type),
                  let href = values["href"], !href.isEmpty else { continue }

            let cleanHref = href.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: cleanHref, relativeTo: baseURL)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { continue }

            let title = values["title"]?.replacingOccurrences(of: "&amp;", with: "&")
            if isCommentFeed(url: url, title: title) { continue }
            guard seen.insert(url.absoluteString).inserted else { continue }
            found.append(Candidate(url: url, title: title))
        }
        return found
    }

    private static func isCommentFeed(url: URL, title: String?) -> Bool {
        let text = ((title ?? "") + " " + url.absoluteString).lowercased()
        return text.contains("comment") || text.contains("yorum")
    }

    /// Whether the start of a download looks like a feed (RSS, Atom or RDF) rather than an HTML page.
    static func looksLikeFeed(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        guard !head.contains("<html"), !head.contains("<!doctype html") else { return false }
        return head.contains("<rss") || head.contains("<feed") || head.contains("<rdf:rdf")
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private static let commonPaths = ["/feed", "/rss", "/rss.xml", "/feed.xml", "/atom.xml", "/index.xml"]

    /// The feed address for a page the user typed, or nil when none is found. Reads at most 300 KB of the page.
    static func findFeed(onPageAt address: String) async -> String? {
        guard let pageURL = URL(string: address) else { return nil }
        var request = URLRequest(url: pageURL)
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

        if let page = await download(request, limit: 300_000) {
            if let first = candidates(inHTML: String(decoding: page, as: UTF8.self), baseURL: pageURL).first {
                return first.url.absoluteString
            }
        }

        // The page advertises nothing: try the usual paths on the same site.
        guard var parts = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else { return nil }
        let deadline = Date().addingTimeInterval(12)   // a slow site must not keep the sheet spinning
        for path in probePaths(forPagePath: pageURL.path) {
            guard !Task.isCancelled, Date() < deadline else { return nil }
            parts.path = path
            parts.query = nil
            parts.fragment = nil
            guard let probeURL = parts.url else { continue }
            var probe = URLRequest(url: probeURL)
            probe.timeoutInterval = 4
            probe.setValue(request.value(forHTTPHeaderField: "User-Agent"), forHTTPHeaderField: "User-Agent")
            if let data = await download(probe, limit: 4_096), looksLikeFeed(data) {
                return probeURL.absoluteString
            }
        }
        return nil
    }

    /// Where to look when a page advertises no feed: the usual names under the section the page sits in
    /// (`/turkce/articles/x` gives `/turkce/index.xml`), then at the site root.
    static func probePaths(forPagePath pagePath: String) -> [String] {
        var paths: [String] = []
        if let section = pagePath.split(separator: "/").first, section.count <= 24 {
            for name in ["index.xml", "feed", "rss.xml"] { paths.append("/\(section)/\(name)") }
        }
        paths += commonPaths
        return paths
    }

    private static func download(_ request: URLRequest, limit: Int) async -> Data? {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= limit { break }
            }
            return data
        } catch {
            return nil
        }
    }
}
