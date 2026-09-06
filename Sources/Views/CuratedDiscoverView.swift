import SwiftUI

struct CuratedDiscoverView: View {

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var selectedLanguage: String? = nil // nil = All, "tr", "en"
    @State private var selectedCategory: String? = nil
    @State private var addingFeedURLs: Set<String> = []

    private let curatedManager = CuratedFeedManager.shared

    private var availableCategories: [CuratedFeedCategory] {
        if let lang = selectedLanguage {
            let prefix = lang == "tr" ? "🇹🇷" : "🇬🇧"
            return curatedManager.categories.filter { $0.category.hasPrefix(prefix) }
        }
        return curatedManager.categories
    }

    private var filteredCuratedFeeds: [(category: String, cleanCategory: String, iconName: String, feed: CuratedFeed)] {
        var results: [(String, String, String, CuratedFeed)] = []

        for categoryGroup in availableCategories {
            if let selectedCat = selectedCategory, categoryGroup.category != selectedCat {
                continue
            }

            for feed in categoryGroup.feeds {
                if !searchText.isEmpty {
                    let query = searchText.lowercased()
                    let matchesTitle = feed.title.lowercased().contains(query)
                    let matchesURL = feed.url.lowercased().contains(query)
                    let matchesCat = categoryGroup.cleanCategoryName.lowercased().contains(query)
                    guard matchesTitle || matchesURL || matchesCat else { continue }
                }
                results.append((categoryGroup.category, categoryGroup.cleanCategoryName, categoryGroup.iconName, feed))
            }
        }

        return results
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar: Language and Categories
                filterBar
                Divider()

                // Feed List / Grid
                if filteredCuratedFeeds.isEmpty {
                    emptySearchResults
                } else {
                    feedList
                }
            }
            .navigationTitle(String(localized: "Discover Curated Feeds"))
            .searchable(text: $searchText, prompt: String(localized: "Search feeds, topics, or domains..."))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 480)
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        VStack(spacing: 8) {
            // Language Segment
            HStack(spacing: 12) {
                Picker(String(localized: "Language"), selection: $selectedLanguage) {
                    Text(String(localized: "All Sources")).tag(nil as String?)
                    Text(String(localized: "Turkish")).tag("tr" as String?)
                    Text(String(localized: "English")).tag("en" as String?)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .onChange(of: selectedLanguage) { _, _ in
                    selectedCategory = nil
                }

                Spacer()

                Text(String(format: String(localized: "%d feeds available"), filteredCuratedFeeds.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Category Chips (Horizontal Scroll)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryPill(title: String(localized: "All Topics"), icon: "square.grid.2x2", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }

                    ForEach(availableCategories) { cat in
                        categoryPill(
                            title: cat.cleanCategoryName,
                            icon: cat.iconName,
                            isSelected: selectedCategory == cat.category
                        ) {
                            if selectedCategory == cat.category {
                                selectedCategory = nil
                            } else {
                                selectedCategory = cat.category
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func categoryPill(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feed List

    @ViewBuilder
    private var feedList: some View {
        List {
            ForEach(filteredCuratedFeeds, id: \.feed.url) { item in
                let isAdded = store.feeds.contains(where: { $0.url == item.feed.url })
                let isAdding = addingFeedURLs.contains(item.feed.url)

                HStack(spacing: 12) {
                    FaviconView(hostOrURL: item.feed.url, size: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(item.feed.title)
                                .font(.headline)

                            HStack(spacing: 4) {
                                Image(systemName: item.iconName)
                                    .font(.system(size: 9))
                                Text(item.cleanCategory)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                        }

                        if let host = URL(string: item.feed.url)?.host {
                            Text(host)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if isAdded {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                            Text(String(localized: "Subscribed"))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Capsule())
                    } else {
                        Button {
                            Task {
                                addingFeedURLs.insert(item.feed.url)
                                await store.addFeed(url: item.feed.url)
                                addingFeedURLs.remove(item.feed.url)
                            }
                        } label: {
                            if isAdding {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 60)
                            } else {
                                Label(String(localized: "Subscribe"), systemImage: "plus")
                                    .font(.caption.weight(.medium))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isAdding)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptySearchResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            Text(String(localized: "No feeds match your search."))
                .font(.headline)
                .foregroundStyle(.secondary)
            Button(String(localized: "Clear Filters")) {
                searchText = ""
                selectedCategory = nil
                selectedLanguage = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
