import SwiftUI

struct MiniPlayerView: View {

    @State private var player = AudioPlayerService.shared
    @Environment(FeedStore.self) private var store
    @State private var isHovered = false

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

    var body: some View {
        if let episode = player.currentEpisode {
            VStack(spacing: 0) {
                Divider()

                HStack(spacing: 16) {
                    // MARK: - Left: Episode Info & Artwork
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 40, height: 40)

                            if let feed = store.feed(for: episode.feedId) {
                                FaviconView(hostOrURL: feed.url, size: 22)
                            } else {
                                Image(systemName: "headphones")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(episode.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Text(player.currentFeedTitle ?? episode.author ?? String(localized: "Podcast"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(minWidth: 160, idealWidth: 220, maxWidth: 280, alignment: .leading)

                    Spacer(minLength: 8)

                    // MARK: - Center: Transport Controls & Scrubber
                    VStack(spacing: 4) {
                        // Buttons
                        HStack(spacing: 14) {
                            Button {
                                player.skipBackward(seconds: 15)
                            } label: {
                                Image(systemName: "gobackward.15")
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(String(localized: "Skip backward 15 seconds"))

                            Button {
                                player.togglePlayPause()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 32, height: 32)

                                    if player.isBuffering {
                                        ProgressView()
                                            .controlSize(.small)
                                            .colorInvert()
                                    } else {
                                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white)
                                            .offset(x: player.isPlaying ? 0 : 1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(player.isPlaying ? String(localized: "Pause") : String(localized: "Play"))

                            Button {
                                player.skipForward(seconds: 15)
                            } label: {
                                Image(systemName: "goforward.15")
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(String(localized: "Skip forward 15 seconds"))
                        }

                        // Scrubber Slider
                        HStack(spacing: 8) {
                            Text(formatTime(player.currentTime))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)

                            Slider(
                                value: Binding(
                                    get: { player.currentTime },
                                    set: { player.seek(to: $0) }
                                ),
                                in: 0...max(player.duration, 1.0)
                            )
                            .controlSize(.mini)
                            .tint(Color.accentColor)

                            Text(player.duration > 0 ? formatRemainingTime(current: player.currentTime, total: player.duration) : "--:--")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: 480)

                    Spacer(minLength: 8)

                    // MARK: - Right: Speed, Volume & Dismiss
                    HStack(spacing: 12) {
                        // Playback Speed Menu
                        Menu {
                            ForEach(AudioPlayerService.availableRates, id: \.self) { rate in
                                Button {
                                    player.setPlaybackRate(rate)
                                } label: {
                                    HStack {
                                        Text(String(format: "%.2fx", rate))
                                        if player.playbackRate == rate {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(String(format: "%.2fx", player.playbackRate))
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help(String(localized: "Playback Speed"))

                        // Volume Popover / Slider
                        HStack(spacing: 4) {
                            Image(systemName: player.volume == 0 ? "speaker.slash.fill" : (player.volume < 0.5 ? "speaker.1.fill" : "speaker.3.fill"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .onTapGesture {
                                    if player.volume > 0 {
                                        player.volume = 0
                                    } else {
                                        player.volume = 1.0
                                    }
                                }

                            Slider(
                                value: $player.volume,
                                in: 0.0...1.0
                            )
                            .controlSize(.mini)
                            .frame(width: 54)
                        }

                        // Close Player
                        Button {
                            player.close()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Close Player"))
                    }
                    .frame(minWidth: 150, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
