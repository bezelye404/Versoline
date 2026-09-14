import Foundation
import SwiftUI
import WebKit
import Combine

// MARK: - Weak Script Message Handler (Retain Cycle Prevention)

private final class WeakVideoScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - VideoPlayerService

@MainActor
@Observable
final class VideoPlayerService: NSObject, WKScriptMessageHandler {

    static let shared = VideoPlayerService()

    // Active Item
    private(set) var currentVideo: FeedItem?
    private(set) var currentFeedTitle: String?
    private(set) var videoID: String?

    // Playback State
    var isPlaying: Bool = false
    var isBuffering: Bool = false
    var currentTime: Double = 0.0
    var duration: Double = 0.0
    var bufferedTime: Double = 0.0
    var playbackRate: Double = 1.0
    var volume: Double = 1.0 {
        didSet {
            let clamped = max(0, min(volume, 1.0))
            isMuted = (clamped == 0)
            executeJS("if (window.player && player.setVolume) { player.setVolume(\(Int(clamped * 100))); }")
        }
    }
    var isMuted: Bool = false
    var isReady: Bool = false
    var isScrubbing: Bool = false
    var scrubTime: Double = 0.0
    var isFullscreen: Bool = false

    // Available playback rates
    static let availableRates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    // Persistent WebKit Instance for zero-reload reparenting
    @ObservationIgnored var webView: WKWebView?
    @ObservationIgnored private var currentAttachedContainer: NSView?

    private override init() {
        super.init()
    }

    // MARK: - Setup WebKit View (Created Once & Recycled)

    private func ensureWebViewCreated() -> WKWebView {
        if let existing = webView {
            return existing
        }

        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.isElementFullscreenEnabled = true

        let weakHandler = WeakVideoScriptMessageHandler(delegate: self)
        configuration.userContentController.add(weakHandler, name: "customPlayerBridge")

        let wv = WKWebView(frame: .zero, configuration: configuration)
        wv.wantsLayer = true
        wv.layer?.backgroundColor = NSColor.black.cgColor
        self.webView = wv
        return wv
    }

    // MARK: - View Reparenting (Continuous Playback Without Reloading)

    func attach(to container: NSView) {
        let wv = ensureWebViewCreated()
        guard wv.superview != container else { return }

        wv.removeFromSuperview()
        wv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        currentAttachedContainer = container
    }

    func detachIfAttached(to container: NSView) {
        if let wv = webView, wv.superview == container {
            wv.removeFromSuperview()
            currentAttachedContainer = nil
        }
    }

    // MARK: - Playback Control

    func play(item: FeedItem, feedTitle: String? = nil) {
        guard let vID = item.youtubeVideoID else { return }

        // Pause active podcast if one is playing
        AudioPlayerService.shared.pause()

        if currentVideo?.id == item.id && videoID == vID {
            // Same video, toggle play
            togglePlayPause()
            return
        }

        currentVideo = item
        currentFeedTitle = feedTitle
        self.videoID = vID
        currentTime = 0.0
        duration = 0.0
        bufferedTime = 0.0
        isBuffering = true
        isPlaying = true

        let wv = ensureWebViewCreated()

        if isReady {
            // Already initialized, load new video instantly via YouTube JS API
            executeJS("if (window.player && player.loadVideoById) { player.loadVideoById({videoId: '\(vID)', startSeconds: 0}); } else { window.location.reload(); }")
        } else {
            // Initial load of embed HTML
            let embedHTML = generateEmbedHTML(videoID: vID)
            wv.loadHTMLString(embedHTML, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        AudioPlayerService.shared.pause()
        executeJS("if (window.player && player.playVideo) { player.playVideo(); }")
        isPlaying = true
    }

    func pause() {
        executeJS("if (window.player && player.pauseVideo) { player.pauseVideo(); }")
        isPlaying = false
    }

    func seek(to seconds: Double) {
        let maxDuration = duration > 0 ? duration : seconds
        let target = max(0, min(seconds, maxDuration))
        currentTime = target
        executeJS("if (window.player && player.seekTo) { player.seekTo(\(target), true); }")
    }

    func seekBy(offset: Double) {
        let base = isScrubbing ? scrubTime : currentTime
        seek(to: base + offset)
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        executeJS("if (window.player && player.setPlaybackRate) { player.setPlaybackRate(\(rate)); }")
    }

    func toggleMute() {
        if isMuted {
            isMuted = false
            let restoreVol = volume > 0.05 ? volume : 0.7
            volume = restoreVol
            executeJS("if (window.player) { if (player.unMute) player.unMute(); if (player.setVolume) player.setVolume(\(Int(restoreVol * 100))); }")
        } else {
            isMuted = true
            executeJS("if (window.player && player.mute) { player.mute(); }")
        }
    }

    func close() {
        pause()
        executeJS("if (window.player && player.stopVideo) { player.stopVideo(); }")
        webView?.removeFromSuperview()
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        webView = nil
        isReady = false
        currentVideo = nil
        currentFeedTitle = nil
        videoID = nil
        currentTime = 0.0
        duration = 0.0
        isPlaying = false
        isBuffering = false
        isFullscreen = false
    }

    // MARK: - Script Bridge Dispatch

    private func executeJS(_ js: String) {
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

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
        default:
            break
        }
    }

    // MARK: - Embed HTML Generator

    private func generateEmbedHTML(videoID: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                :root, html, body {
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
                            'fs': 0,
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

                function sendBridgeMessage(data) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.customPlayerBridge) {
                        window.webkit.messageHandlers.customPlayerBridge.postMessage(JSON.stringify(data));
                    }
                }
            </script>
        </body>
        </html>
        """
    }
}
