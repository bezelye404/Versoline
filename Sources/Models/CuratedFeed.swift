import Foundation

struct CuratedFeed: Identifiable, Hashable, Codable, Sendable {
    var id: String { url }
    let title: String
    let url: String
}

struct CuratedFeedCategory: Identifiable, Hashable, Codable, Sendable {
    var id: String { category }
    let category: String
    let feeds: [CuratedFeed]

    var iconName: String {
        let lower = category.lowercased()
        if lower.contains("bilim") || lower.contains("science") { return "atom" }
        if lower.contains("teknoloji") || lower.contains("technology") { return "laptopcomputer" }
        if lower.contains("gündem") || lower.contains("haber") || lower.contains("news") { return "newspaper" }
        if lower.contains("spor") || lower.contains("sports") { return "sportscourt" }
        if lower.contains("ekonomi") || lower.contains("finans") || lower.contains("business") { return "chart.line.uptrend.xyaxis" }
        if lower.contains("iş") { return "briefcase" }
        if lower.contains("kültür") || lower.contains("sanat") { return "paintpalette" }
        if lower.contains("eğlence") || lower.contains("oyun") || lower.contains("gaming") { return "gamecontroller" }
        if lower.contains("savunma") { return "shield.fill" }
        if lower.contains("yaşam") { return "heart.fill" }
        if lower.contains("politika") || lower.contains("politics") { return "building.columns" }
        return "dot.radiowaves.up.forward"
    }

    var cleanCategoryName: String {
        category.replacingOccurrences(of: "🇹🇷 ", with: "")
                .replacingOccurrences(of: "🇬🇧 ", with: "")
    }
}
