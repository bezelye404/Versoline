import Foundation
import CryptoKit

@MainActor
final class ReaderModeExtractor {

    static let shared = ReaderModeExtractor()

    private let memoryCache = NSCache<NSString, NSString>()
    private let cacheDirectory: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDir = appSupport.appendingPathComponent("EasyRSS/ReaderCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        self.cacheDirectory = cacheDir
        memoryCache.countLimit = 15
        memoryCache.totalCostLimit = 2 * 1024 * 1024 // 2MB RAM limit
    }

    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    // MARK: - Cache Helpers

    private func cacheKey(for urlString: String) -> String {
        let inputData = Data(urlString.utf8)
        let hash = SHA256.hash(data: inputData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(for urlString: String) -> URL {
        let key = cacheKey(for: urlString)
        return cacheDirectory.appendingPathComponent("\(key).html")
    }

    // MARK: - Substantive Content Validation

    func isSubstantiveContent(_ html: String) -> Bool {
        let stripped = html.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.count >= 350
    }

    func cachedContent(for urlString: String, requireSubstantive: Bool = false) -> String? {
        let nsKey = urlString as NSString
        if let memory = memoryCache.object(forKey: nsKey) {
            let memoryString = memory as String
            if requireSubstantive && !isSubstantiveContent(memoryString) {
                memoryCache.removeObject(forKey: nsKey)
                let diskURL = fileURL(for: urlString)
                try? FileManager.default.removeItem(at: diskURL)
                return nil
            }
            return memoryString
        }

        let diskURL = fileURL(for: urlString)
        if FileManager.default.fileExists(atPath: diskURL.path),
           let diskData = try? Data(contentsOf: diskURL),
           let html = String(data: diskData, encoding: .utf8) {
            if requireSubstantive && !isSubstantiveContent(html) {
                // Delete poisoned or stub teaser from disk
                try? FileManager.default.removeItem(at: diskURL)
                return nil
            }
            memoryCache.setObject(html as NSString, forKey: nsKey)
            return html
        }

        return nil
    }

    func saveToCache(urlString: String, content: String, storeInMemory: Bool = true) {
        if storeInMemory {
            memoryCache.setObject(content as NSString, forKey: urlString as NSString)
        }
        let diskURL = fileURL(for: urlString)
        Task.detached(priority: .utility) {
            try? content.data(using: .utf8)?.write(to: diskURL, options: .atomic)
        }
    }

    // MARK: - Extraction

    func formatFeedContentAsReaderHTML(
        title: String,
        author: String?,
        pubDate: Date?,
        htmlContent: String,
        link: String
    ) -> String {
        var headerHTML = "<h1>\(title)</h1>"
        var metaItems: [String] = []
        if let author, !author.isEmpty {
            metaItems.append(author)
        }
        if let pubDate {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            metaItems.append(df.string(from: pubDate))
        }
        if !metaItems.isEmpty {
            headerHTML += "<p style=\"opacity: 0.6; font-size: 0.9em; margin-bottom: 1.5em;\">\(metaItems.joined(separator: " • "))</p>"
        }
        return headerHTML + "<div class=\"reader-body\">" + htmlContent + "</div>"
    }

    func extract(
        from urlString: String,
        fallbackContent: String? = nil,
        title: String? = nil,
        author: String? = nil,
        pubDate: Date? = nil,
        forceWebFetch: Bool = false
    ) async -> String? {
        // 1. Check memory or disk cache first (offline support) if not force-reloading
        if !forceWebFetch, let cached = cachedContent(for: urlString, requireSubstantive: true) {
            return cached
        }

        // 2. Direct format for Reddit or YouTube
        let isReddit = urlString.lowercased().contains("reddit.com")
        let isYouTube = urlString.lowercased().contains("youtube.com") || urlString.lowercased().contains("youtu.be")

        if (isReddit || isYouTube), let fallbackContent, !fallbackContent.isEmpty {
            let formatted = formatFeedContentAsReaderHTML(
                title: title ?? "",
                author: author,
                pubDate: pubDate,
                htmlContent: fallbackContent,
                link: urlString
            )
            saveToCache(urlString: urlString, content: formatted, storeInMemory: false)
            return formatted
        }

        guard let url = URL(string: urlString) else {
            if let fallbackContent, !fallbackContent.isEmpty {
                return formatFeedContentAsReaderHTML(title: title ?? "", author: author, pubDate: pubDate, htmlContent: fallbackContent, link: urlString)
            }
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                let html = String(decoding: data, as: UTF8.self)
                if let cleanedBody = extractArticleHTML(from: html, baseURL: url), !cleanedBody.isEmpty {
                    let fullFormatted: String
                    if cleanedBody.contains("<h1") {
                        fullFormatted = cleanedBody
                    } else {
                        fullFormatted = formatFeedContentAsReaderHTML(
                            title: title ?? "",
                            author: author,
                            pubDate: pubDate,
                            htmlContent: cleanedBody,
                            link: urlString
                        )
                    }
                    saveToCache(urlString: urlString, content: fullFormatted, storeInMemory: false)
                    return fullFormatted
                }
            }
        } catch {
            AppLogger.shared.log("Reader mode web extraction error: \(error.localizedDescription)", level: .warning, category: .network, details: urlString)
        }

        // 3. Fallback to feed content if web extraction failed
        if let fallbackContent, !fallbackContent.isEmpty {
            let formatted = formatFeedContentAsReaderHTML(
                title: title ?? "",
                author: author,
                pubDate: pubDate,
                htmlContent: fallbackContent,
                link: urlString
            )
            return formatted
        }

        return nil
    }

    private func extractArticleHTML(from rawHTML: String, baseURL: URL) -> String? {
        var html = rawHTML

        // 1. Remove non-content tags: script, style, noscript, iframe, svg, nav, footer, header, aside, comments
        let removePatterns = [
            #"<script[\s\S]*?</script>"#,
            #"<style[\s\S]*?</style>"#,
            #"<noscript[\s\S]*?</noscript>"#,
            #"<nav[\s\S]*?</nav>"#,
            #"<footer[\s\S]*?</footer>"#,
            #"<header[\s\S]*?</header>"#,
            #"<aside[\s\S]*?</aside>"#,
            #"<!--[\s\S]*?-->"#
        ]

        for pattern in removePatterns {
            html = html.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        // 2. Multi-Candidate Container Scoring: search for article, main, or prominent content classes
        let candidatePatterns = [
            #"<article[\s\S]*?</article>"#,
            #"<main[\s\S]*?</main>"#,
            #"<div[^>]*class=["'][^"']*(?:entry-content|article-body|post-content|story-body|article-content|article__body|main-content|story-text)[^"']*["'][\s\S]*?</div>"#,
            #"<section[^>]*class=["'][^"']*(?:entry-content|article-body|post-content|story-body|article-content|article__body)[^"']*["'][\s\S]*?</section>"#
        ]

        var bestCandidate: String?
        var bestScore: Int = 0

        for pattern in candidatePatterns {
            let matchedBlocks = matches(for: pattern, in: html)
            for block in matchedBlocks {
                let plainText = block.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines)
                if plainText.count > bestScore {
                    bestScore = plainText.count
                    bestCandidate = block
                }
            }
        }

        if let bestCandidate, bestScore >= 300 {
            return sanitize(bestCandidate, baseURL: baseURL)
        }

        // 3. Fallback: extract all paragraphs, headings, blockquotes, and lists
        let paragraphBlocks = matches(for: #"<(?:p|h[1-6]|blockquote|ul|ol|pre)[\s\S]*?</(?:p|h[1-6]|blockquote|ul|ol|pre)>"#, in: html)
        if !paragraphBlocks.isEmpty {
            let joined = paragraphBlocks.joined(separator: "\n")
            let plainText = joined.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines)
            if plainText.count >= 250 {
                return sanitize(joined, baseURL: baseURL)
            }
        }

        return nil
    }

    private func sanitize(_ content: String, baseURL: URL) -> String {
        var cleaned = content.replacingOccurrences(of: #"style=["'][^"']*["']"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"class=["'][^"']*["']"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"onclick=["'][^"']*["']"#, with: "", options: .regularExpression)

        // Resolve relative img src URLs to absolute URLs so images render properly in WKWebView
        if let host = baseURL.host, let scheme = baseURL.scheme {
            let basePrefix = "\(scheme)://\(host)"
            cleaned = cleaned.replacingOccurrences(
                of: #"src="/([^"]+)""#,
                with: "src=\"\(basePrefix)/$1\"",
                options: .regularExpression
            )
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(for regex: String, in text: String) -> [String] {
        do {
            let re = try NSRegularExpression(pattern: regex, options: [.caseInsensitive])
            let nsString = text as NSString
            let results = re.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            return results.map { nsString.substring(with: $0.range) }
        } catch {
            return []
        }
    }

    // MARK: - Cache Management & Quota Enforcement

    var diskCacheSizeBytes: Int64 {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for file in files {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func clearDiskCache() {
        memoryCache.removeAllObjects()
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fm.removeItem(at: file)
            }
        }
    }

    func cleanupDiskCache(olderThanDays days: Int = 30, preservedLinks: Set<String> = []) {
        guard days > 0 else { return }
        let cutoffDate = Date().addingTimeInterval(-Double(days * 86400))
        let preservedFilenames = Set(preservedLinks.map { "\(cacheKey(for: $0)).html" })
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }

        var removedCount = 0
        for file in files {
            let filename = file.lastPathComponent
            if preservedFilenames.contains(filename) { continue }
            if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate,
               modDate < cutoffDate {
                try? fm.removeItem(at: file)
                removedCount += 1
            }
        }
        if removedCount > 0 {
            AppLogger.shared.log("Cleaned up \(removedCount) stale reader cache files from disk", level: .info, category: .storage)
        }
    }

    func enforceQuota(maxSizeBytes: Int64 = 150 * 1024 * 1024, preservedLinks: Set<String> = []) {
        let currentSize = diskCacheSizeBytes
        guard currentSize > maxSizeBytes else { return }

        let targetSize = Int64(Double(maxSizeBytes) * 0.8) // Reduce to 80% of max
        let preservedFilenames = Set(preservedLinks.map { "\(cacheKey(for: $0)).html" })
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        // Sort files by modification date ascending (oldest first - LRU)
        let sortedFiles = files.sorted { f1, f2 in
            let d1 = (try? f1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let d2 = (try? f2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return d1 < d2
        }

        var reclaimedBytes: Int64 = 0
        var remainingSize = currentSize

        for file in sortedFiles {
            guard remainingSize > targetSize else { break }
            let filename = file.lastPathComponent
            if preservedFilenames.contains(filename) { continue }

            if let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                try? fm.removeItem(at: file)
                remainingSize -= Int64(size)
                reclaimedBytes += Int64(size)
            }
        }

        if reclaimedBytes > 0 {
            AppLogger.shared.log("Reader disk cache LRU quota enforced: reclaimed \(reclaimedBytes / 1024 / 1024) MB", level: .info, category: .storage)
        }
    }
}
