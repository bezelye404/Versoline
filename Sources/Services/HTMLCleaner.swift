import Foundation

enum HTMLCleaner {

    private static let namedEntities: [String: String] = [
        "&amp;": "&",
        "&quot;": "\"",
        "&apos;": "'",
        "&lt;": "<",
        "&gt;": ">",
        "&nbsp;": " ",
        "&ndash;": "–",
        "&mdash;": "—",
        "&lsquo;": "‘",
        "&rsquo;": "’",
        "&sbquo;": "‚",
        "&ldquo;": "“",
        "&rdquo;": "”",
        "&bdquo;": "„",
        "&hellip;": "…",
        "&bull;": "•",
        "&prime;": "′",
        "&Prime;": "″",
        "&copy;": "©",
        "&reg;": "®",
        "&trade;": "™",
        "&euro;": "€",
        "&pound;": "£",
        "&yen;": "¥",
        "&cent;": "¢"
    ]

    private static let decimalEntityRegex = try? NSRegularExpression(pattern: #"&#([0-9]{1,7});"#)
    private static let hexEntityRegex = try? NSRegularExpression(pattern: #"&#[xX]([0-9a-fA-F]{1,6});"#)
    private static let htmlTagRegex = try? NSRegularExpression(pattern: #"<[^>]+>"#)

    /// Decodes both named, decimal, and hex HTML entities into readable Unicode characters.
    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }

        var result = string

        // 1. Replace known named entities
        for (entity, replacement) in namedEntities {
            if result.contains(entity) {
                result = result.replacingOccurrences(of: entity, with: replacement)
            }
        }

        // 2. Replace decimal entities &#1234;
        if let regex = decimalEntityRegex, result.contains("&#") {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                if let codeRange = Range(match.range(at: 1), in: result),
                   let code = UInt32(result[codeRange]),
                   let scalar = UnicodeScalar(code) {
                    let char = String(scalar)
                    if let fullRange = Range(match.range(at: 0), in: result) {
                        result.replaceSubrange(fullRange, with: char)
                    }
                }
            }
        }

        // 3. Replace hex entities &#x1F600;
        if let regex = hexEntityRegex, result.contains("&#x") || result.contains("&#X") {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                if let codeRange = Range(match.range(at: 1), in: result),
                   let code = UInt32(result[codeRange], radix: 16),
                   let scalar = UnicodeScalar(code) {
                    let char = String(scalar)
                    if let fullRange = Range(match.range(at: 0), in: result) {
                        result.replaceSubrange(fullRange, with: char)
                    }
                }
            }
        }

        return result
    }

    /// Strips HTML tags and decodes entities to produce clean plain text.
    static func stripHTMLAndDecode(_ string: String) -> String {
        var text = string

        if let regex = htmlTagRegex, text.contains("<") {
            let nsString = text as NSString
            text = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: nsString.length), withTemplate: " ")
        }

        text = decodeEntities(text)

        // Collapse excess whitespace
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let noiseRegexes: [NSRegularExpression] = {
        let patterns = [
            #"[^\n<]{0,60}google['\u2019]?\s*(?:da|de)?\s*favori[^\n<]{0,100}"#,
            #"linke tıkla[^\n\.<]{0,120}"#,
            #"tıkla ve [^\n\.<]{0,80}"#,
            #"^\s*anasayfa[\s\S]{0,150}?(?:gündem|ekonomi|spor|dünya|yaşam|yerel gündem|teknoloji)[\s\S]{0,80}?\n"#,
            #"\b\d{1,2}:\d{2},\s*\d{1,2}[\/\.]\d{1,2}[\/\.]\d{4}[^\n<]*"#,
            #"paylaş[\s\S]{0,40}(?:facebook|x|whatsapp|linkedin|nsosyal|bağlantıyı kopyala)[\s\S]{0,120}"#,
            #"(?:facebook|twitter|whatsapp|linkedin|telegram|reddit)\s+ile\s+paylaş[^\n<]{0,100}"#,
            #"bizi\s+(?:sosyal medyada|x'te|twitter'da|facebook'ta)\s+takip edin[^\n<]{0,100}"#,
            #"giriş:\s*\d{1,2}\s+[a-zA-ZğüşıöçĞÜŞİÖÇ]+\s+\d{4}[^\n<]*güncelleme:\s*\d{1,2}\s+[a-zA-ZğüşıöçĞÜŞİÖÇ]+\s+\d{4}[^\n<]*"#,
            #"<script[\s\S]*?</script>"#,
            #"<noscript[\s\S]*?</noscript>"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    /// Removes repetitive RSS social sharing footers, clickbait headers, and timestamp boilerplate.
    static func removeBoilerplateNoise(_ string: String) -> String {
        var text = string
        for regex in noiseRegexes {
            let nsText = text as NSString
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length), withTemplate: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let adTagRegexes: [NSRegularExpression] = {
        let patterns = [
            #"<(?:div|section|aside|figure|p|span)[^>]*(?:class|id)=["'][^"']*(?:reklam|adv-|advertisement|ad-banner|banner-ad|sponsor|dfp|google-ad|taboola|outbrain|ins-element|criteo)[^"']*["'][\s\S]*?</(?:div|section|aside|figure|p|span)>"#,
            #"<a[^>]*(?:href|data-href)=["'][^"']*(?:doubleclick|googlesyndication|adclick|adservice|reklam|banner)[^"']*["'][^>]*>[\s\S]*?</a>"#,
            #"<img[^>]*(?:class|alt|src)=["'][^"']*(?:reklam|ad-banner|sponsor|banner)[^"']*["'][^>]*>"#,
            #"<img[^>]*(?:width=["'](?:0|1)["'][^>]*height=["'](?:0|1)["']|height=["'](?:0|1)["'][^>]*width=["'](?:0|1)["'])[^>]*>"#,
            #"<ins[\s\S]*?</ins>"#,
            #"<iframe[^>]*(?:google|doubleclick|taboola|outbrain|criteo|facebook\.com\/plugins|platform\.twitter)[\s\S]*?</iframe>"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    private static let emptyParagraphRegex = try? NSRegularExpression(pattern: #"<p>\s*(?:&nbsp;|\s)*</p>"#, options: [.caseInsensitive])

    /// Removes embedded ad banners, sponsor graphics, tracking pixels and auxiliary iframes.
    static func stripAdvertisementsAndBanners(_ html: String) -> String {
        var text = html
        for regex in adTagRegexes {
            let nsText = text as NSString
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length), withTemplate: "")
        }
        if let emptyPara = emptyParagraphRegex {
            let nsText = text as NSString
            text = emptyPara.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length), withTemplate: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    func decodingHTMLEntities() -> String {
        HTMLCleaner.decodeEntities(self)
    }

    func strippingHTML() -> String {
        HTMLCleaner.stripHTMLAndDecode(self)
    }

    func cleaningRSSBoilerplate() -> String {
        HTMLCleaner.removeBoilerplateNoise(self)
    }

    func strippingAdsAndBanners() -> String {
        HTMLCleaner.stripAdvertisementsAndBanners(self)
    }
}


