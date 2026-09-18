import SwiftUI
import AppKit

// MARK: - Spotify-Style Universal Mini Player (Podcasts & Videos)

struct MiniPlayerView: View {

    @Bindable private var audioPlayer = AudioPlayerService.shared
    @Bindable private var videoPlayer = VideoPlayerService.shared
    @Environment(FeedStore.self) private var store
    @Environment(\.appTheme) private var theme

    var onNavigateToArticle: ((FeedItem) -> Void)? = nil

    @State private var showQueuePopover = false

    private enum ActiveMedia {
        case podcast(FeedItem)
        case video(FeedItem)

        var item: FeedItem {
            switch self {
            case .podcast(let item), .video(let item):
                return item
            }
        }
    }

    private var activeMedia: ActiveMedia? {
        if videoPlayer.currentVideo != nil && (videoPlayer.isPlaying || !audioPlayer.isPlaying) {
            if let video = videoPlayer.currentVideo {
                return .video(video)
            }
        }
        if let episode = audioPlayer.currentEpisode {
            return .podcast(episode)
        }
        if let video = videoPlayer.currentVideo {
            return .video(video)
        }
        return nil
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private func formatRemainingTime(current: Double, total: Double) -> String {
        guard total > 0, total >= current else { return "--:--" }
        let remaining = total - current
        return "-" + formatTime(remaining)
    }

    private func shareTimestamp(for item: FeedItem) {
        let text = "\(item.title)\n\(audioPlayer.shareURLString(for: item))"
        let picker = NSSharingServicePicker(items: [text])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .maxY)
        }
    }

    var body: some View {
        if let media = activeMedia {
            VStack(spacing: 0) {
                Divider()

                HStack(spacing: 16) {
                    // MARK: - Left: Artwork, Info & Direct "Go to Article" Action
                    leftMediaInfoSection(media: media)
                        .frame(minWidth: 160, idealWidth: 220, maxWidth: 280, alignment: .leading)

                    Spacer(minLength: 8)

                    // MARK: - Center: Transport Controls & Interactive Scrubber
                    centerControlsSection(media: media)
                        .frame(maxWidth: 440)

                    Spacer(minLength: 8)

                    // MARK: - Right: Tools (Speed, Sleep Timer, Queue, Volume, Fullscreen, Close)
                    rightToolsSection(media: media)
                        .frame(minWidth: 200, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Left Media Info Section

    @ViewBuilder
    private func leftMediaInfoSection(media: ActiveMedia) -> some View {
        HStack(spacing: 10) {
            // Artwork / Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 38, height: 38)

                switch media {
                case .podcast(let episode):
                    if let feed = store.feed(for: episode.feedId) {
                        FaviconView(hostOrURL: feed.url, size: 22)
                    } else {
                        Image(systemName: "headphones")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.podcastColor)
                    }
                case .video(let video):
                    if let thumbURL = video.youtubeThumbnailURL {
                        DownsampledImageView(
                            url: thumbURL,
                            targetSize: CGSize(width: 38, height: 38),
                            contentMode: .fill,
                            cornerRadius: 6
                        ) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(theme.youtubeColor)
                        }
                    } else {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(theme.youtubeColor)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(theme.hairlineBorder, lineWidth: 0.5)
            )

            // Titles & Equalizer
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(media.item.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    switch media {
                    case .podcast:
                        EqualizerWaveformView(isPlaying: audioPlayer.isPlaying, barWidth: 1.5, maxHeight: 9)
                    case .video:
                        EqualizerWaveformView(isPlaying: videoPlayer.isPlaying, barWidth: 1.5, maxHeight: 9)
                    }
                }

                HStack(spacing: 6) {
                    Text(subtitleFor(media: media))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    // Single-click "Go to Article / Feed" Button
                    Button {
                        AppHaptics.tap()
                        onNavigateToArticle?(media.item)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(theme.accentColor)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Go to Article / Feed"))
                }
            }
        }
    }

    private func subtitleFor(media: ActiveMedia) -> String {
        switch media {
        case .podcast(let episode):
            return audioPlayer.currentFeedTitle ?? episode.author ?? String(localized: "Podcast")
        case .video(let video):
            return videoPlayer.currentFeedTitle ?? video.author ?? "YouTube"
        }
    }

    // MARK: - Center Controls Section

    @ViewBuilder
    private func centerControlsSection(media: ActiveMedia) -> some View {
        VStack(spacing: 4) {
            // Transport Buttons
            HStack(spacing: 14) {
                // Skip Backward
                Button {
                    AppHaptics.tap()
                    switch media {
                    case .podcast:
                        audioPlayer.skipBackward(seconds: 15)
                    case .video:
                        videoPlayer.seekBy(offset: -10)
                    }
                } label: {
                    Image(systemName: mediaIsPodcast(media) ? "gobackward.15" : "gobackward.10")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(mediaIsPodcast(media) ? String(localized: "Skip backward 15 seconds") : String(localized: "Skip backward 10 seconds"))

                // Play / Pause Toggle Button
                Button {
                    AppHaptics.tap()
                    withAnimation(AppAnimation.bouncy) {
                        switch media {
                        case .podcast:
                            audioPlayer.togglePlayPause()
                        case .video:
                            videoPlayer.togglePlayPause()
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(theme.accentColor)
                            .frame(width: 30, height: 30)

                        if isBuffering(for: media) {
                            ProgressView()
                                .controlSize(.small)
                                .colorInvert()
                        } else {
                            Image(systemName: isPlaying(for: media) ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: isPlaying(for: media) ? 0 : 1)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(isPlaying(for: media) ? String(localized: "Pause") : String(localized: "Play"))

                // Skip Forward
                Button {
                    AppHaptics.tap()
                    switch media {
                    case .podcast:
                        audioPlayer.skipForward(seconds: 15)
                    case .video:
                        videoPlayer.seekBy(offset: 10)
                    }
                } label: {
                    Image(systemName: mediaIsPodcast(media) ? "goforward.15" : "goforward.10")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(mediaIsPodcast(media) ? String(localized: "Skip forward 15 seconds") : String(localized: "Skip forward 10 seconds"))
            }

            // Scrubber Slider & Timers
            HStack(spacing: 7) {
                Text(formatTime(currentTime(for: media)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { currentTime(for: media) },
                        set: { seek(media: media, to: $0) }
                    ),
                    in: 0...max(duration(for: media), 1.0)
                )
                .controlSize(.mini)
                .tint(theme.accentColor)

                Text(duration(for: media) > 0 ? formatRemainingTime(current: currentTime(for: media), total: duration(for: media)) : "--:--")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }
        }
    }

    // MARK: - Right Tools Section

    @ViewBuilder
    private func rightToolsSection(media: ActiveMedia) -> some View {
        HStack(spacing: 8) {
            // Playback Speed Menu
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button {
                        setPlaybackRate(media: media, rate: rate)
                    } label: {
                        HStack {
                            Text(String(format: "%.2gx", rate))
                            if currentPlaybackRate(media: media) == rate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(String(format: "%.2gx", currentPlaybackRate(media: media)))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "Playback Speed"))

            switch media {
            case .podcast(let episode):
                // Sleep Timer Menu
                Menu {
                    Button(String(localized: "Turn Off Timer")) {
                        audioPlayer.cancelSleepTimer()
                    }
                    Divider()
                    Button("15 " + String(localized: "minutes")) {
                        audioPlayer.startSleepTimer(minutes: 15)
                    }
                    Button("30 " + String(localized: "minutes")) {
                        audioPlayer.startSleepTimer(minutes: 30)
                    }
                    Button("45 " + String(localized: "minutes")) {
                        audioPlayer.startSleepTimer(minutes: 45)
                    }
                    Button("60 " + String(localized: "minutes")) {
                        audioPlayer.startSleepTimer(minutes: 60)
                    }
                    Button(String(localized: "End of Episode")) {
                        audioPlayer.startSleepTimerUntilEndOfEpisode()
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: audioPlayer.sleepTimerRemainingSeconds != nil ? "moon.zzz.fill" : "moon.zzz")
                            .font(.system(size: 11))
                        if let remaining = audioPlayer.sleepTimerRemainingSeconds {
                            Text("\(max(1, remaining / 60))m")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        audioPlayer.sleepTimerRemainingSeconds != nil ? theme.accentColor.opacity(0.12) : Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                    .foregroundStyle(audioPlayer.sleepTimerRemainingSeconds != nil ? theme.accentColor : Color.secondary)
                }
                .menuStyle(.borderlessButton)
                .help(String(localized: "Sleep Timer"))

                // Up Next Queue Popover
                Button {
                    AppHaptics.tap()
                    showQueuePopover.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11))
                            .foregroundStyle(showQueuePopover || !audioPlayer.queue.isEmpty ? theme.accentColor : Color.secondary)

                        if !audioPlayer.queue.isEmpty {
                            Circle()
                                .fill(theme.accentColor)
                                .frame(width: 4, height: 4)
                                .offset(x: 2, y: -2)
                        }
                    }
                    .padding(4)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showQueuePopover, arrowEdge: .top) {
                    QueuePopoverView()
                        .environment(store)
                }
                .help(String(localized: "Up Next Queue"))

                // Share Timestamp Button
                Button {
                    AppHaptics.tap()
                    shareTimestamp(for: episode)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Share Episode with Timestamp"))

            case .video(let video):
                // Fullscreen Button
                Button {
                    AppHaptics.tap()
                    if let vID = video.youtubeVideoID {
                        withAnimation(AppAnimation.pageReveal) {
                            store.fullscreenVideo = FullscreenVideoContext(videoID: vID, title: video.title, link: video.link)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Fullscreen Video"))
            }

            // Volume Control
            HStack(spacing: 4) {
                Image(systemName: currentVolume(media: media) == 0 ? "speaker.slash.fill" : (currentVolume(media: media) < 0.5 ? "speaker.1.fill" : "speaker.3.fill"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        AppHaptics.tap()
                        toggleMute(media: media)
                    }

                Slider(
                    value: volumeBinding(media: media),
                    in: 0.0...1.0
                )
                .controlSize(.mini)
                .frame(width: 44)
            }

            // Close Player (X)
            Button {
                AppHaptics.tap()
                withAnimation(AppAnimation.pageReveal) {
                    closePlayer(media: media)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Close Player"))
        }
    }

    // MARK: - Media State Helpers

    private func mediaIsPodcast(_ media: ActiveMedia) -> Bool {
        if case .podcast = media { return true }
        return false
    }

    private func isPlaying(for media: ActiveMedia) -> Bool {
        switch media {
        case .podcast: return audioPlayer.isPlaying
        case .video: return videoPlayer.isPlaying
        }
    }

    private func isBuffering(for media: ActiveMedia) -> Bool {
        switch media {
        case .podcast: return audioPlayer.isBuffering
        case .video: return videoPlayer.isBuffering
        }
    }

    private func currentTime(for media: ActiveMedia) -> Double {
        switch media {
        case .podcast: return audioPlayer.currentTime
        case .video: return videoPlayer.currentTime
        }
    }

    private func duration(for media: ActiveMedia) -> Double {
        switch media {
        case .podcast: return audioPlayer.duration
        case .video: return videoPlayer.duration
        }
    }

    private func seek(media: ActiveMedia, to seconds: Double) {
        switch media {
        case .podcast: audioPlayer.seek(to: seconds)
        case .video: videoPlayer.seek(to: seconds)
        }
    }

    private func currentPlaybackRate(media: ActiveMedia) -> Double {
        switch media {
        case .podcast: return Double(audioPlayer.playbackRate)
        case .video: return videoPlayer.playbackRate
        }
    }

    private func setPlaybackRate(media: ActiveMedia, rate: Double) {
        switch media {
        case .podcast: audioPlayer.setPlaybackRate(Float(rate))
        case .video: videoPlayer.setPlaybackRate(rate)
        }
    }

    private func currentVolume(media: ActiveMedia) -> Float {
        switch media {
        case .podcast: return audioPlayer.volume
        case .video: return Float(videoPlayer.volume)
        }
    }

    private func toggleMute(media: ActiveMedia) {
        switch media {
        case .podcast:
            if audioPlayer.volume > 0 { audioPlayer.volume = 0 } else { audioPlayer.volume = 1.0 }
        case .video:
            videoPlayer.toggleMute()
        }
    }

    private func volumeBinding(media: ActiveMedia) -> Binding<Double> {
        switch media {
        case .podcast:
            return Binding(
                get: { Double(audioPlayer.volume) },
                set: { audioPlayer.volume = Float($0) }
            )
        case .video:
            return Binding(
                get: { videoPlayer.volume },
                set: { videoPlayer.volume = $0 }
            )
        }
    }

    private func closePlayer(media: ActiveMedia) {
        switch media {
        case .podcast: audioPlayer.close()
        case .video: videoPlayer.close()
        }
    }
}
