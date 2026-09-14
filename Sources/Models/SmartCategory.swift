import Foundation
import SwiftUI

// MARK: - Smart Category Model

enum SmartCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case news          = "news"
    case technology    = "technology"
    case science       = "science"
    case finance       = "finance"
    case sports        = "sports"
    case culture       = "culture"
    case entertainment = "entertainment"
    case lifestyle     = "lifestyle"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .news:
            return String(localized: "News & Agenda")
        case .technology:
            return String(localized: "Technology")
        case .science:
            return String(localized: "Science")
        case .finance:
            return String(localized: "Economy & Finance")
        case .sports:
            return String(localized: "Sports")
        case .culture:
            return String(localized: "Culture & Arts")
        case .entertainment:
            return String(localized: "Entertainment & Games")
        case .lifestyle:
            return String(localized: "Lifestyle & Health")
        }
    }

    var systemImage: String {
        switch self {
        case .news:          return "newspaper.fill"
        case .technology:    return "cpu.fill"
        case .science:       return "atom"
        case .finance:       return "chart.line.uptrend.xyaxis"
        case .sports:        return "figure.run"
        case .culture:       return "paintpalette.fill"
        case .entertainment: return "gamecontroller.fill"
        case .lifestyle:     return "leaf.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .news:          return Color(red: 0.18, green: 0.50, blue: 0.92) // Editorial Blue
        case .technology:    return Color(red: 0.12, green: 0.65, blue: 0.72) // Teal Cyan
        case .science:       return Color(red: 0.58, green: 0.38, blue: 0.88) // Purple
        case .finance:       return Color(red: 0.22, green: 0.68, blue: 0.42) // Sage Green
        case .sports:        return Color(red: 0.92, green: 0.52, blue: 0.20) // Terracotta Orange
        case .culture:       return Color(red: 0.85, green: 0.35, blue: 0.55) // Dusty Rose
        case .entertainment: return Color(red: 0.88, green: 0.30, blue: 0.30) // Crimson
        case .lifestyle:     return Color(red: 0.20, green: 0.70, blue: 0.58) // Mint
        }
    }
}

// MARK: - Smart Category Classifier (Zero Memory Overhead / O(1) Rule Pipeline)

@MainActor
enum SmartCategoryClassifier {

    // Cache mapping for curated feed URLs to their resolved SmartCategory
    private static let curatedCategoryMap: [String: SmartCategory] = {
        var map: [String: SmartCategory] = [:]
        let curated = CuratedFeedManager.shared.allFeeds()
        for entry in curated {
            let catName = entry.category.lowercased()
            let resolved: SmartCategory?
            if catName.contains("spor") || catName.contains("sport") {
                resolved = .sports
            } else if catName.contains("teknoloji") || catName.contains("technology") {
                resolved = .technology
            } else if catName.contains("bilim") || catName.contains("science") {
                resolved = .science
            } else if catName.contains("ekonomi") || catName.contains("finans") || catName.contains("business") || catName.contains("iş dünyası") {
                resolved = .finance
            } else if catName.contains("gündem") || catName.contains("news") || catName.contains("politics") {
                resolved = .news
            } else if catName.contains("kültür") || catName.contains("sanat") || catName.contains("culture") {
                resolved = .culture
            } else if catName.contains("eğlence") || catName.contains("gaming") || catName.contains("subreddit") {
                resolved = .entertainment
            } else if catName.contains("yaşam") || catName.contains("life") {
                resolved = .lifestyle
            } else {
                resolved = nil
            }
            if let resolved {
                map[entry.feed.url.lowercased()] = resolved
            }
        }
        return map
    }()

    static func classify(feed: Feed) -> SmartCategory? {
        // Tier 1: Check curated catalog
        if let match = curatedCategoryMap[feed.url.lowercased()] {
            return match
        }

        // Tier 2: Check feed URL and title metadata
        let feedMeta = "\(feed.title) \(feed.url)".lowercased()
        return matchFeedMetadata(feedMeta)
    }

    static func classify(item: FeedItem, feed: Feed?) -> SmartCategory? {
        // Tier 1: Check feed URL against curated catalog lookup (Instant exact hit)
        if let feedURL = feed?.url.lowercased(), let match = curatedCategoryMap[feedURL] {
            return match
        }

        // Tier 2: Check RSS/Atom native <category> tag if publisher specified one
        if let tag = item.category?.lowercased(), !tag.isEmpty {
            if let match = matchCategoryWord(tag) {
                return match
            }
        }

        // Tier 3: Check Feed URL and Feed Title metadata
        if let feed {
            let feedTitleLower = feed.title.lowercased()
            let feedURLLower = feed.url.lowercased()
            let feedMeta = "\(feedTitleLower) \(feedURLLower)"

            if let match = matchFeedMetadata(feedMeta) {
                return match
            }
        }

        // Tier 4: Article Title & Snippet keyword matching
        let articleText = "\(item.title) \(item.snippet)".lowercased()
        return matchContentKeywords(articleText)
    }

    private static func matchCategoryWord(_ tag: String) -> SmartCategory? {
        if tag.contains("spor") || tag.contains("sport") || tag.contains("futbol") || tag.contains("football") || tag.contains("basket") {
            return .sports
        }
        if tag.contains("tech") || tag.contains("teknoloji") || tag.contains("yazılım") || tag.contains("software") || tag.contains("ai") || tag.contains("hardware") {
            return .technology
        }
        if tag.contains("bilim") || tag.contains("science") || tag.contains("uzay") || tag.contains("space") || tag.contains("fizik") || tag.contains("arkeo") {
            return .science
        }
        if tag.contains("ekonomi") || tag.contains("finans") || tag.contains("finance") || tag.contains("business") || tag.contains("borsa") || tag.contains("market") {
            return .finance
        }
        if tag.contains("gündem") || tag.contains("haber") || tag.contains("news") || tag.contains("politika") || tag.contains("politics") || tag.contains("world") || tag.contains("dünya") {
            return .news
        }
        if tag.contains("kültür") || tag.contains("sanat") || tag.contains("culture") || tag.contains("art") || tag.contains("kitap") || tag.contains("book") || tag.contains("edebiyat") {
            return .culture
        }
        if tag.contains("oyun") || tag.contains("game") || tag.contains("gaming") || tag.contains("eğlence") || tag.contains("entertainment") || tag.contains("movie") || tag.contains("dizi") || tag.contains("film") {
            return .entertainment
        }
        if tag.contains("yaşam") || tag.contains("life") || tag.contains("sağlık") || tag.contains("health") || tag.contains("gastronomi") || tag.contains("yemek") || tag.contains("travel") || tag.contains("gezi") {
            return .lifestyle
        }
        return nil
    }

    private static func matchFeedMetadata(_ meta: String) -> SmartCategory? {
        // Sports feed markers
        if meta.contains("/spor") || meta.contains("sports") || meta.contains("fotomac") || meta.contains("fotospor") || meta.contains("fanatik") || meta.contains("basketdergisi") || meta.contains("aspor") || meta.contains("espn") || meta.contains("goal.com") || meta.contains("theathletic") || meta.contains("nba") {
            return .sports
        }
        // Tech feed markers
        if meta.contains("/teknoloji") || meta.contains("technology") || meta.contains("technopat") || meta.contains("webtekno") || meta.contains("webrazzi") || meta.contains("shiftdelete") || meta.contains("donanimhaber") || meta.contains("techcrunch") || meta.contains("wired") || meta.contains("theverge") || meta.contains("arstechnica") || meta.contains("github") || meta.contains("appleinsider") {
            return .technology
        }
        // Science feed markers
        if meta.contains("/bilim") || meta.contains("science") || meta.contains("evrimagaci") || meta.contains("arkeofili") || meta.contains("gelecekbilimde") || meta.contains("sarkac") || meta.contains("nature.com") || meta.contains("scientificamerican") {
            return .science
        }
        // Finance feed markers
        if meta.contains("/ekonomi") || meta.contains("finans") || meta.contains("bloomberg") || meta.contains("investing") || meta.contains("doviz") || meta.contains("foreks") || meta.contains("midas") || meta.contains("forbes") || meta.contains("economist") || meta.contains("marketwatch") || meta.contains("coindesk") {
            return .finance
        }
        // Culture feed markers
        if meta.contains("kultur") || meta.contains("sanat") || meta.contains("kayiprihtim") || meta.contains("edebiyat") || meta.contains("bantmag") || meta.contains("argonotlar") || meta.contains("book") || meta.contains("kitap") {
            return .culture
        }
        // Entertainment feed markers
        if meta.contains("/oyun") || meta.contains("gaming") || meta.contains("oyungezer") || meta.contains("merlininkazani") || meta.contains("ign") || meta.contains("gamespot") || meta.contains("kotaku") || meta.contains("beyazperde") {
            return .entertainment
        }
        // News feed markers
        if meta.contains("/haber") || meta.contains("news") || meta.contains("gundem") || meta.contains("gazete") || meta.contains("bbc") || meta.contains("reuters") || meta.contains("sozcu") || meta.contains("cumhuriyet") || meta.contains("hurriyet") || meta.contains("t24") || meta.contains("bianet") || meta.contains("nytimes") || meta.contains("theguardian") || meta.contains("apnews") {
            return .news
        }
        // Lifestyle feed markers
        if meta.contains("/yasam") || meta.contains("life") || meta.contains("lifestyle") || meta.contains("saglik") || meta.contains("health") || meta.contains("gastronomi") || meta.contains("yemek") || meta.contains("travel") || meta.contains("gezi") || meta.contains("wellness") {
            return .lifestyle
        }
        return nil
    }

    private static func matchContentKeywords(_ text: String) -> SmartCategory? {
        // High-precision keywords (Turkish & English)
        
        // 1. Sports keywords
        let sportsKeywords = ["süper lig", "şampiyonlar ligi", "premier league", "fenerbahçe", "galatasaray", "beşiktaş", "trabzonspor", "nba", "euroleague", "transfer", "teknik direktör", "gol krallığı", "penaltı", "stadyum", "voleybol", "wimbledon", "formula 1", "grand prix", "olimpiyat", "champions league", "football match", "basketball", "tennis tournament"]
        for kw in sportsKeywords where text.contains(kw) {
            return .sports
        }

        // 2. Finance keywords
        let financeKeywords = ["bist 100", "borsa istanbul", "merkez bankası", "tcmb", "faiz kararı", "enflasyon oranı", "dolar kuru", "euro kuru", "hisse senedi", "kripto para", "bitcoin", "ethereum", "temettü", "bilanço", "halka arz", "fed faiz", "wall street", "stock market", "revenue growth", "interest rate", "cryptocurrency", "bull market", "bear market"]
        for kw in financeKeywords where text.contains(kw) {
            return .finance
        }

        // 3. Technology keywords
        let techKeywords = ["yapay zeka", "büyük dil modeli", "chatgpt", "openai", "deep learning", "akıllı telefon", "işlemci mimarisi", "yazılım geliştirme", "kodlama", "siber güvenlik", "gpu", "nvidia", "apple m4", "apple vision", "ios 18", "macos sequoia", "android 15", "open source", "source code", "developer tool", "firmware", "vulnerability", "cyberattack"]
        for kw in techKeywords where text.contains(kw) {
            return .technology
        }

        // 4. Science keywords
        let scienceKeywords = ["james webb", "hubble teleskobu", "mars keşif", "karadelik", "galaksi", "ötegezegen", "dna dizilimi", "genetik mutasyon", "arkeolojik kazı", "fosil kalıntı", "kuantum bilgisayar", "parçacık fiziği", "cern", "iklim değişikliği", "biyoçeşitlilik", "astronomy", "exoplanet", "quantum physics", "archaeological", "fossil discovery", "solar system"]
        for kw in scienceKeywords where text.contains(kw) {
            return .science
        }

        // 5. Entertainment & Gaming keywords
        let entertainmentKeywords = ["playstation 5", "xbox series", "nintendo switch", "steam deck", "oyun stüdyosu", "gameplay trailer", "vizyona girdi", "gişe hasılatı", "netflix türkiye", "dizi incelemesi", "video game", "box office", "season finale", "oscar ödülleri", "sinema filmi"]
        for kw in entertainmentKeywords where text.contains(kw) {
            return .entertainment
        }

        // 6. Culture & Arts keywords
        let cultureKeywords = ["çağdaş sanat", "resim sergisi", "bienal", "edebiyat ödülü", "yeni roman", "tiyatro oyunu", "opera ve bale", "felsefe sempozyumu", "mimarlık ödülü", "art exhibition", "contemporary art", "literature award", "theater play", "poetry collection"]
        for kw in cultureKeywords where text.contains(kw) {
            return .culture
        }

        // 7. Lifestyle keywords
        let lifestyleKeywords = ["yemek tarifi", "gastronomi", "sağlıklı beslenme", "diyet listesi", "seyahat rehberi", "gezi notları", "yoga ve meditasyon", "ruh sağlığı", "healthy diet", "travel guide", "mindfulness", "wellness"]
        for kw in lifestyleKeywords where text.contains(kw) {
            return .lifestyle
        }

        // 8. News / Agenda keywords
        let newsKeywords = ["cumhurbaşkanı", "bakanlık", "tbmm", "meclis genel kurulu", "başsavcılık", "soruşturma kapsamında", "gözaltına alındı", "tutuklandı", "dışişleri bakanlığı", "beyaz saray", "pentagon", "birleşmiş milletler", "avrupa birliği", "parlamento", "prime minister", "foreign ministry", "united nations", "investigation launched"]
        for kw in newsKeywords where text.contains(kw) {
            return .news
        }

        return nil
    }
}
