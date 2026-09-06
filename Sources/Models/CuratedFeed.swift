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
        switch category.lowercased() {
        case "news": return "newspaper"
        case "sports": return "sportscourt"
        case "technology": return "laptopcomputer"
        case "business": return "chart.line.uptrend.xyaxis"
        case "politics": return "building.columns"
        case "gaming": return "gamecontroller"
        default: return "dot.radiowaves.up.forward"
        }
    }
}
