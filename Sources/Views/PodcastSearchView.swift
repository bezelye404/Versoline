import SwiftUI

struct PodcastSearchView: View {

    @Environment(FeedStore.self) private var store
    var selectedFolderId: UUID? = nil
    @State private var searchService = PodcastSearchService.shared
    @State private var query: String = ""
    @State private var addingURLs: Set<String> = []
    @State private var copiedURL: String? = nil
    @State private var debounceTask: Task<Void, Never>? = nil

    private let quickTopics = [
        "Technology",
        "News",
        "Science",
        "Business",
        "Comedy",
        "Design",
        "True Crime",
        "🇹🇷 Türkçe"
    ]

    private func isSubscribed(_ feedURL: String) -> Bool {
        store.feeds.contains { $0.url.trimmingCharacters(in: .whitespacesAndNewlines) == feedURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Search Input Bar
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))

                    TextField("Search podcasts by name, host, or topic...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .onChange(of: query) { _, newQuery in
                            debounceTask?.cancel()
                            debounceTask = Task {
                                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                                guard !Task.isCancelled else { return }
                                searchService.search(query: newQuery)
                            }
                        }

                    if !query.isEmpty {
                        Button {
                            query = ""
                            searchService.clear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Quick Topic Suggestions
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text(String(localized: "Popular:"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        ForEach(quickTopics, id: \.self) { topic in
                            let searchTerm = topic.replacingOccurrences(of: "🇹🇷 ", with: "")
                            Button {
                                query = searchTerm
                                searchService.search(query: searchTerm)
                            } label: {
                                Text(topic)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(query.lowercased() == searchTerm.lowercased() ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08))
                                    .foregroundStyle(query.lowercased() == searchTerm.lowercased() ? Color.accentColor : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // MARK: - Content Area
            Group {
                if searchService.isSearching {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.regular)
                        Text(String(localized: "Searching podcast directory..."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !searchService.results.isEmpty {
                    resultsList
                } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    noResultsView
                } else {
                    idleWelcomeView
                }
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(searchService.results) { podcast in
                    podcastRow(podcast: podcast)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Podcast Row Card

    @ViewBuilder
    private func podcastRow(podcast: PodcastSearchResult) -> some View {
        let subscribed = isSubscribed(podcast.feedURL)
        let isAdding = addingURLs.contains(podcast.feedURL)
        let isCopied = copiedURL == podcast.feedURL

        HStack(alignment: .top, spacing: 14) {
            // Artwork
            AsyncImage(url: URL(string: podcast.artworkURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    ZStack {
                        Color.secondary.opacity(0.12)
                        Image(systemName: "headphones")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    Color.secondary.opacity(0.12)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)

            // Info Column
            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.title)
                    .font(.headline)
                    .lineLimit(2)
                    .textSelection(.enabled)

                if !podcast.author.isEmpty {
                    Text(podcast.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Badges
                HStack(spacing: 6) {
                    if let genre = podcast.genre, !genre.isEmpty {
                        Text(genre)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    if let epCount = podcast.formattedEpisodesCount {
                        Text(epCount)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // RSS Feed URL snippet
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)

                    Text(podcast.feedURL)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 12)

            // Actions Column
            VStack(alignment: .trailing, spacing: 8) {
                // Subscribe Button
                if subscribed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text(String(localized: "Subscribed"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
                } else {
                    Button {
                        subscribeToPodcast(podcast)
                    } label: {
                        if isAdding {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 60)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                Text(String(localized: "Subscribe"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isAdding)
                }

                // Copy RSS Feed URL Button
                Button {
                    copyFeedURL(podcast.feedURL)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(isCopied ? String(localized: "Copied!") : String(localized: "Copy RSS"))
                            .font(.caption2)
                    }
                    .foregroundStyle(isCopied ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Copy RSS Feed URL to clipboard"))
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func subscribeToPodcast(_ podcast: PodcastSearchResult) {
        addingURLs.insert(podcast.feedURL)
        Task {
            await store.addFeed(url: podcast.feedURL, folderId: selectedFolderId)
            addingURLs.remove(podcast.feedURL)
        }
    }

    private func copyFeedURL(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        copiedURL = url
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiedURL == url {
                copiedURL = nil
            }
        }
    }

    // MARK: - Idle & Empty States

    private var idleWelcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color.accentColor)

            Text("Podcast Search Engine & RSS Finder")
                .font(.title3.weight(.semibold))

            Text("Search millions of podcasts from Apple Podcasts directory.\nFind direct RSS feeds, preview episodes, and subscribe with one click.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.quaternary)

            Text(String(localized: "No podcasts found"))
                .font(.headline)

            Text(String(format: String(localized: "We couldn't find any podcast matching \"%@\"."), query))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
