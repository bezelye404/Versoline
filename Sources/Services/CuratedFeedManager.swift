import Foundation

@MainActor
final class CuratedFeedManager {

    static let shared = CuratedFeedManager()

    private(set) var categories: [CuratedFeedCategory] = []

    private init() {
        load()
    }

    func load() {
        // 1. Try bundled JSON
        if let url = Bundle.main.url(forResource: "curated_feeds", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([CuratedFeedCategory].self, from: data) {
            self.categories = list
            AppLogger.shared.log("Loaded \(list.count) curated categories (\(totalFeedCount) feeds) from JSON", level: .info, category: .storage)
            return
        }

        // 2. Try bundled rss.md fallback
        if let mdURL = Bundle.main.url(forResource: "rss", withExtension: "md"),
           let mdString = try? String(contentsOf: mdURL, encoding: .utf8) {
            let parsed = parseMarkdown(mdString)
            if !parsed.isEmpty {
                self.categories = parsed
                AppLogger.shared.log("Loaded \(parsed.count) curated categories from rss.md", level: .info, category: .storage)
                return
            }
        }
    }

    var totalFeedCount: Int {
        categories.reduce(0) { $0 + $1.feeds.count }
    }

    func allFeeds() -> [(category: String, feed: CuratedFeed)] {
        categories.flatMap { cat in
            cat.feeds.map { (category: cat.category, feed: $0) }
        }
    }

    // MARK: - Markdown Parser Fallback

    private func parseMarkdown(_ markdown: String) -> [CuratedFeedCategory] {
        var results: [CuratedFeedCategory] = []

        // Split by <h3><strong>Category</strong></h3>
        let categoryPattern = try? NSRegularExpression(pattern: #"<h3><strong>(.*?)</strong></h3>([\s\S]*?)(?=<h3>|$)"#, options: [])
        let linkPattern = try? NSRegularExpression(pattern: #"<a href=["'](.*?)["']>(.*?)</a>"#, options: [])

        guard let categoryPattern, let linkPattern else { return [] }

        let nsString = markdown as NSString
        let catMatches = categoryPattern.matches(in: markdown, range: NSRange(location: 0, length: nsString.length))

        for catMatch in catMatches {
            guard catMatch.numberOfRanges >= 3 else { continue }
            let catName = nsString.substring(with: catMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let sectionHTML = nsString.substring(with: catMatch.range(at: 2))

            let linkMatches = linkPattern.matches(in: sectionHTML, range: NSRange(location: 0, length: (sectionHTML as NSString).length))
            var feeds: [CuratedFeed] = []

            for linkMatch in linkMatches {
                guard linkMatch.numberOfRanges >= 3 else { continue }
                var url = (sectionHTML as NSString).substring(with: linkMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                let rawTitle = (sectionHTML as NSString).substring(with: linkMatch.range(at: 2))
                let title = rawTitle.strippingHTML()

                if url.hasPrefix("http://www.feeder.co/add-feed?url=") {
                    url = String(url.dropFirst("http://www.feeder.co/add-feed?url=".count))
                    if url.hasSuffix("#") { url = String(url.dropLast()) }
                }
                if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
                    url = "https://" + url
                }

                feeds.append(CuratedFeed(title: title, url: url))
            }

            if !feeds.isEmpty {
                results.append(CuratedFeedCategory(category: catName, feeds: feeds))
            }
        }

        return results
    }
}
