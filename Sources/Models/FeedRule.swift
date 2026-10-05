import Foundation

/// "In this feed, articles containing this word are marked as read (or bookmarked) as they arrive."
/// Rules run on the Mac when a refresh brings new articles; they never hide anything (muted keywords do that).
struct FeedRule: Codable, Identifiable, Equatable, Sendable {

    enum Action: String, Codable, CaseIterable, Sendable {
        case markRead
        case bookmark
    }

    var id = UUID()
    /// The feed the rule is for; nil means every feed.
    var feedID: UUID?
    var keyword: String
    var action: Action

    /// Case, accents and the Turkish dotless i do not matter. Looks at the title and the summary.
    func matches(_ item: FeedItem) -> Bool {
        if let feedID, item.feedId != feedID { return false }
        let needle = StoryClusterer.fold(keyword.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return false }
        return StoryClusterer.fold(item.title).contains(needle) || StoryClusterer.fold(item.snippet).contains(needle)
    }
}

enum FeedRules {

    static let defaultsKey = "feedRulesJSON"

    static func decode(_ json: String) -> [FeedRule] {
        guard let data = json.data(using: .utf8), let rules = try? JSONDecoder().decode([FeedRule].self, from: data) else { return [] }
        return rules
    }

    static func encode(_ rules: [FeedRule]) -> String {
        guard let data = try? JSONEncoder().encode(rules) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static var stored: [FeedRule] {
        decode(UserDefaults.standard.string(forKey: defaultsKey) ?? "")
    }

    /// Applies the matching rules to an item; returns whether anything changed.
    @discardableResult
    static func apply(_ rules: [FeedRule], to item: inout FeedItem) -> Bool {
        var changed = false
        for rule in rules where rule.matches(item) {
            switch rule.action {
            case .markRead where !item.isRead:
                item.isRead = true
                changed = true
            case .bookmark where !item.isBookmarked:
                item.isBookmarked = true
                changed = true
            default:
                break
            }
        }
        return changed
    }
}
