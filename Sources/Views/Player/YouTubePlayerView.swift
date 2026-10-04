import SwiftUI
import WebKit

// MARK: - Shared Video Canvas View (Zero-Reload Reparenting via VideoPlayerService)

struct YouTubePlayerView: View {

    @Environment(\.appTheme) private var theme
    @Environment(FeedStore.self) private var store
    @Bindable private var videoPlayer = VideoPlayerService.shared

    let videoID: String
    let title: String
    let link: String
    var item: FeedItem?

    @State private var isThumbnailHovered: Bool = false

    private var isCurrentVideoActive: Bool {
        videoPlayer.videoID == videoID && videoPlayer.currentVideo != nil
    }

    private var resolvedItem: FeedItem {
        if let it = item { return it }
        // Fallback synthetic item if not passed directly
        return FeedItem(
            feedId: UUID(),
            title: title,
            link: link,
            itemDescription: ""
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if isCurrentVideoActive {
                    NativeVideoPlayerCanvas(
                        videoID: videoID,
                        title: title,
                        isModalFullscreen: false,
                        onToggleFullscreen: {
                            withAnimation(AppAnimation.pageReveal) {
                                store.fullscreenVideo = FullscreenVideoContext(videoID: videoID, title: title, link: link)
                                videoPlayer.isFullscreen = true
                            }
                        }
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    thumbnailCover
                        .aspectRatio(16/9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .transition(.opacity)
                }
            }
            // The page decodes and keeps frames for the player's size: 960 px wide costs about 30 MB more than
            // 640 px. Inline playback is capped; fullscreen is the user's explicit choice for a bigger picture.
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)

            // Video Control & Metadata Row
            HStack(spacing: 12) {
                Label("YouTube", systemImage: "play.rectangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.youtubeColor)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isCurrentVideoActive {
                    Button {
                        withAnimation(AppAnimation.safe(.spring(response: 0.3, dampingFraction: 0.82))) {
                            videoPlayer.close()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9))
                            Text(String(localized: "Stop"))
                                .font(.caption2.weight(.medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Stop Player"))
                }

                Link(destination: URL(string: link) ?? URL(string: "https://youtube.com/watch?v=\(videoID)")!) {
                    HStack(spacing: 4) {
                        Text(String(localized: "Open in Browser"))
                            .font(.caption2)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Premium Cinema Thumbnail Cover

    private var thumbnailCover: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                // YouTube HQ Thumbnail
                DownsampledImageView(
                    url: URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg"),
                    targetSize: geo.size,
                    contentMode: .fill
                ) {
                    ZStack {
                        Color.black
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .scaleEffect(isThumbnailHovered ? 1.03 : 1.0)
                .animation(AppAnimation.safe(.spring(response: 0.45, dampingFraction: 0.8)), value: isThumbnailHovered)

                // Dark Cinema Gradient
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.35),
                        Color.black.opacity(0.15),
                        Color.black.opacity(0.70)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Large Glass Play Button
                Button {
                    AppHaptics.tap()
                    withAnimation(AppAnimation.safe(.spring(response: 0.35, dampingFraction: 0.8))) {
                        videoPlayer.play(item: resolvedItem)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 64, height: 64)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(isThumbnailHovered ? 0.35 : 0.15), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 12, y: 4)

                        Image(systemName: "play.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: 2)
                    }
                    .scaleEffect(isThumbnailHovered ? 1.08 : 1.0)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Play Video"))

                // Bottom Title Overlay
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.youtubeColor)

                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(14)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isThumbnailHovered = hovering
            }
            .onTapGesture {
                AppHaptics.tap()
                withAnimation(AppAnimation.safe(.spring(response: 0.35, dampingFraction: 0.8))) {
                    videoPlayer.play(item: resolvedItem)
                }
            }
        }
    }
}

// MARK: - Native Video Player Canvas (SwiftUI Hardware Video & Native Glass HUD)
