import Foundation

@MainActor
final class ReaderModeExtractor {

    static let shared = ReaderModeExtractor()

    private var articleCache: [String: String] = [:]

    private init() {}

    func extract(from urlString: String) async -> String? {
        if let cached = articleCache[urlString] {
            return cached
        }

        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
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
                articleCache[urlString] = cleaned
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
        // Strip out display:none, onclick, inline style tags that might break layout
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
}
