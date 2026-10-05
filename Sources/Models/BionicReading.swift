import Foundation

// Bolds the first letters of every word so the eye can skim. Works on AttributedString so links and code
// keep their look; the HTML formatter in WebView.swift stays for the web-based reader.

enum BionicReading {
    /// How many leading characters of a word of `length` characters are emphasised.
    static func boldLength(forWordLength length: Int) -> Int {
        switch length {
        case ...1: return 0
        case 2...3: return 1
        case 4...6: return 2
        case 7...9: return 3
        default: return max(3, length / 2)
        }
    }

    static func apply(to text: AttributedString) -> AttributedString {
        var result = text
        var boldRanges: [Range<AttributedString.Index>] = []

        for run in text.runs {
            // Links and code stay as they are.
            if run.link != nil { continue }
            if let intent = run.inlinePresentationIntent, intent.contains(.code) { continue }

            let runText = text[run.range]
            var wordStart: AttributedString.Index?
            var length = 0

            func flush(at end: AttributedString.Index) {
                guard let start = wordStart else { return }
                let count = boldLength(forWordLength: length)
                if count > 0 {
                    var cursor = start
                    var advanced = 0
                    while advanced < count, cursor < end {
                        cursor = text.characters.index(after: cursor)
                        advanced += 1
                    }
                    boldRanges.append(start..<cursor)
                }
                wordStart = nil
                length = 0
            }

            var index = runText.startIndex
            while index < runText.endIndex {
                let character = runText.characters[index]
                if character.isLetter || character.isNumber {
                    if wordStart == nil { wordStart = index }
                    length += 1
                } else {
                    flush(at: index)
                }
                index = runText.characters.index(after: index)
            }
            flush(at: run.range.upperBound)
        }

        for range in boldRanges {
            let existing = result[range].inlinePresentationIntent ?? []
            result[range].inlinePresentationIntent = existing.union(.stronglyEmphasized)
        }
        return result
    }
}
