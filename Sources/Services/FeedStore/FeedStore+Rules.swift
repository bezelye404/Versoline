import Foundation

extension FeedStore {

    /// Runs the rules over the articles already in the library (new articles get them on arrival). Only unread
    /// articles can be marked read and only unmarked ones bookmarked, so it is safe to run again. Returns how many
    /// articles changed.
    @discardableResult
    func applyRulesToExistingArticles() -> Int {
        let rules = FeedRules.stored
        guard !rules.isEmpty else { return 0 }
        var changed = 0
        for (feedId, feedItems) in items {
            var updated = feedItems
            var feedChanged = false
            for index in updated.indices where FeedRules.apply(rules, to: &updated[index]) {
                changed += 1
                feedChanged = true
            }
            if feedChanged { items[feedId] = updated }
        }
        guard changed > 0 else { return 0 }
        invalidateItemCaches()
        updateCachedCounts()
        updateSmartCategoryCaches()
        save(immediate: false, updateCounts: false)
        AppLogger.shared.log("Rules changed \(changed) existing articles", level: .info, category: .storage)
        return changed
    }
}
