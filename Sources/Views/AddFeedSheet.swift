import SwiftUI

enum AddFeedTab: String, CaseIterable, Identifiable {
    case customURL
    case curatedCatalog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .customURL:
            return String(localized: "Custom URL")
        case .curatedCatalog:
            return String(localized: "Curated Catalog (rss.md)")
        }
    }

    var iconName: String {
        switch self {
        case .customURL:
            return "link"
        case .curatedCatalog:
            return "sparkles.rectangle.stack"
        }
    }
}

struct AddFeedSheet: View {

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var initialTab: AddFeedTab = .customURL

    @State private var selectedTab: AddFeedTab
    @State private var feedURL: String = ""
    @State private var isValidating: Bool = false

    // Catalog state
    @State private var searchText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var addingFeedURLs: Set<String> = []

    private let curatedManager = CuratedFeedManager.shared

    init(initialTab: AddFeedTab = .customURL) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    private var filteredCuratedFeeds: [(category: String, feed: CuratedFeed)] {
        let all = curatedManager.allFeeds()
        return all.filter { item in
            if let cat = selectedCategory, item.category != cat {
                return false
            }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                return item.feed.title.lowercased().contains(q) ||
                       item.feed.url.lowercased().contains(q) ||
                       item.category.lowercased().contains(q)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented Mode Selector
            Picker("Mode", selection: $selectedTab) {
                ForEach(AddFeedTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            if selectedTab == .customURL {
                customURLView
            } else {
                curatedCatalogView
            }
        }
        .frame(
            width: selectedTab == .curatedCatalog ? 580 : 460,
            height: selectedTab == .curatedCatalog ? 520 : 440
        )
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }

    // MARK: - Custom URL View

    private var customURLView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.secondary)

                        Text("Add Feed")
                            .font(.title3.weight(.semibold))

                        Text("Enter an RSS or Atom feed URL.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)

                    // Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Feed URL")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        TextField("https://example.com/feed.xml", text: $feedURL)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                addFeed()
                            }
                    }

                    // Discovery Banner to Curated Catalog
                    Button {
                        selectedTab = .curatedCatalog
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.tint.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "sparkles.rectangle.stack")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.tint)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Browse Curated Feeds (rss.md)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Text("\(curatedManager.totalFeedCount)+ Feeds")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.tint)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.tint.opacity(0.1), in: Capsule())
                                }

                                Text("Over 100+ popular feeds in Tech, News, Gaming & more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // Quick Suggestions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Example Feeds")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)

                        VStack(spacing: 4) {
                            suggestionButton("BBC News – World", url: "http://feeds.bbci.co.uk/news/world/rss.xml")
                            suggestionButton("Techcrunch", url: "http://feeds.feedburner.com/Techcrunch")
                            suggestionButton("The Verge", url: "https://www.theverge.com/rss/index.xml")
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    addFeed()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Curated Catalog View

    private var curatedCatalogView: some View {
        VStack(spacing: 0) {
            // Search Bar & Filter Bar
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField(String(localized: "Search 100+ feeds..."), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Category Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        categoryFilterChip(
                            title: String(localized: "All"),
                            count: curatedManager.totalFeedCount,
                            icon: "square.grid.2x2",
                            isSelected: selectedCategory == nil
                        ) {
                            selectedCategory = nil
                        }

                        ForEach(curatedManager.categories) { cat in
                            categoryFilterChip(
                                title: localizedCategory(cat.category),
                                count: cat.feeds.count,
                                icon: cat.iconName,
                                isSelected: selectedCategory == cat.category
                            ) {
                                selectedCategory = cat.category
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Feed List
            let items = filteredCuratedFeeds
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No results found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items, id: \.feed.url) { item in
                            curatedFeedRow(feed: item.feed, category: item.category)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }

            Divider()

            // Catalog Footer
            HStack {
                Text(String(localized: "Curated from rss.md (by @joshuawalcher)"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(String(localized: "Done")) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Row & Chip Components

    private func curatedFeedRow(feed: CuratedFeed, category: String) -> some View {
        let isAlreadyAdded = store.feeds.contains(where: { $0.url == feed.url })
        let isCurrentlyAdding = addingFeedURLs.contains(feed.url)

        return HStack(spacing: 12) {
            // Category Icon
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 32, height: 32)
                Image(systemName: iconForCategory(category))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.system(.body, design: .default, weight: .medium))
                    .lineLimit(1)

                Text(URL(string: feed.url)?.host ?? feed.url)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if isAlreadyAdded {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text(String(localized: "Added"))
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.1), in: Capsule())
            } else if isCurrentlyAdding {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 48)
            } else {
                Button {
                    addCurated(feed: feed)
                } label: {
                    Label(String(localized: "Add"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func categoryFilterChip(title: String, count: Int, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func suggestionButton(_ title: String, url: String) -> some View {
        Button {
            feedURL = url
        } label: {
            HStack {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.caption)
                Spacer()
                Text(URL(string: url)?.host ?? url)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(0.5))
        )
    }

    // MARK: - Actions

    private func addFeed() {
        guard !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var urlString = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        isValidating = true

        Task {
            await store.addFeed(url: urlString)
            isValidating = false
            if store.errorMessage == nil {
                dismiss()
            }
        }
    }

    private func addCurated(feed: CuratedFeed) {
        addingFeedURLs.insert(feed.url)
        Task {
            await store.addFeed(url: feed.url)
            addingFeedURLs.remove(feed.url)
        }
    }

    private func iconForCategory(_ category: String) -> String {
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

    private func localizedCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "news": return String(localized: "News")
        case "sports": return String(localized: "Sports")
        case "technology": return String(localized: "Technology")
        case "business": return String(localized: "Business")
        case "politics": return String(localized: "Politics")
        case "gaming": return String(localized: "Gaming")
        default: return category
        }
    }
}
