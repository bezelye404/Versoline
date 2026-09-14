import SwiftUI
import WebKit

// MARK: - Shared Video Canvas View (Zero-Reload Reparenting via VideoPlayerService)

struct SharedVideoCanvasView: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        VideoPlayerService.shared.attach(to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        VideoPlayerService.shared.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        VideoPlayerService.shared.detachIfAttached(to: nsView)
    }
}

// MARK: - Main YouTube Custom Player View

struct YouTubePlayerView: View {

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
            .frame(maxWidth: .infinity)
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)

            // Video Control & Metadata Row
            HStack(spacing: 12) {
                Label("YouTube", systemImage: "play.rectangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isCurrentVideoActive {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
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
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isThumbnailHovered)

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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
                            .foregroundStyle(.red)

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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    videoPlayer.play(item: resolvedItem)
                }
            }
        }
    }
}

// MARK: - Native Video Player Canvas (SwiftUI Hardware Video & Native Glass HUD)

struct NativeVideoPlayerCanvas: View {

    let videoID: String
    let title: String
    var isModalFullscreen: Bool = false
    let onToggleFullscreen: () -> Void

    @Bindable private var videoPlayer = VideoPlayerService.shared

    @State private var isControlsVisible: Bool = true
    @State private var hideWorkItem: DispatchWorkItem?
    @State private var isVolumeExpanded: Bool = false
    @State private var isVolumeHovered: Bool = false
    @State private var showFeedbackPulse: Bool = false
    @State private var feedbackIcon: String = "play.fill"

    var body: some View {
        ZStack {
            // 1. Shared Headless Hardware Video Canvas
            SharedVideoCanvasView()
                .background(Color.black)

            // 2. Instant Tap Canvas (Single tap: play/pause instantly with 0 delay)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    AppHaptics.tap()
                    videoPlayer.togglePlayPause()
                    triggerPulse(icon: videoPlayer.isPlaying ? "play.fill" : "pause.fill")
                    resetControlsTimer()
                }

            // 3. Top Cinema Header (When in Modal Fullscreen)
            if isModalFullscreen {
                VStack {
                    if isControlsVisible || !videoPlayer.isPlaying {
                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.red)

                                Text(title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                            .shadow(color: Color.black.opacity(0.4), radius: 8, y: 3)

                            Spacer()

                            Button {
                                onToggleFullscreen()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.escape, modifiers: [])
                            .help(String(localized: "Exit Fullscreen (Esc)"))
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .transition(.opacity.combined(with: .offset(y: -8)))
                    }

                    Spacer()
                }
            }

            // 4. Bottom Gradient Vignette (Ensures contrast against bright videos)
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 84)
                .allowsHitTesting(false)
                .opacity(isControlsVisible || !videoPlayer.isPlaying ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.3), value: isControlsVisible)
            }

            // 5. Central Feedback Pulse & Buffering Indicator
            if videoPlayer.isBuffering {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 58, height: 58)
                        .shadow(color: .black.opacity(0.35), radius: 10)
                    ProgressView()
                        .controlSize(.regular)
                }
                .transition(.scale.combined(with: .opacity))
            } else if showFeedbackPulse {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 60, height: 60)
                        .shadow(color: .black.opacity(0.35), radius: 12)
                    Image(systemName: feedbackIcon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: feedbackIcon == "play.fill" ? 2 : 0)
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            // 6. Custom Native SwiftUI HUD Overlay (Auto-Hiding)
            VStack {
                Spacer()
                if isControlsVisible || !videoPlayer.isPlaying || videoPlayer.isScrubbing {
                    bottomControlsBar
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
            .padding(10)
        }
        .onContinuousHover { _ in
            resetControlsTimer()
        }
        .onAppear {
            resetControlsTimer()
        }
        .onDisappear {
            hideWorkItem?.cancel()
        }
    }

    // MARK: - Bottom HUD Bar (Glassmorphic & Zero Layout Shift)

    private var bottomControlsBar: some View {
        HStack(spacing: 8) {
            // Play / Pause Toggle
            PlayerHUDButton(icon: videoPlayer.isPlaying ? "pause.fill" : "play.fill", tooltip: videoPlayer.isPlaying ? String(localized: "Pause") : String(localized: "Play")) {
                videoPlayer.togglePlayPause()
                triggerPulse(icon: videoPlayer.isPlaying ? "play.fill" : "pause.fill")
                resetControlsTimer()
            }

            // 10s Backward
            PlayerHUDButton(icon: "gobackward.10", tooltip: String(localized: "Seek Backward 10s")) {
                videoPlayer.seekBy(offset: -10)
                triggerPulse(icon: "gobackward.10")
                resetControlsTimer()
            }

            // 10s Forward
            PlayerHUDButton(icon: "goforward.10", tooltip: String(localized: "Seek Forward 10s")) {
                videoPlayer.seekBy(offset: 10)
                triggerPulse(icon: "goforward.10")
                resetControlsTimer()
            }

            // Current Time (Monospaced)
            Text(formatTime(videoPlayer.isScrubbing ? videoPlayer.scrubTime : videoPlayer.currentTime))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .frame(minWidth: 38, alignment: .trailing)

            // Interactive Live Scrubber (Smooth GeometryReader)
            NativePlayerScrubber(videoPlayer: videoPlayer)

            // Duration (Monospaced)
            Text(formatTime(videoPlayer.duration))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(minWidth: 38, alignment: .leading)

            // Playback Speed Menu
            Menu {
                ForEach(VideoPlayerService.availableRates, id: \.self) { rate in
                    Button {
                        videoPlayer.setPlaybackRate(rate)
                        resetControlsTimer()
                    } label: {
                        HStack {
                            Text(rate == 1.0 ? "1.0x (Normal)" : String(format: "%.2gx", rate))
                            if videoPlayer.playbackRate == rate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(videoPlayer.playbackRate == 1.0 ? "1x" : String(format: "%.2gx", videoPlayer.playbackRate))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "Playback Speed"))

            // Zero-Layout-Shift Volume Control
            volumeControlWithFloatingCapsule

            // Fullscreen Button
            PlayerHUDButton(
                icon: isModalFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                tooltip: isModalFullscreen ? String(localized: "Exit Fullscreen") : String(localized: "Fullscreen")
            ) {
                onToggleFullscreen()
                resetControlsTimer()
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Floating Volume Capsule (Zero Layout Shift Guaranteed)

    private var volumeControlWithFloatingCapsule: some View {
        HStack(spacing: 0) {
            Button {
                videoPlayer.toggleMute()
                resetControlsTimer()
            } label: {
                Image(systemName: videoPlayer.isMuted || videoPlayer.volume == 0 ? "speaker.slash.fill" : (videoPlayer.volume > 0.5 ? "speaker.wave.3.fill" : "speaker.wave.1.fill"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(isVolumeHovered ? 0.16 : 0.0))
                    )
            }
            .buttonStyle(.plain)
            .help(videoPlayer.isMuted ? String(localized: "Unmute") : String(localized: "Mute"))
            .onHover { hovering in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isVolumeHovered = hovering
                    if hovering {
                        isVolumeExpanded = true
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if isVolumeExpanded {
                VStack(spacing: 8) {
                    Slider(
                        value: $videoPlayer.volume,
                        in: 0.0...1.0
                    )
                    .controlSize(.mini)
                    .tint(.white)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 76, height: 20)
                    .padding(.vertical, 32)

                    Text("\(Int(videoPlayer.volume * 100))%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.4), radius: 12, y: -4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .offset(y: -140)
                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                .onHover { inPopup in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isVolumeExpanded = inPopup
                    }
                }
            }
        }
    }

    // MARK: - Auto-Hide HUD Timer

    private func resetControlsTimer() {
        withAnimation(.easeOut(duration: 0.18)) {
            isControlsVisible = true
        }
        hideWorkItem?.cancel()

        guard videoPlayer.isPlaying && !videoPlayer.isScrubbing else { return }

        let work = DispatchWorkItem { [self] in
            withAnimation(.easeInOut(duration: 0.35)) {
                isControlsVisible = false
                isVolumeExpanded = false
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func triggerPulse(icon: String) {
        feedbackIcon = icon
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            showFeedbackPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.2)) {
                showFeedbackPulse = false
            }
        }
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
}

// MARK: - Fullscreen Video Modal View

struct FullscreenVideoModal: View {
    let videoID: String
    let title: String
    let link: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            NativeVideoPlayerCanvas(
                videoID: videoID,
                title: title,
                isModalFullscreen: true,
                onToggleFullscreen: onClose
            )
            .aspectRatio(16/9, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Player HUD Button (Apple HIG Hover Style)

private struct PlayerHUDButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.9))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? 0.16 : 0.0))
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Native Player Scrubber

struct NativePlayerScrubber: View {
    @Bindable var videoPlayer: VideoPlayerService
    @State private var isHovered: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let duration = max(videoPlayer.duration, 0.001)
            let progress = videoPlayer.isScrubbing ? (videoPlayer.scrubTime / duration) : (videoPlayer.currentTime / duration)
            let clampedProgress = max(0, min(progress, 1.0))
            let bufferedFraction = max(0, min(videoPlayer.bufferedTime / duration, 1.0))

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: isHovered || videoPlayer.isScrubbing ? 6 : 3.5)

                // Buffered Track
                Capsule()
                    .fill(Color.white.opacity(0.38))
                    .frame(width: totalWidth * CGFloat(bufferedFraction), height: isHovered || videoPlayer.isScrubbing ? 6 : 3.5)

                // Progress Track
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.orange.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: totalWidth * CGFloat(clampedProgress), height: isHovered || videoPlayer.isScrubbing ? 6 : 3.5)

                // Thumb Handle
                Circle()
                    .fill(Color.white)
                    .frame(width: isHovered || videoPlayer.isScrubbing ? 13 : 8, height: isHovered || videoPlayer.isScrubbing ? 13 : 8)
                    .shadow(color: Color.black.opacity(0.5), radius: 3, x: 0, y: 1)
                    .offset(x: max(0, min(totalWidth * CGFloat(clampedProgress) - (isHovered || videoPlayer.isScrubbing ? 6.5 : 4), totalWidth - 13)))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        videoPlayer.isScrubbing = true
                        let ratio = max(0, min(value.location.x / totalWidth, 1.0))
                        videoPlayer.scrubTime = Double(ratio) * videoPlayer.duration
                    }
                    .onEnded { value in
                        let ratio = max(0, min(value.location.x / totalWidth, 1.0))
                        let targetTime = Double(ratio) * videoPlayer.duration
                        videoPlayer.seek(to: targetTime)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            videoPlayer.isScrubbing = false
                        }
                    }
            )
            .onHover { hovering in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    isHovered = hovering
                }
            }
        }
        .frame(height: 16)
    }
}
