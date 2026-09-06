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
}

extension String {
    func decodingHTMLEntities() -> String {
        HTMLCleaner.decodeEntities(self)
    }

    func strippingHTML() -> String {
        HTMLCleaner.stripHTMLAndDecode(self)
    }
}
