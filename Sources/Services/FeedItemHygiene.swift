import Foundation

// MARK: - Feed item hygiene
//
// Some feeds carry entries that are not articles: social "follow us" promos, links to the home page,
// the same story listed several times, or items with no <link> at all (podcast hosts often identify
// episodes only by <guid> and the audio file). Without a unique link, items share one identity, which
// breaks read state and bookmarks. These rules are pure and conservative: they only drop what is clearly
// not an article.

enum FeedItemHygiene {

    /// Link for an item: the real link if it is a web URL, otherwise the guid if that is one, otherwise the
    /// audio file of a podcast episode. `nil` means the entry has nothing that identifies it; drop it.
    static func resolvedLink(link: String, guid: String, enclosureURL: String?) -> String? {
        for candidate in [link, guid, enclosureURL ?? ""] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if isWebURL(trimmed) { return trimmed }
        }
        return nil
    }

    /// True when an entry clearly is not an article and should not appear in the list.
    static func isNotAnArticle(title: String, link: String, hasEnclosure: Bool, feedHost: String?) -> Bool {
        guard let url = URL(string: link), let host = url.host?.lowercased() else { return true }
        let linkHost = normalizedHost(host)
        let sameSite = feedHost.map { normalizedHost($0) == linkHost || linkHost.hasSuffix("." + normalizedHost($0)) } ?? false
        let pathDepth = url.pathComponents.filter { $0 != "/" }.count

        // A bare home page is never a story (podcast episodes can legitimately point at the show page).
        if pathDepth == 0 && !hasEnclosure { return true }

        // Promotion for a social channel or app that is not the feed's own site.
        if !sameSite && socialAndStoreHosts.contains(where: { linkHost == $0 || linkHost.hasSuffix("." + $0) }) {
            return true
        }

        // "Follow us" / "subscribe" style titles that lead to a shallow page.
        if pathDepth <= 1 && !hasEnclosure && promotionalTitle(title) { return true }
        return false
    }

    /// Removes duplicates (same article reached through different tracking parameters or fragments) and
    /// non-articles, keeping the first occurrence and the feed's order.
    static func clean(_ items: [FeedItem], feedHost: String?) -> [FeedItem] {
        var seen = Set<String>()
        var result: [FeedItem] = []
        result.reserveCapacity(items.count)
        for item in items {
            if isNotAnArticle(title: item.title, link: item.link, hasEnclosure: item.audioURL != nil, feedHost: feedHost) { continue }
            guard seen.insert(dedupeKey(for: item.link)).inserted else { continue }
            result.append(item)
        }
        return result
    }

    /// Identity of an article for duplicate detection: lower-case host, no fragment, no tracking
    /// parameters, no trailing slash.
    static func dedupeKey(for link: String) -> String {
        guard var components = URLComponents(string: link) else { return link }
        components.fragment = nil
        components.host = components.host?.lowercased()
        while components.path.count > 1 && components.path.hasSuffix("/") { components.path.removeLast() }
        if let items = components.queryItems {
            let kept = items.filter { !isTrackingParameter($0.name) }.sorted { $0.name < $1.name }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        return components.string ?? link
    }

    // MARK: - Helpers

    private static func isWebURL(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return url.host?.isEmpty == false
    }

    private static func normalizedHost(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    private static func isTrackingParameter(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("utm_") || trackingParameters.contains(lower)
    }

    private static func promotionalTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return promotionalPhrases.contains { lower.contains($0) }
    }

    private static let trackingParameters: Set<String> = [
        "at_medium", "at_campaign", "at_source", "fbclid", "gclid", "igshid", "mc_cid", "mc_eid", "ref", "cmpid", "ocid", "ncid",
    ]

    private static let socialAndStoreHosts = [
        "whatsapp.com", "wa.me", "t.me", "telegram.me", "telegram.org", "facebook.com", "fb.com", "fb.me", "instagram.com",
        "twitter.com", "x.com", "linkedin.com", "tiktok.com", "play.google.com", "apps.apple.com", "itunes.apple.com",
    ]

    private static let promotionalPhrases = [
        "abone ol", "abone olmak için", "takip edin", "bizi takip", "kanalımıza katıl", "uygulamayı indir",
        "subscribe to", "follow us", "join our channel", "download our app", "sign up for our newsletter",
    ]
}
