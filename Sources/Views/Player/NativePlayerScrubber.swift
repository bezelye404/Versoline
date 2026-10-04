import SwiftUI
import WebKit

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
                withAnimation(AppAnimation.safe(.spring(response: 0.25, dampingFraction: 0.75))) {
                    isHovered = hovering
                }
            }
        }
        .frame(height: 16)
    }
}
