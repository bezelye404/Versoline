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

    // Playback Queue (Up Next)
    var queue: [FeedItem] = []

    // Sleep Timer
    var sleepTimerRemainingSeconds: Int? = nil
    var sleepTimerTotalSeconds: Int? = nil
    private var sleepTimerTask: Task<Void, Never>?
    private var preFadeVolume: Float = 1.0

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
        guard let urlString = item.audioURL, let streamURL = URL(string: urlString) else {
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

        // Check if offline local download exists
        let playbackURL: URL
        if let localURL = PodcastDownloadService.shared.localFileURL(for: item.id) {
            playbackURL = localURL
            AppLogger.shared.log("Streaming from offline downloaded file: \(item.title)", level: .info, category: .storage)
        } else {
            playbackURL = streamURL
        }

        let playerItem = AVPlayerItem(url: playbackURL)
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
        guard player != nil else { return }
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
        cancelSleepTimer()
        persistCurrentProgress()
        cleanupObservers()
        player = nil
        currentEpisode = nil
        currentFeedTitle = nil
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Playback Queue (Up Next)

    func addToQueue(_ item: FeedItem) {
        guard item.isPodcast, !queue.contains(where: { $0.id == item.id }) else { return }
        queue.append(item)
    }

    func playNext(_ item: FeedItem) {
        guard item.isPodcast else { return }
        queue.removeAll(where: { $0.id == item.id })
        queue.insert(item, at: 0)
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        queue.remove(at: index)
    }

    func clearQueue() {
        queue.removeAll()
    }

    // MARK: - Sleep Timer with Fade-Out

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        let seconds = minutes * 60
        sleepTimerTotalSeconds = seconds
        sleepTimerRemainingSeconds = seconds
        preFadeVolume = volume
        runSleepTimer()
    }

    func startSleepTimerUntilEndOfEpisode() {
        cancelSleepTimer()
        let remaining = max(1, Int(duration - currentTime))
        sleepTimerTotalSeconds = remaining
        sleepTimerRemainingSeconds = remaining
        preFadeVolume = volume
        runSleepTimer()
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerRemainingSeconds = nil
        sleepTimerTotalSeconds = nil
        if volume != preFadeVolume {
            volume = preFadeVolume
        }
    }

    private func runSleepTimer() {
        sleepTimerTask = Task { @MainActor in
            while let current = sleepTimerRemainingSeconds, current > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                let newRemaining = current - 1
                self.sleepTimerRemainingSeconds = newRemaining

                // Smooth fade out in the last 5 seconds
                if newRemaining <= 5 && newRemaining > 0 {
                    let fadeFraction = Float(newRemaining) / 5.0
                    self.volume = self.preFadeVolume * fadeFraction
                } else if newRemaining == 0 {
                    self.pause()
                    self.volume = self.preFadeVolume
                    self.sleepTimerRemainingSeconds = nil
                    self.sleepTimerTotalSeconds = nil
                    AppLogger.shared.log("Sleep timer expired - playback paused with audio fade-out", level: .info, category: .ui)
                    break
                }
            }
        }
    }

    // MARK: - Timestamp Share Text

    func shareURLString(for item: FeedItem) -> String {
        let secs = Int(currentTime)
        if secs > 0 && currentEpisode?.id == item.id {
            return "\(item.link)#t=\(secs)"
        }
        return item.link
    }

    // MARK: - Handlers & Observers

    @objc private func playerItemDidReachEnd(_ notification: Notification) {
        guard let episode = currentEpisode else { return }
        feedStore?.updatePlaybackProgress(
            for: episode.id,
            feedId: episode.feedId,
            position: 0.0,
            isFinished: true
        )

        // Check if there is an episode queued up in Up Next!
        if !queue.isEmpty, let store = feedStore {
            let nextItem = queue.removeFirst()
            AppLogger.shared.log("Episode ended. Auto-advancing to queued episode: \(nextItem.title)", level: .info, category: .ui)
            play(item: nextItem, feedTitle: nil, store: store)
            return
        }

        isPlaying = false
        currentTime = 0.0
        lastSavedPosition = 0.0
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
