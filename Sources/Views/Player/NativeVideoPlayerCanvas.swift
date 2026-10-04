import SwiftUI
import WebKit

struct NativeVideoPlayerCanvas: View {

    let videoID: String
    let title: String
    var isModalFullscreen: Bool = false
    let onToggleFullscreen: () -> Void

    @Environment(FeedStore.self) private var store
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
            SharedVideoCanvasView(isModalFullscreen: isModalFullscreen)
                .id("shared-video-canvas-\(isModalFullscreen ? "modal" : "inline")-\(store.fullscreenVideo == nil)")
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
                .animation(AppAnimation.safe(.easeInOut(duration: 0.3)), value: isControlsVisible)
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
                withAnimation(AppAnimation.safe(.spring(response: 0.2, dampingFraction: 0.8))) {
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
                    withAnimation(AppAnimation.safe(.spring(response: 0.25, dampingFraction: 0.8))) {
                        isVolumeExpanded = inPopup
                    }
                }
            }
        }
    }

    // MARK: - Auto-Hide HUD Timer

    private func resetControlsTimer() {
        withAnimation(AppAnimation.safe(.easeOut(duration: 0.18))) {
            isControlsVisible = true
        }
        hideWorkItem?.cancel()

        guard videoPlayer.isPlaying && !videoPlayer.isScrubbing else { return }

        let work = DispatchWorkItem { [self] in
            withAnimation(AppAnimation.safe(.easeInOut(duration: 0.35))) {
                isControlsVisible = false
                isVolumeExpanded = false
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func triggerPulse(icon: String) {
        feedbackIcon = icon
        withAnimation(AppAnimation.safe(.spring(response: 0.2, dampingFraction: 0.7))) {
            showFeedbackPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(AppAnimation.safe(.easeOut(duration: 0.2))) {
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

struct PlayerHUDButton: View {
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
            withAnimation(AppAnimation.safe(.spring(response: 0.2, dampingFraction: 0.8))) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Native Player Scrubber
