import SwiftUI

/// Rules for articles as they arrive: in one feed, or in all of them, articles containing a word are marked as read or
/// bookmarked. Muted keywords (the Filters page) hide articles; rules never do.
struct RulesSettingsTab: View {

    @Environment(FeedStore.self) private var store
    @AppStorage(FeedRules.defaultsKey) private var rulesJSON = ""

    @State private var feedID: UUID?
    @State private var keyword = ""
    @State private var action: FeedRule.Action = .markRead
    @State private var appliedCount: Int?

    private var rules: [FeedRule] { FeedRules.decode(rulesJSON) }

    var body: some View {
        VStack(spacing: 12) {
            Text("Rules run on new articles when feeds refresh. They mark matching articles as read or bookmark them; nothing is hidden or deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Picker("", selection: $feedID) {
                    Text("All Feeds").tag(UUID?.none)
                    ForEach(store.feeds) { feed in
                        Text(feed.title).tag(UUID?.some(feed.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)

                TextField("Title or summary contains...", text: $keyword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addRule)

                Picker("", selection: $action) {
                    Text("Mark as Read").tag(FeedRule.Action.markRead)
                    Text("Bookmark").tag(FeedRule.Action.bookmark)
                }
                .labelsHidden()
                .frame(maxWidth: 120)

                Button("Add", action: addRule)
                    .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if rules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No rules yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(rules) { rule in
                        HStack(spacing: 8) {
                            Image(systemName: rule.action == .markRead ? "checkmark.circle" : "star")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: "\u{201C}\(rule.keyword)\u{201D}")
                                    .font(.callout)
                                Text(verbatim: "\(feedName(rule.feedID)) \u{2192} \(rule.action == .markRead ? String(localized: "Mark as Read") : String(localized: "Bookmark"))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                remove(rule)
                            } label: {
                                Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button("Apply to Existing Articles") {
                        appliedCount = store.applyRulesToExistingArticles()
                    }
                    if let appliedCount {
                        Text(String(format: String(localized: "%d articles changed"), appliedCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(18)
    }

    private func feedName(_ id: UUID?) -> String {
        guard let id else { return String(localized: "All Feeds") }
        return store.feed(for: id)?.title ?? String(localized: "Removed feed")
    }

    private func addRule() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rulesJSON = FeedRules.encode(rules + [FeedRule(feedID: feedID, keyword: trimmed, action: action)])
        keyword = ""
        appliedCount = nil
    }

    private func remove(_ rule: FeedRule) {
        rulesJSON = FeedRules.encode(rules.filter { $0.id != rule.id })
        appliedCount = nil
    }
}
