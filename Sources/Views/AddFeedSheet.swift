import SwiftUI

enum AddFeedTab: String, CaseIterable, Identifiable {
    case customURL
    case socialFeeds
    case curatedCatalog
    case podcastSearch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .customURL:
            return String(localized: "Custom URL")
        case .socialFeeds:
            return String(localized: "YouTube & Reddit")
        case .curatedCatalog:
            return String(localized: "Curated Catalog")
        case .podcastSearch:
            return String(localized: "Podcast Search")
        }
    }

    var iconName: String {
        switch self {
        case .customURL:
            return "link"
        case .socialFeeds:
            return "play.rectangle.on.rectangle"
        case .curatedCatalog:
            return "sparkles.rectangle.stack"
        case .podcastSearch:
            return "waveform.and.magnifyingglass"
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
    @State private var selectedFolderId: UUID? = nil

    // Catalog state
    @State private var searchText: String = ""
    @State private var selectedLanguage: String? = nil // nil = All, "tr" = Türkçe, "en" = English
    @State private var selectedCategory: String? = nil
    @State private var addingFeedURLs: Set<String> = []

    private let curatedManager = CuratedFeedManager.shared

    init(initialTab: AddFeedTab = .customURL) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    private var availableCategories: [CuratedFeedCategory] {
        if let lang = selectedLanguage {
            let prefix = lang == "tr" ? "🇹🇷" : "🇬🇧"
            return curatedManager.categories.filter { $0.category.hasPrefix(prefix) }
        }
        return curatedManager.categories
    }

    private var filteredCuratedFeeds: [(category: String, feed: CuratedFeed)] {
        let all = curatedManager.allFeeds()
        return all.filter { item in
            if let lang = selectedLanguage {
                let prefix = lang == "tr" ? "🇹🇷" : "🇬🇧"
                if !item.category.hasPrefix(prefix) { return false }
            }
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

            switch selectedTab {
            case .customURL:
                customURLView
            case .socialFeeds:
                SocialFeedsView(selectedFolderId: selectedFolderId)
            case .curatedCatalog:
                curatedCatalogView
            case .podcastSearch:
                PodcastSearchView(selectedFolderId: selectedFolderId)
            }
        }
        .frame(width: 640, height: 560)
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

                    // Folder Selector (Optional)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Folder (Optional)"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Picker(String(localized: "Folder"), selection: $selectedFolderId) {
                            Text(String(localized: "None (Uncategorized)")).tag(nil as UUID?)
                            ForEach(store.folders) { folder in
                                Text(folder.name).tag(folder.id as UUID?)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // Podcast Search Banner
                    Button {
                        selectedTab = .podcastSearch
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.orange.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "waveform.and.magnifyingglass")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.orange)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(String(localized: "Podcast Search Engine"))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Text(String(localized: "Finder"))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.1), in: Capsule())
                                }

                                Text(String(localized: "Search millions of podcasts and find RSS feeds"))
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
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // YouTube & Reddit Feeds Banner
                    Button {
                        selectedTab = .socialFeeds
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "play.rectangle.on.rectangle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.red)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(String(localized: "YouTube & Reddit Feeds"))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Text(String(localized: "Generator"))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.1), in: Capsule())
                                }

                                Text(String(localized: "Subscribe to channels, playlists, subreddits & users"))
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
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
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
            // Folder Selector for Curated Catalog
            HStack(spacing: 8) {
                Text(String(localized: "Folder (Optional):"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: $selectedFolderId) {
                    Text(String(localized: "None (Uncategorized)")).tag(nil as UUID?)
                    ForEach(store.folders) { folder in
                        Text(folder.name).tag(folder.id as UUID?)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 220)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

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

                // Language Selector Pills
                HStack(spacing: 8) {
                    languageFilterChip(
                        title: String(localized: "All"),
                        count: curatedManager.totalFeedCount,
                        isSelected: selectedLanguage == nil
                    ) {
                        selectedLanguage = nil
                        selectedCategory = nil
                    }

                    let trCount = curatedManager.categories.filter { $0.category.hasPrefix("🇹🇷") }.reduce(0) { $0 + $1.feeds.count }
                    languageFilterChip(
                        title: "🇹🇷 Türkçe",
                        count: trCount,
                        isSelected: selectedLanguage == "tr"
                    ) {
                        selectedLanguage = "tr"
                        selectedCategory = nil
                    }

                    let enCount = curatedManager.categories.filter { $0.category.hasPrefix("🇬🇧") }.reduce(0) { $0 + $1.feeds.count }
                    languageFilterChip(
                        title: "🇬🇧 English",
                        count: enCount,
                        isSelected: selectedLanguage == "en"
                    ) {
                        selectedLanguage = "en"
                        selectedCategory = nil
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Category Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        categoryFilterChip(
                            title: String(localized: "All"),
                            count: availableCategories.reduce(0) { $0 + $1.feeds.count },
                            icon: "square.grid.2x2",
                            isSelected: selectedCategory == nil
                        ) {
                            selectedCategory = nil
                        }

                        ForEach(availableCategories) { cat in
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
                Text(String(localized: "Curated Feed Catalog"))
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
            await store.addFeed(url: urlString, folderId: selectedFolderId)
            isValidating = false
            if store.errorMessage == nil {
                dismiss()
            }
        }
    }

    private func addCurated(feed: CuratedFeed) {
        addingFeedURLs.insert(feed.url)
        Task {
            await store.addFeed(url: feed.url, folderId: selectedFolderId)
            addingFeedURLs.remove(feed.url)
        }
    }

    private func languageFilterChip(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconForCategory(_ category: String) -> String {
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

    private func localizedCategory(_ category: String) -> String {
        let clean = category
            .replacingOccurrences(of: "🇹🇷 ", with: "")
            .replacingOccurrences(of: "🇬🇧 ", with: "")

        switch clean.lowercased() {
        case "news": return String(localized: "News")
        case "sports": return String(localized: "Sports")
        case "technology": return String(localized: "Technology")
        case "business": return String(localized: "Business")
        case "politics": return String(localized: "Politics")
        case "gaming": return String(localized: "Gaming")
        default: return clean
        }
    }
}
