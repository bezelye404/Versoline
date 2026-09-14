import SwiftUI
import AppKit

struct MiniPlayerView: View {

    @Bindable private var player = AudioPlayerService.shared
    @Environment(FeedStore.self) private var store
    @State private var showQueuePopover = false

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
        let text = "\(item.title)\n\(player.shareURLString(for: item))"
        let picker = NSSharingServicePicker(items: [text])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .maxY)
        }
    }

    var body: some View {
        if let episode = player.currentEpisode {
            VStack(spacing: 0) {
                Divider()

                HStack(spacing: 16) {
                    // MARK: - Left: Episode Info, Artwork & Equalizer
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                                .frame(width: 36, height: 36)

                            if let feed = store.feed(for: episode.feedId) {
                                FaviconView(hostOrURL: feed.url, size: 20)
                            } else {
                                Image(systemName: "headphones")
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppTheme.Colors.podcast)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(AppTheme.Colors.hairlineBorder, lineWidth: 0.5)
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(episode.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                EqualizerWaveformView(isPlaying: player.isPlaying, barWidth: 1.5, maxHeight: 9)
                            }

                            Text(player.currentFeedTitle ?? episode.author ?? String(localized: "Podcast"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(minWidth: 150, idealWidth: 200, maxWidth: 260, alignment: .leading)

                    Spacer(minLength: 8)

                    // MARK: - Center: Transport Controls & Scrubber
                    VStack(spacing: 4) {
                        // Buttons
                        HStack(spacing: 14) {
                            Button {
                                AppHaptics.tap()
                                player.skipBackward(seconds: 15)
                            } label: {
                                Image(systemName: "gobackward.15")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(String(localized: "Skip backward 15 seconds"))

                            Button {
                                AppHaptics.tap()
                                withAnimation(AppAnimation.bouncy) {
                                    player.togglePlayPause()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.Colors.accent)
                                        .frame(width: 30, height: 30)

                                    if player.isBuffering {
                                        ProgressView()
                                            .controlSize(.small)
                                            .colorInvert()
                                    } else {
                                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .offset(x: player.isPlaying ? 0 : 1)
                                            .contentTransition(.symbolEffect(.replace))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(player.isPlaying ? String(localized: "Pause") : String(localized: "Play"))

                            Button {
                                AppHaptics.tap()
                                player.skipForward(seconds: 15)
                            } label: {
                                Image(systemName: "goforward.15")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(String(localized: "Skip forward 15 seconds"))
                        }

                        // Scrubber Slider
                        HStack(spacing: 7) {
                            Text(formatTime(player.currentTime))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)

                            Slider(
                                value: Binding(
                                    get: { player.currentTime },
                                    set: { player.seek(to: $0) }
                                ),
                                in: 0...max(player.duration, 1.0)
                            )
                            .controlSize(.mini)
                            .tint(AppTheme.Colors.accent)

                            Text(player.duration > 0 ? formatRemainingTime(current: player.currentTime, total: player.duration) : "--:--")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: 440)

                    Spacer(minLength: 8)

                    // MARK: - Right: Tools (Speed, Sleep Timer, Queue, Share, Volume, Close)
                    HStack(spacing: 8) {
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
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help(String(localized: "Playback Speed"))

                        // Sleep Timer Menu
                        Menu {
                            Button(String(localized: "Turn Off Timer")) {
                                player.cancelSleepTimer()
                            }
                            Divider()
                            Button("15 " + String(localized: "minutes")) {
                                player.startSleepTimer(minutes: 15)
                            }
                            Button("30 " + String(localized: "minutes")) {
                                player.startSleepTimer(minutes: 30)
                            }
                            Button("45 " + String(localized: "minutes")) {
                                player.startSleepTimer(minutes: 45)
                            }
                            Button("60 " + String(localized: "minutes")) {
                                player.startSleepTimer(minutes: 60)
                            }
                            Button(String(localized: "End of Episode")) {
                                player.startSleepTimerUntilEndOfEpisode()
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: player.sleepTimerRemainingSeconds != nil ? "moon.zzz.fill" : "moon.zzz")
                                    .font(.system(size: 11))
                                if let remaining = player.sleepTimerRemainingSeconds {
                                    Text("\(max(1, remaining / 60))m")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                }
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                player.sleepTimerRemainingSeconds != nil ? AppTheme.Colors.accent.opacity(0.12) : Color.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )
                            .foregroundStyle(player.sleepTimerRemainingSeconds != nil ? AppTheme.Colors.accent : Color.secondary)
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
                                    .foregroundStyle(showQueuePopover || !player.queue.isEmpty ? AppTheme.Colors.accent : Color.secondary)

                                if !player.queue.isEmpty {
                                    Circle()
                                        .fill(AppTheme.Colors.accent)
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

                        // Volume Popover / Slider
                        HStack(spacing: 4) {
                            Image(systemName: player.volume == 0 ? "speaker.slash.fill" : (player.volume < 0.5 ? "speaker.1.fill" : "speaker.3.fill"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .onTapGesture {
                                    AppHaptics.tap()
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
                            .frame(width: 44)
                        }

                        // Close Player
                        Button {
                            AppHaptics.tap()
                            withAnimation(AppAnimation.pageReveal) {
                                player.close()
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
                    .frame(minWidth: 190, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
