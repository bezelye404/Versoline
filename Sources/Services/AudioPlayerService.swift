import Foundation
import SwiftUI
import AVFoundation
import MediaPlayer

@MainActor
@Observable
final class AudioPlayerService {

    static let shared = AudioPlayerService()

    private(set) var currentEpisode: FeedItem?
    private(set) var currentFeedTitle: String?
    var isPlaying: Bool = false
    var currentTime: Double = 0.0
    var duration: Double = 0.0
    var playbackRate: Float = 1.0
    var volume: Float = 1.0 {
        didSet {
            player?.volume = volume
        }
    }
    var isBuffering: Bool = false
    var errorMessage: String?

    // Supported playback speeds
    static let availableRates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private weak var feedStore: FeedStore?
    private var lastSavedPosition: Double = 0.0
    private var commandsConfigured = false

    private init() {
        setupRemoteCommands()
        setupTerminationObserver()
    }

    // MARK: - Playback Control

    func play(item: FeedItem, feedTitle: String? = nil, store: FeedStore) {
        guard let urlString = item.audioURL, let url = URL(string: urlString) else {
            errorMessage = "Invalid audio stream URL."
            return
        }

        self.feedStore = store
        self.errorMessage = nil

        // If clicking the currently playing item, toggle play/pause
        if currentEpisode?.id == item.id {
            togglePlayPause()
            return
        }

        // Save progress for existing episode before switching
        persistCurrentProgress()

        // Cleanup previous player observers
        cleanupObservers()

        currentEpisode = item
        currentFeedTitle = feedTitle
        currentTime = item.playbackPosition
        duration = 0.0
        isBuffering = true

        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.volume = volume
        self.player = newPlayer

        // Observe Item Status & Duration
        statusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .readyToPlay {
                    self.isBuffering = false
                    let itemDuration = item.duration.seconds
                    if itemDuration.isFinite && itemDuration > 0 {
                        self.duration = itemDuration
                    }
                    self.updateNowPlayingInfo()
                } else if item.status == .failed {
                    self.isBuffering = false
                    self.errorMessage = item.error?.localizedDescription ?? "Playback failed."
                    AppLogger.shared.log("Audio playback error: \(self.errorMessage ?? "")", level: .error, category: .ui)
                }
            }
        }

        // Periodic Time Observer (every 0.5s for smooth UI scrubbing)
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, let curItem = self.currentEpisode else { return }
                let currentSecs = time.seconds
                if currentSecs.isFinite && currentSecs >= 0 {
                    self.currentTime = currentSecs

                    // Fallback duration if not set by item
                    if self.duration <= 0, let itemDur = self.player?.currentItem?.duration.seconds, itemDur.isFinite && itemDur > 0 {
                        self.duration = itemDur
                    }

                    // Periodic auto-save every 5 seconds
                    if abs(currentSecs - self.lastSavedPosition) >= 5.0 {
                        self.lastSavedPosition = currentSecs
                        self.feedStore?.updatePlaybackProgress(
                            for: curItem.id,
                            feedId: curItem.feedId,
                            position: currentSecs,
                            isFinished: false
                        )
                    }
                }
            }
        }

        // Observe end of playback
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        // Resume from saved position if user previously listened
        if item.playbackPosition > 5 && !item.isFinished {
            let targetTime = CMTime(seconds: item.playbackPosition, preferredTimescale: 600)
            newPlayer.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in
                    self?.player?.rate = self?.playbackRate ?? 1.0
                    self?.isPlaying = true
                    self?.updateNowPlayingInfo()
                }
            }
        } else {
            newPlayer.rate = playbackRate
            isPlaying = true
            updateNowPlayingInfo()
        }

        AppLogger.shared.log("Streaming podcast episode: \(item.title)", level: .info, category: .ui)
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        persistCurrentProgress()
        updateNowPlayingInfo()
    }

    func resume() {
        guard let player else { return }
        player.rate = playbackRate
        isPlaying = true
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        currentTime = clamped

        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.persistCurrentProgress()
                self?.updateNowPlayingInfo()
            }
        }
    }

    func skipForward(seconds: Double = 15) {
        seek(to: currentTime + seconds)
    }

    func skipBackward(seconds: Double = 15) {
        seek(to: currentTime - seconds)
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
        updateNowPlayingInfo()
    }

    func close() {
        pause()
        persistCurrentProgress()
        cleanupObservers()
        player = nil
        currentEpisode = nil
        currentFeedTitle = nil
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Handlers & Observers

    @objc private func playerItemDidReachEnd(_ notification: Notification) {
        guard let episode = currentEpisode else { return }
        isPlaying = false
        currentTime = 0.0
        lastSavedPosition = 0.0
        feedStore?.updatePlaybackProgress(
            for: episode.id,
            feedId: episode.feedId,
            position: 0.0,
            isFinished: true
        )
        updateNowPlayingInfo()
        AppLogger.shared.log("Finished playing episode: \(episode.title)", level: .info, category: .ui)
    }

    private func persistCurrentProgress() {
        guard let episode = currentEpisode else { return }
        feedStore?.updatePlaybackProgress(
            for: episode.id,
            feedId: episode.feedId,
            position: currentTime,
            isFinished: false
        )
    }

    private func cleanupObservers() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    private func setupTerminationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.persistCurrentProgress()
            }
        }
    }

    // MARK: - macOS Now Playing & MPRemoteCommandCenter Integration

    private func setupRemoteCommands() {
        guard !commandsConfigured else { return }
        commandsConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.resume()
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.skipForward(seconds: 15)
            }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.skipBackward(seconds: 15)
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in
                self?.seek(to: posEvent.positionTime)
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0
        ]

        if let feedTitle = currentFeedTitle, !feedTitle.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyArtist] = feedTitle
        } else if let author = episode.author, !author.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyArtist] = author
        }

        if duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
