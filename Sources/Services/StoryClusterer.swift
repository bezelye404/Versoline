import Foundation

/// Finds the same news story told by several feeds, from titles and the first words of the summary only.
///
/// Turkish news is full of one event published by ten sources within the hour. Items are compared as TF-IDF vectors
/// of word stems (a word's first five letters stand in for stemming: `Husilere`, `Husiler` and `Husilerin` all become
/// `husil`), and items join the story whose combined vector they are most similar to, as long as they were published
/// close in time. Everything is computed locally from data already in memory, nothing is stored, and no model is loaded.
enum StoryClusterer {

    struct Story: Equatable, Sendable {
        /// The item shown for the story, then the others, newest first.
        let memberIDs: [UUID]
        let feedCount: Int
        var leadID: UUID { memberIDs[0] }
        var size: Int { memberIDs.count }
    }

    struct Settings: Sendable {
        /// Cosine similarity at which an item joins a story.
        var threshold: Float = 0.45
        /// Multiplier when both items name numbers and share none.
        var disjointNumbersFactor: Float = 0.6
        /// Items further apart in time than this are never the same story.
        var window: TimeInterval = 36 * 3600
        /// Only items this recent are looked at, so the work stays small however big the library is.
        var horizon: TimeInterval = 48 * 3600
        /// Feeds whose item should represent a story when it has one (the user's pinned feeds).
        var preferredFeeds: Set<UUID> = []
    }

    private static let stopWords: Set<String> = [
        // Turkish
        "ve", "ile", "icin", "bir", "bu", "su", "o", "de", "da", "ki", "mi", "mu", "gibi", "kadar", "daha", "en", "cok",
        "ama", "fakat", "ancak", "veya", "ya", "hem", "ise", "olan", "oldu", "olarak", "etti", "edildi", "ediyor", "var",
        "yok", "son", "dakika", "haber", "haberi", "haberler", "flas", "video", "foto", "galeri", "canli", "yayin",
        "iste", "iddia", "aciklama", "aciklandi", "acikladi", "dedi", "yapti", "yapildi", "sonra", "once", "gore",
        "nin", "nun", "in", "un", "den", "dan", "ten", "tan", "ne", "nasil", "neden", "kim", "hangi",
        // English
        "the", "and", "for", "with", "from", "that", "this", "has", "have", "are", "was", "were", "will", "after",
        "before", "over", "into", "about", "its", "his", "her", "new", "says", "say",
    ]

    /// Lower-case, without diacritics, with Turkish dotless i folded to i. Plain Swift: the Foundation call that does
    /// this bridges every string to NSString, which is slow and heavy when run for every item.
    static func fold(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            switch scalar {
            case "ç": result.append("c")
            case "ğ": result.append("g")
            case "ı": result.append("i")
            case "ö": result.append("o")
            case "ş": result.append("s")
            case "ü": result.append("u")
            case "â", "á", "à", "ä": result.append("a")
            case "î", "í", "ì", "ï": result.append("i")
            case "û", "ú", "ù": result.append("u")
            case "é", "è", "ê", "ë": result.append("e")
            case "ó", "ò", "ô": result.append("o")
            case "\u{0300}"..."\u{036F}": continue   // combining marks, e.g. the dot of a decomposed İ
            default: result.append(scalar)
            }
        }
        return String(result)
    }

    /// The stems of the words in a text: apostrophe suffixes dropped (`Yemen'de` is `yemen`), short and common words
    /// left out, numbers kept (they tell stories apart: "3 killed" and "5 killed" are different events).
    static func stems(of text: String) -> [String] {
        var result: [String] = []
        for rawWord in fold(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }) {
            var word = Substring(rawWord)
            if let cut = word.firstIndex(where: { $0 == "'" || $0 == "’" }) { word = word[..<cut] }
            guard !word.isEmpty else { continue }
            let isNumber = word.allSatisfy(\.isNumber)
            if !isNumber, word.count < 3 { continue }
            if stopWords.contains(String(word)) { continue }
            result.append(String(word.prefix(5)))
        }
        return result
    }

    //
    // Words are turned into small integers first: comparing and hashing `Int32`s instead of strings keeps the work
    // (and the memory it leaves behind in the heap) a fraction of what string keys cost.

    private typealias Term = Int32
    private typealias Weights = [Term: Float]

    private static func norm(_ weights: Weights) -> Float {
        weights.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
    }

    private static func dot(_ lhs: Weights, _ rhs: Weights) -> Float {
        let (small, large) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        var sum: Float = 0
        for (key, value) in small { if let match = large[key] { sum += value * match } }
        return sum
    }

    private struct Candidate {
        let id: UUID
        let feedID: UUID
        let snippetLength: Int
        let date: Date
        let termFrequency: [Term: Float]   // title words counted double
        let numbers: Set<Term>             // numbers in the title
    }

    private struct Cluster {
        var members: [Int]        // indexes into the candidates
        var sum: Weights
        var newest: Date
        var numbers: Set<Term>
    }

    /// Stories with at least two items, most sources first. `now` is only used to leave out old items.
    static func stories(in items: [FeedItem], now: Date = Date(), settings: Settings = Settings()) -> [Story] {
        let cutoff = now.addingTimeInterval(-settings.horizon)
        var vocabulary: [String: Term] = [:]
        func term(_ stem: String) -> Term {
            if let known = vocabulary[stem] { return known }
            let created = Term(vocabulary.count)
            vocabulary[stem] = created
            return created
        }

        var candidates: [Candidate] = []
        for item in items {
            guard let date = item.pubDate, date >= cutoff, date <= now.addingTimeInterval(3600), !item.isPodcast else { continue }
            let titleStems = stems(of: item.title)
            var tf: [Term: Float] = [:]
            for stem in titleStems { tf[term(stem), default: 0] += 2 }
            for stem in stems(of: String(item.snippet.prefix(160))) { tf[term(stem), default: 0] += 1 }
            guard tf.count >= 3 else { continue }
            let numbers = Set(titleStems.filter { $0.allSatisfy(\.isNumber) }.map(term))
            candidates.append(Candidate(id: item.id, feedID: item.feedId, snippetLength: item.snippet.count,
                                        date: date, termFrequency: tf, numbers: numbers))
        }
        guard candidates.count >= 2 else { return [] }

        // Inverse document frequency over the candidates: words in many stories ("Erdogan", "Turkiye") count less.
        var documentFrequency = [Int](repeating: 0, count: vocabulary.count)
        for candidate in candidates { for term in candidate.termFrequency.keys { documentFrequency[Int(term)] += 1 } }
        let total = Float(candidates.count)
        let idf: [Float] = documentFrequency.map { log(1 + total / Float(max($0, 1))) }

        var clusters: [Cluster] = []
        var index: [Term: Set<Int>] = [:]   // word -> clusters that contain it

        for position in candidates.indices.sorted(by: { candidates[$0].date < candidates[$1].date }) {
            let candidate = candidates[position]
            var own: Weights = [:]
            own.reserveCapacity(candidate.termFrequency.count)
            for (term, tf) in candidate.termFrequency { own[term] = (1 + log(tf)) * idf[Int(term)] }
            let ownNorm = norm(own)
            guard ownNorm > 0 else { continue }

            var best: (cluster: Int, score: Float)?
            var tried = Set<Int>()
            for term in candidate.termFrequency.keys {
                for clusterIndex in index[term] ?? [] where tried.insert(clusterIndex).inserted {
                    let cluster = clusters[clusterIndex]
                    guard candidate.date.timeIntervalSince(cluster.newest) <= settings.window else { continue }
                    var score = dot(own, cluster.sum) / (ownNorm * max(norm(cluster.sum), 0.0001))
                    // "3 killed" and "5 killed" are different events: stories that both give numbers but no common one.
                    if !candidate.numbers.isEmpty, !cluster.numbers.isEmpty, candidate.numbers.isDisjoint(with: cluster.numbers) {
                        score *= settings.disjointNumbersFactor
                    }
                    if score >= settings.threshold, score > (best?.score ?? 0) { best = (clusterIndex, score) }
                }
            }

            if let best {
                clusters[best.cluster].members.append(position)
                for (term, weight) in own {
                    clusters[best.cluster].sum[term, default: 0] += weight
                    index[term, default: []].insert(best.cluster)
                }
                clusters[best.cluster].newest = max(clusters[best.cluster].newest, candidate.date)
                clusters[best.cluster].numbers.formUnion(candidate.numbers)
            } else {
                clusters.append(Cluster(members: [position], sum: own, newest: candidate.date, numbers: candidate.numbers))
                for term in own.keys { index[term, default: []].insert(clusters.count - 1) }
            }
        }

        return clusters
            .filter { $0.members.count >= 2 }
            .map { story(from: $0.members.map { candidates[$0] }, settings: settings) }
            .sorted { lhs, rhs in lhs.feedCount != rhs.feedCount ? lhs.feedCount > rhs.feedCount : lhs.size > rhs.size }
    }

    private static func story(from members: [Candidate], settings: Settings) -> Story {
        // The lead is the item of a preferred feed if there is one, otherwise the most informative (longest summary).
        let lead = members.max { lhs, rhs in
            let lp = settings.preferredFeeds.contains(lhs.feedID), rp = settings.preferredFeeds.contains(rhs.feedID)
            if lp != rp { return !lp }
            if lhs.snippetLength != rhs.snippetLength { return lhs.snippetLength < rhs.snippetLength }
            return lhs.date < rhs.date
        }!
        let others = members.filter { $0.id != lead.id }.sorted { $0.date > $1.date }
        return Story(memberIDs: [lead.id] + others.map(\.id), feedCount: Set(members.map(\.feedID)).count)
    }
}
