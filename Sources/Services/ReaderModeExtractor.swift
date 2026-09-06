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
        memoryCache.countLimit = 60
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

    func cachedContent(for urlString: String) -> String? {
        let nsKey = urlString as NSString
        if let memory = memoryCache.object(forKey: nsKey) {
            return memory as String
        }

        let diskURL = fileURL(for: urlString)
        if FileManager.default.fileExists(atPath: diskURL.path),
           let diskData = try? Data(contentsOf: diskURL),
           let html = String(data: diskData, encoding: .utf8) {
            memoryCache.setObject(html as NSString, forKey: nsKey)
            return html
        }

        return nil
    }

    func saveToCache(urlString: String, content: String) {
        memoryCache.setObject(content as NSString, forKey: urlString as NSString)
        let diskURL = fileURL(for: urlString)
        Task.detached(priority: .utility) {
            try? content.data(using: .utf8)?.write(to: diskURL, options: .atomic)
        }
    }

    // MARK: - Extraction

    func extract(from urlString: String) async -> String? {
        // 1. Check memory or disk cache first (offline support)
        if let cached = cachedContent(for: urlString) {
            return cached
        }

        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let html = String(decoding: data, as: UTF8.self)
            let cleaned = extractArticleHTML(from: html, baseURL: url)
            if let cleaned, !cleaned.isEmpty {
                saveToCache(urlString: urlString, content: cleaned)
                return cleaned
            }
        } catch {
            AppLogger.shared.log("Reader mode extraction error: \(error.localizedDescription)", level: .warning, category: .network, details: urlString)
        }

        return nil
    }

    private func extractArticleHTML(from rawHTML: String, baseURL: URL) -> String? {
        var html = rawHTML

        // 1. Remove non-content tags: script, style, noscript, iframe, svg, nav, footer, header
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

        // 2. Look for <article> ... </article>
        if let articleMatch = html.range(of: #"<article[\s\S]*?</article>"#, options: [.regularExpression, .caseInsensitive]) {
            let articleContent = String(html[articleMatch])
            return sanitize(articleContent)
        }

        // 3. Look for <main> ... </main>
        if let mainMatch = html.range(of: #"<main[\s\S]*?</main>"#, options: [.regularExpression, .caseInsensitive]) {
            let mainContent = String(html[mainMatch])
            return sanitize(mainContent)
        }

        // 4. Fallback: extract paragraphs
        let pMatches = matches(for: #"<p[\s\S]*?</p>"#, in: html)
        if !pMatches.isEmpty {
            let joined = pMatches.joined(separator: "\n")
            return sanitize(joined)
        }

        return nil
    }

    private func sanitize(_ content: String) -> String {
        var cleaned = content.replacingOccurrences(of: #"style=["'][^"']*["']"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"class=["'][^"']*["']"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"onclick=["'][^"']*["']"#, with: "", options: .regularExpression)
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

    // MARK: - Cache Management

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
}
