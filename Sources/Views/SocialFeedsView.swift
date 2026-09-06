import SwiftUI

struct SocialFeedsView: View {

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Platform: String, CaseIterable, Identifiable {
        case youtube
        case reddit

        var id: String { rawValue }

        var title: String {
            switch self {
            case .youtube: return "YouTube"
            case .reddit: return "Reddit"
            }
        }

        var icon: String {
            switch self {
            case .youtube: return "play.rectangle.fill"
            case .reddit: return "bubble.left.and.bubble.right.fill"
            }
        }

        var color: Color {
            switch self {
            case .youtube: return .red
            case .reddit: return .orange
            }
        }
    }

    enum RedditTarget: String, CaseIterable, Identifiable {
        case subreddit
        case user

        var id: String { rawValue }

        var title: String {
            switch self {
            case .subreddit: return String(localized: "Subreddit (r/)")
            case .user: return String(localized: "User Profile (u/)")
            }
        }
    }

    @State private var selectedPlatform: Platform = .youtube

    // YouTube State
    @State private var youtubeInput: String = ""
    @State private var isResolvingYouTube: Bool = false
    @State private var youtubeError: String? = nil
    @State private var resolvedResult: SocialFeedResolver.YouTubeChannelResult? = nil

    // Reddit State
    @State private var redditTarget: RedditTarget = .subreddit
    @State private var redditSubreddit: String = ""
    @State private var redditSort: RedditSort = .hot
    @State private var redditTimeFilter: RedditTimeFilter = .week
    @State private var redditUsername: String = ""
    @State private var redditUserType: RedditUserFeedType = .all
    @State private var isAddingReddit: Bool = false
    @State private var redditError: String? = nil

    private let youtubeExamples = ["@mkbhd", "@veritasium", "@apple", "@TED"]
    private let redditSubredditExamples = ["apple", "swift", "technology", "programming"]

    var body: some View {
        VStack(spacing: 0) {
            // Platform Segmented Switcher
            Picker("Platform", selection: $selectedPlatform) {
                ForEach(Platform.allCases) { platform in
                    Label(platform.title, systemImage: platform.icon).tag(platform)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    switch selectedPlatform {
                    case .youtube:
                        youtubeSection
                    case .reddit:
                        redditSection
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - YouTube Section

    private var youtubeSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "YouTube RSS Feed"))
                        .font(.headline)
                    Text(String(localized: "Subscribe to any channel, handle (@name), playlist, or custom URL."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Input Field
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Channel Handle or URL"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)

                    TextField(String(localized: "e.g. @mkbhd, veritasium, or youtube.com/@apple"), text: $youtubeInput)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            addYouTubeFeed()
                        }

                    if !youtubeInput.isEmpty {
                        Button {
                            youtubeInput = ""
                            resolvedResult = nil
                            youtubeError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }

            // Quick Example Chips
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Popular Channels:"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 8) {
                    ForEach(youtubeExamples, id: \.self) { handle in
                        Button {
                            youtubeInput = handle
                            youtubeError = nil
                        } label: {
                            Text(handle)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Error display
            if let error = youtubeError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            // Resolved Result Card
            if let result = resolvedResult {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(result.title ?? String(localized: "YouTube Channel Found"))
                            .font(.subheadline.weight(.semibold))
                    }

                    Text(result.rssURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Action Button
            HStack {
                Spacer()

                Button {
                    addYouTubeFeed()
                } label: {
                    HStack(spacing: 6) {
                        if isResolvingYouTube {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "plus")
                        }
                        Text(String(localized: "Add YouTube Feed"))
                    }
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(youtubeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolvingYouTube)
            }
        }
    }

    // MARK: - Reddit Section

    private var redditSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Reddit RSS Feed"))
                        .font(.headline)
                    Text(String(localized: "Subscribe to any subreddit community or user activity with custom sorting."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Target Switcher (Subreddit vs User)
            Picker("Target", selection: $redditTarget) {
                ForEach(RedditTarget.allCases) { target in
                    Text(target.title).tag(target)
                }
            }
            .pickerStyle(.segmented)

            if redditTarget == .subreddit {
                subredditFields
            } else {
                userFields
            }

            // Live Preview of Generated URL
            let liveURL = currentRedditURL
            if !liveURL.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Generated RSS URL:"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)

                    Text(liveURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Error display
            if let error = redditError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            // Action Button
            HStack {
                Spacer()

                Button {
                    addRedditFeed()
                } label: {
                    HStack(spacing: 6) {
                        if isAddingReddit {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "plus")
                        }
                        Text(redditTarget == .subreddit ? String(localized: "Add Subreddit Feed") : String(localized: "Add User Feed"))
                    }
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(currentRedditIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingReddit)
            }
        }
    }

    // MARK: - Subreddit Fields

    private var subredditFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Input
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Subreddit Name"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("r/")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)

                    TextField("apple, swift, technology...", text: $redditSubreddit)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            addRedditFeed()
                        }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }

            // Quick Example Chips
            HStack(spacing: 8) {
                ForEach(redditSubredditExamples, id: \.self) { sub in
                    Button {
                        redditSubreddit = sub
                    } label: {
                        Text("r/\(sub)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Sort Selector
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Sort By"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)

                    Picker("Sort", selection: $redditSort) {
                        ForEach(RedditSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if redditSort == .top {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Time Frame"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)

                        Picker("Time Filter", selection: $redditTimeFilter) {
                            ForEach(RedditTimeFilter.allCases) { tf in
                                Text(tf.title).tag(tf)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
        }
    }

    // MARK: - User Fields

    private var userFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Input
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Reddit Username"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("u/")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)

                    TextField("username", text: $redditUsername)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            addRedditFeed()
                        }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }

            // Activity Type
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Feed Content"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)

                Picker("Type", selection: $redditUserType) {
                    ForEach(RedditUserFeedType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Helpers & Actions

    private var currentRedditIdentifier: String {
        redditTarget == .subreddit ? redditSubreddit : redditUsername
    }

    private var currentRedditURL: String {
        if redditTarget == .subreddit {
            guard !redditSubreddit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            return SocialFeedResolver.shared.buildRedditSubredditURL(
                subreddit: redditSubreddit,
                sort: redditSort,
                timeFilter: redditSort == .top ? redditTimeFilter : nil
            )
        } else {
            guard !redditUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            return SocialFeedResolver.shared.buildRedditUserURL(
                username: redditUsername,
                type: redditUserType
            )
        }
    }

    private func addYouTubeFeed() {
        let input = youtubeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        isResolvingYouTube = true
        youtubeError = nil

        Task {
            do {
                let result = try await SocialFeedResolver.shared.resolveYouTube(input: input)
                resolvedResult = result
                await store.addFeed(url: result.rssURL)
                isResolvingYouTube = false

                if store.errorMessage == nil {
                    dismiss()
                } else {
                    youtubeError = store.errorMessage
                }
            } catch {
                isResolvingYouTube = false
                youtubeError = error.localizedDescription
            }
        }
    }

    private func addRedditFeed() {
        let url = currentRedditURL
        guard !url.isEmpty else { return }

        isAddingReddit = true
        redditError = nil

        Task {
            await store.addFeed(url: url)
            isAddingReddit = false

            if store.errorMessage == nil {
                dismiss()
            } else {
                redditError = store.errorMessage
            }
        }
    }
}
