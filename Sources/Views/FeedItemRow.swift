import SwiftUI

struct FeedItemRow: View {

    @Environment(\.appTheme) private var theme
    @AppStorage(AppSettingsKeys.isCompactListMode) private var isCompactListMode = false
    let item: FeedItem
    var isSelected: Bool = false
    var feedTitle: String? = nil
    var feedURL: String? = nil
    var feedImageURL: String? = nil

    private static let relativeDateTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var formattedDate: String {
        guard let date = item.pubDate else { return "" }
        return Self.relativeDateTimeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private var mediaThumbnailURL: URL? {
        if let yt = item.youtubeThumbnailURL { return yt }
        if item.isPodcast, let img = feedImageURL, let url = URL(string: img) { return url }
        return nil
    }

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Main text column
            HStack(alignment: .top, spacing: 9) {
                // Unread indicator dot
                ZStack {
                    if !item.isRead {
                        Circle()
                            .fill(theme.unreadDotColor)
                            .frame(width: 7, height: 7)
                            .transition(.scale(scale: 1.3).combined(with: .opacity))
                    }
                }
                .frame(width: 8, height: 8)
                .padding(.top, isCompactListMode ? 4 : 5)
                .animation(AppAnimation.bouncy, value: item.isRead)

                VStack(alignment: .leading, spacing: isCompactListMode ? 2 : 4) {
                    // Title and Bookmark
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 13, weight: item.isRead ? .regular : .semibold))
                            .lineLimit(isCompactListMode ? 1 : 2)
                            .foregroundStyle(item.isRead ? .secondary : .primary)

                        if item.isBookmarked {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.bookmarkColor)
                                .transition(.scale(scale: 1.2).combined(with: .opacity))
                                .animation(AppAnimation.bouncy, value: item.isBookmarked)
                        }
                    }

                    // Content snippet
                    if !isCompactListMode && !item.snippet.isEmpty {
                        Text(item.snippet)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Metadata: one quiet line, "source · time · media". No author icon, no capsules.
                    HStack(spacing: 5) {
                        if let feedTitle, !feedTitle.isEmpty {
                            FaviconView(hostOrURL: feedURL ?? URL(string: item.link)?.host ?? item.link, size: 12)
                            Text(feedTitle)
                                .fontWeight(.medium)
                        } else if let author = item.author, !author.isEmpty {
                            Text(author)
                        }

                        if !formattedDate.isEmpty {
                            if (feedTitle?.isEmpty == false) || (item.author?.isEmpty == false) {
                                Text("·")
                            }
                            Text(formattedDate)
                        }

                        if item.isPodcast {
                            let player = AudioPlayerService.shared
                            let isPlayingThis = player.currentEpisode?.id == item.id && player.isPlaying
                            let isDownloaded = PodcastDownloadService.shared.isDownloaded(item.id)
                            Text("·")
                            if isPlayingThis {
                                EqualizerWaveformView(isPlaying: true, barWidth: 2, maxHeight: 9)
                            } else {
                                Image(systemName: "headphones")
                            }
                            if let duration = item.formattedDuration {
                                Text(duration)
                            }
                            if isDownloaded {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(theme.successColor)
                            }
                        }

                        if item.isYouTube {
                            Text("·")
                            Image(systemName: "play.rectangle.fill")
                                .foregroundStyle(theme.youtubeColor)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.top, 1)
                }
            }

            // Media thumbnail
            if let mediaURL = mediaThumbnailURL {
                let thumbSize: CGFloat = isCompactListMode ? 36 : 46
                DownsampledImageView(
                    url: mediaURL,
                    targetSize: CGSize(width: thumbSize, height: thumbSize),
                    contentMode: .fill,
                    cornerRadius: AppTheme.Metrics.thumbnailCornerRadius
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Metrics.thumbnailCornerRadius, style: .continuous)
                        .stroke(theme.hairlineBorder, lineWidth: 0.5)
                )
                .overlay(alignment: .center) {
                    if item.isPodcast || item.isYouTube {
                        Circle()
                            .fill(Color.black.opacity(0.65))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(item.isYouTube ? theme.youtubeColor : .white)
                                    .offset(x: 1)
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isCompactListMode ? 5 : 7)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
                    .fill(theme.cardSelected)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
                            .stroke(theme.cardSelectedBorder, lineWidth: 1.0)
                    )
            } else if isHovered {
                RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
                    .fill(theme.cardHover)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
                            .stroke(theme.hairlineBorder, lineWidth: 0.6)
                    )
            }
        }
        .scaleEffect(isHovered && !isSelected ? 1.004 : 1.0)
        .animation(AppAnimation.hover, value: isHovered)
        .animation(AppAnimation.slidingPill, value: isSelected)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
