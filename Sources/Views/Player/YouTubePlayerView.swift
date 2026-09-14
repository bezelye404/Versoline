import SwiftUI
import WebKit

// MARK: - Weak Script Message Handler (Retain Cycle & Leak Prevention)

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - Player Bridge Controller (Bidirectional Swift <-> WebKit)

@MainActor
final class PlayerBridgeController: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var bufferedTime: Double = 0.0
    @Published var playbackRate: Double = 1.0
    @Published var volume: Double = 1.0
    @Published var isMuted: Bool = false
    @Published var isReady: Bool = false
    @Published var isScrubbing: Bool = false
    @Published var scrubTime: Double = 0.0
    @Published var isFullscreen: Bool = false

    weak var webView: WKWebView?

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        Task { @MainActor in
            self.handleBridgeMessage(type: type, payload: json)
        }
    }

    private func handleBridgeMessage(type: String, payload: [String: Any]) {
        switch type {
        case "ready":
            isReady = true
            if let dur = payload["duration"] as? Double, dur > 0 {
                duration = dur
            }
        case "state":
            guard let state = payload["state"] as? String else { return }
            switch state {
            case "playing":
                isPlaying = true
                isBuffering = false
            case "paused":
                isPlaying = false
                isBuffering = false
            case "buffering":
                isBuffering = true
            case "ended":
                isPlaying = false
                isBuffering = false
                currentTime = duration
            default:
                break
            }
        case "time":
            if !isScrubbing, let cur = payload["currentTime"] as? Double {
                currentTime = cur
            }
            if let dur = payload["duration"] as? Double, dur > 0 {
                duration = dur
            }
            if let buf = payload["buffered"] as? Double {
                bufferedTime = buf
            }
        case "fullscreen":
            if let isFs = payload["isFullscreen"] as? Bool {
                isFullscreen = isFs
            }
        default:
            break
        }
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        webView?.evaluateJavaScript("if (window.player && player.playVideo) { player.playVideo(); }", completionHandler: nil)
        isPlaying = true
    }

    func pause() {
        webView?.evaluateJavaScript("if (window.player && player.pauseVideo) { player.pauseVideo(); }", completionHandler: nil)
        isPlaying = false
    }

    func seek(to seconds: Double) {
        let maxDuration = duration > 0 ? duration : seconds
        let target = max(0, min(seconds, maxDuration))
        currentTime = target
        webView?.evaluateJavaScript("if (window.player && player.seekTo) { player.seekTo(\(target), true); }", completionHandler: nil)
    }

    func seekBy(offset: Double) {
        let base = isScrubbing ? scrubTime : currentTime
        seek(to: base + offset)
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        webView?.evaluateJavaScript("if (window.player && player.setPlaybackRate) { player.setPlaybackRate(\(rate)); }", completionHandler: nil)
    }

    func setVolume(_ vol: Double) {
        let clamped = max(0, min(vol, 1.0))
        volume = clamped
        isMuted = (clamped == 0)
        webView?.evaluateJavaScript("if (window.player && player.setVolume) { player.setVolume(\(Int(clamped * 100))); }", completionHandler: nil)
    }

    func toggleMute() {
        if isMuted {
            isMuted = false
            let restoreVol = volume > 0.05 ? volume : 0.7
            volume = restoreVol
            webView?.evaluateJavaScript("if (window.player) { if (player.unMute) player.unMute(); if (player.setVolume) player.setVolume(\(Int(restoreVol * 100))); }", completionHandler: nil)
        } else {
            isMuted = true
            webView?.evaluateJavaScript("if (window.player && player.mute) { player.mute(); }", completionHandler: nil)
        }
    }

    func toggleFullscreen() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isFullscreen.toggle()
        }
    }

    func triggerPictureInPicture() {
        // Broadcast PiP toggle directly to the video subframe
        let js = """
        (function() {
            window.postMessage('pip_toggle', '*');
            for (var i = 0; i < window.frames.length; i++) {
                try { window.frames[i].postMessage('pip_toggle', '*'); } catch(e) {}
            }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

// MARK: - Main YouTube Custom Player View

struct YouTubePlayerView: View {

    @Environment(FeedStore.self) private var store

    let videoID: String
    let title: String
    let link: String
    var isTheaterMode: Binding<Bool>? = nil

    @StateObject private var bridge = PlayerBridgeController()
    @State private var isPlayerActive: Bool = false
    @State private var isThumbnailHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if isPlayerActive {
                    NativeVideoPlayerCanvas(
                        videoID: videoID,
                        title: title,
                        bridge: bridge,
                        isModalFullscreen: false,
                        onToggleFullscreen: {
                            bridge.pause()
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

                if isPlayerActive {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            isPlayerActive = false
                            bridge.pause()
                        }
                    } label: {
                        Label(String(localized: "Close Player"), systemImage: "stop.fill")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(String(localized: "Stop video and free memory"))
                }

                if let url = URL(string: link) {
                    Link(destination: url) {
                        Label(String(localized: "Watch on YouTube"), systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onChange(of: store.fullscreenVideo) { _, val in
            if val != nil {
                bridge.pause()
            }
        }
    }

    // MARK: - Click-To-Play Thumbnail Cover (0 MB WebKit RAM)

    @ViewBuilder
    private var thumbnailCover: some View {
        ZStack {
            let thumbURL = URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")

            AsyncImage(url: thumbURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                case .failure:
                    ZStack {
                        Color.black.opacity(0.85)
                        Image(systemName: "video.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                case .empty:
                    ZStack {
                        Color.black.opacity(0.85)
                        ProgressView()
                            .controlSize(.small)
                    }
                @unknown default:
                    Color.black
                }
            }

            // Cinematic Vignette
            LinearGradient(
                colors: [Color.black.opacity(0.15), Color.black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Play Button with Glassmorphism & Spring Hover
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isPlayerActive = true
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 68, height: 68)
                        .shadow(color: Color.black.opacity(0.4), radius: 14, x: 0, y: 6)

                    Circle()
                        .fill(Color.red.opacity(isThumbnailHovered ? 0.95 : 0.85))
                        .frame(width: 54, height: 54)

                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(isThumbnailHovered ? 1.08 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isThumbnailHovered)
            .onHover { hovering in
                isThumbnailHovered = hovering
            }
        }
    }
}

// MARK: - Native Video Player Canvas (Headless WebKit + SwiftUI HUD)

struct NativeVideoPlayerCanvas: View {
    let videoID: String
    let title: String
    @ObservedObject var bridge: PlayerBridgeController
    var isModalFullscreen: Bool = false
    var onToggleFullscreen: (() -> Void)? = nil

    @State private var isControlsVisible: Bool = true
    @State private var hideWorkItem: DispatchWorkItem?
    @State private var isVolumeExpanded: Bool = false
    @State private var isVolumeHovered: Bool = false
    @State private var showFeedbackPulse: Bool = false
    @State private var feedbackIcon: String = "play.fill"

    var body: some View {
        ZStack {
            // 1. Headless Hardware Video Canvas
            CustomHeadlessWebView(videoID: videoID, bridge: bridge)
                .background(Color.black)

            // 2. Invisible Tap Canvas (Single tap: play/pause; Double tap: fullscreen)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if let onToggle = onToggleFullscreen {
                        onToggle()
                    } else {
                        bridge.toggleFullscreen()
                    }
                    resetControlsTimer()
                }
                .onTapGesture(count: 1) {
                    bridge.togglePlay()
                    triggerPulse(icon: bridge.isPlaying ? "play.fill" : "pause.fill")
                    resetControlsTimer()
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
                .opacity(isControlsVisible || !bridge.isPlaying ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.3), value: isControlsVisible)
            }

            // 4. Central Feedback Pulse & Buffering Indicator
            if bridge.isBuffering {
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

            // 5. Custom Native SwiftUI HUD Overlay (Auto-Hiding)
            VStack {
                Spacer()
                if isControlsVisible || !bridge.isPlaying || bridge.isScrubbing {
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
            PlayerHUDButton(icon: bridge.isPlaying ? "pause.fill" : "play.fill", tooltip: bridge.isPlaying ? String(localized: "Pause") : String(localized: "Play")) {
                bridge.togglePlay()
                triggerPulse(icon: bridge.isPlaying ? "play.fill" : "pause.fill")
                resetControlsTimer()
            }

            // 10s Backward
            PlayerHUDButton(icon: "gobackward.10", tooltip: String(localized: "Seek Backward 10s")) {
                bridge.seekBy(offset: -10)
                triggerPulse(icon: "gobackward.10")
                resetControlsTimer()
            }

            // 10s Forward
            PlayerHUDButton(icon: "goforward.10", tooltip: String(localized: "Seek Forward 10s")) {
                bridge.seekBy(offset: 10)
                triggerPulse(icon: "goforward.10")
                resetControlsTimer()
            }

            // Current Time (Monospaced)
            Text(formatTime(bridge.isScrubbing ? bridge.scrubTime : bridge.currentTime))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .frame(minWidth: 38, alignment: .trailing)

            // Interactive Live Scrubber (Smooth GeometryReader)
            NativePlayerScrubber(bridge: bridge)

            // Duration (Monospaced)
            Text(formatTime(bridge.duration))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(minWidth: 38, alignment: .leading)

            // Playback Speed Menu
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                    Button {
                        bridge.setPlaybackRate(rate)
                        resetControlsTimer()
                    } label: {
                        HStack {
                            Text(rate == 1.0 ? "1.0x (Normal)" : String(format: "%.2gx", rate))
                            if bridge.playbackRate == rate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(bridge.playbackRate == 1.0 ? "1x" : String(format: "%.2gx", bridge.playbackRate))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "Playback Speed"))

            // Zero-Layout-Shift Volume Control (Floating Glass Capsule Anchored Above)
            volumeControlWithFloatingCapsule

            // Picture-in-Picture Button
            PlayerHUDButton(icon: "pip.enter", tooltip: String(localized: "Picture in Picture")) {
                bridge.triggerPictureInPicture()
                resetControlsTimer()
            }

            // Fullscreen Button
            PlayerHUDButton(
                icon: isModalFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                tooltip: isModalFullscreen ? String(localized: "Exit Fullscreen") : String(localized: "Fullscreen")
            ) {
                if let onToggle = onToggleFullscreen {
                    onToggle()
                } else {
                    bridge.toggleFullscreen()
                }
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
                bridge.toggleMute()
                resetControlsTimer()
            } label: {
                Image(systemName: bridge.isMuted || bridge.volume == 0 ? "speaker.slash.fill" : (bridge.volume > 0.5 ? "speaker.wave.3.fill" : "speaker.wave.1.fill"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(isVolumeHovered ? 0.16 : 0.0))
                    )
            }
            .buttonStyle(.plain)
            .help(bridge.isMuted ? String(localized: "Unmute") : String(localized: "Mute"))
        }
        .frame(width: 26, height: 26)
        .overlay(alignment: .top) {
            if isVolumeExpanded {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { bridge.isMuted ? 0.0 : bridge.volume },
                            set: { bridge.setVolume($0) }
                        ),
                        in: 0...1
                    )
                    .frame(width: 76)
                    .controlSize(.mini)

                    Text("\(Int((bridge.isMuted ? 0 : bridge.volume) * 100))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.45), radius: 10, x: 0, y: 4)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .offset(y: -44)
                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
            }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                isVolumeExpanded = hovering
                isVolumeHovered = hovering
            }
        }
    }

    private func resetControlsTimer() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isControlsVisible = true
        }
        hideWorkItem?.cancel()

        let task = DispatchWorkItem {
            if bridge.isPlaying && !bridge.isScrubbing && !isVolumeExpanded {
                withAnimation(.easeInOut(duration: 0.35)) {
                    isControlsVisible = false
                }
            }
        }
        hideWorkItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: task)
    }

    private func triggerPulse(icon: String) {
        feedbackIcon = icon
        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
            showFeedbackPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.25)) {
                showFeedbackPulse = false
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "00:00" }
        let totalSec = Int(seconds)
        let hours = totalSec / 3600
        let minutes = (totalSec % 3600) / 60
        let secs = totalSec % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}

// MARK: - Full-Window Cinematic Video Modal

struct FullscreenVideoModal: View {
    let videoID: String
    let title: String
    let link: String
    let onClose: () -> Void

    @StateObject private var bridge = PlayerBridgeController()

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // 16:9 Video Canvas Centered in Full Window
            NativeVideoPlayerCanvas(
                videoID: videoID,
                title: title,
                bridge: bridge,
                isModalFullscreen: true,
                onToggleFullscreen: onClose
            )
            .aspectRatio(16/9, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Top Bar: Clean Frosted Title Pill + Exit Fullscreen Button
            VStack {
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
                        onClose()
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

                Spacer()
            }
        }
        .onAppear {
            bridge.play()
        }
        .onDisappear {
            bridge.pause()
        }
    }
}

// MARK: - Player HUD Button (Apple HIG Hover Pill Style)

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

// MARK: - Native Player Scrubber (Interactive Live Slider with Buffer Bar)

struct NativePlayerScrubber: View {
    @ObservedObject var bridge: PlayerBridgeController
    @State private var isHovered: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let duration = max(bridge.duration, 0.001)
            let progress = bridge.isScrubbing ? (bridge.scrubTime / duration) : (bridge.currentTime / duration)
            let clampedProgress = max(0, min(progress, 1.0))
            let bufferedFraction = max(0, min(bridge.bufferedTime / duration, 1.0))

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: isHovered || bridge.isScrubbing ? 6 : 3.5)

                // Buffered Track
                Capsule()
                    .fill(Color.white.opacity(0.38))
                    .frame(width: totalWidth * CGFloat(bufferedFraction), height: isHovered || bridge.isScrubbing ? 6 : 3.5)

                // Progress Track
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.orange.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: totalWidth * CGFloat(clampedProgress), height: isHovered || bridge.isScrubbing ? 6 : 3.5)

                // Thumb Handle
                Circle()
                    .fill(Color.white)
                    .frame(width: isHovered || bridge.isScrubbing ? 13 : 8, height: isHovered || bridge.isScrubbing ? 13 : 8)
                    .shadow(color: Color.black.opacity(0.5), radius: 3, x: 0, y: 1)
                    .offset(x: max(0, min(totalWidth * CGFloat(clampedProgress) - (isHovered || bridge.isScrubbing ? 6.5 : 4), totalWidth - 13)))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        bridge.isScrubbing = true
                        let ratio = max(0, min(value.location.x / totalWidth, 1.0))
                        bridge.scrubTime = Double(ratio) * bridge.duration
                    }
                    .onEnded { value in
                        let ratio = max(0, min(value.location.x / totalWidth, 1.0))
                        let targetTime = Double(ratio) * bridge.duration
                        bridge.seek(to: targetTime)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            bridge.isScrubbing = false
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

// MARK: - Headless Hardware Video Canvas (WKWebView with Subframe PiP & Fullscreen Bridge)

struct CustomHeadlessWebView: NSViewRepresentable {
    let videoID: String
    let bridge: PlayerBridgeController

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.isElementFullscreenEnabled = true

        let weakHandler = WeakScriptMessageHandler(delegate: bridge)
        configuration.userContentController.add(weakHandler, name: "customPlayerBridge")

        // Injected Subframe Script: Runs directly inside the YouTube iframe (forMainFrameOnly: false)
        // This gives direct, same-origin access to the HTML5 <video> element for Picture-in-Picture & Fullscreen!
        let subframeScript = """
        (function() {
            window.addEventListener('message', function(e) {
                if (e.data === 'pip_toggle') {
                    var v = document.querySelector('video');
                    if (v) {
                        if (document.pictureInPictureElement) {
                            document.exitPictureInPicture();
                        } else if (v.requestPictureInPicture) {
                            v.requestPictureInPicture();
                        } else if (v.webkitSetPresentationMode) {
                            var mode = v.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture';
                            v.webkitSetPresentationMode(mode);
                        }
                    }
                } else if (e.data === 'fullscreen_toggle') {
                    var v = document.querySelector('video');
                    if (v) {
                        if (document.fullscreenElement || document.webkitFullscreenElement) {
                            if (document.exitFullscreen) document.exitFullscreen();
                            else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
                        } else {
                            if (v.requestFullscreen) v.requestFullscreen();
                            else if (v.webkitRequestFullscreen) v.webkitRequestFullscreen();
                            else if (v.webkitEnterFullscreen) v.webkitEnterFullscreen();
                        }
                    }
                }
            });
        })();
        """
        let userScript = WKUserScript(
            source: subframeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.black.cgColor
        bridge.webView = webView

        let embedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                :root, html, body, :-webkit-full-screen, :fullscreen {
                    width: 100% !important;
                    height: 100% !important;
                    background-color: #000000 !important;
                    overflow: hidden !important;
                    margin: 0 !important;
                    padding: 0 !important;
                }
                #player-wrap {
                    width: 100% !important;
                    height: 100% !important;
                    position: absolute;
                    top: 0; left: 0;
                    background-color: #000000 !important;
                    pointer-events: none;
                }
                #player, iframe {
                    width: 100% !important;
                    height: 100% !important;
                    border: none !important;
                    background-color: #000000 !important;
                }
            </style>
        </head>
        <body>
            <div id="player-wrap"><div id="player"></div></div>
            <script>
                var tag = document.createElement('script');
                tag.src = "https://www.youtube.com/iframe_api";
                var firstScriptTag = document.getElementsByTagName('script')[0];
                firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

                var player;
                function onYouTubeIframeAPIReady() {
                    player = new YT.Player('player', {
                        width: '100%',
                        height: '100%',
                        videoId: '\(videoID)',
                        playerVars: {
                            'autoplay': 1,
                            'controls': 0,
                            'modestbranding': 1,
                            'rel': 0,
                            'fs': 1,
                            'playsinline': 1,
                            'disablekb': 1,
                            'iv_load_policy': 3,
                            'enablejsapi': 1,
                            'origin': 'https://www.youtube-nocookie.com'
                        },
                        events: {
                            'onReady': onPlayerReady,
                            'onStateChange': onPlayerStateChange
                        }
                    });
                }

                function onPlayerReady(event) {
                    try {
                        event.target.playVideo();
                        var dur = player.getDuration() || 0;
                        sendBridgeMessage({ type: 'ready', duration: dur });
                        setInterval(reportProgress, 250);
                    } catch (e) {}
                }

                function onPlayerStateChange(event) {
                    try {
                        var stateStr = 'unstarted';
                        if (event.data == YT.PlayerState.PLAYING) stateStr = 'playing';
                        else if (event.data == YT.PlayerState.PAUSED) stateStr = 'paused';
                        else if (event.data == YT.PlayerState.BUFFERING) stateStr = 'buffering';
                        else if (event.data == YT.PlayerState.ENDED) stateStr = 'ended';
                        sendBridgeMessage({ type: 'state', state: stateStr });
                    } catch (e) {}
                }

                function reportProgress() {
                    try {
                        if (player && player.getCurrentTime) {
                            var cur = player.getCurrentTime() || 0;
                            var dur = player.getDuration() || 0;
                            var loaded = (player.getVideoLoadedFraction ? player.getVideoLoadedFraction() : 0) * dur;
                            sendBridgeMessage({ type: 'time', currentTime: cur, duration: dur, buffered: loaded });
                        }
                    } catch (e) {}
                }

                document.addEventListener('fullscreenchange', function() {
                    var isFs = !!(document.fullscreenElement || document.webkitFullscreenElement);
                    sendBridgeMessage({ type: 'fullscreen', isFullscreen: isFs });
                });
                document.addEventListener('webkitfullscreenchange', function() {
                    var isFs = !!(document.fullscreenElement || document.webkitFullscreenElement);
                    sendBridgeMessage({ type: 'fullscreen', isFullscreen: isFs });
                });

                function sendBridgeMessage(data) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.customPlayerBridge) {
                        window.webkit.messageHandlers.customPlayerBridge.postMessage(JSON.stringify(data));
                    }
                }
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(embedHTML, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: ()) {
        nsView.stopLoading()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "customPlayerBridge")
        nsView.load(URLRequest(url: URL(string: "about:blank")!))
    }
}
