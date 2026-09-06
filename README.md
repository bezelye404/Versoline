# easyRSS

A swiss-knife RSS reader built for macOS. Written in Swift and SwiftUI with zero third-party dependencies.

---

## Features

### Feeds & Content

- **RSS & Atom**: Supports standard RSS 2.0 and Atom feeds.
- **YouTube Channels**: Paste any channel handle (`@.........`), channel URL, or channel name to automatically resolve and subscribe to its video feed.
- **Subreddits & Users**: Add feeds for any subreddit or Reddit user with custom sorting (`hot`, `new`, `top`, `rising`) and time filters.
- **Podcasts**:
  - In-app iTunes podcast search engine.
  - Streaming audio playback with mini player, scrub bar, playback speed (0.75x–2.0x), and sleep timer.
  - Offline episode download management (`.mp3`).
  - Chapter and timestamp detection with instant jump.
- **Curated Catalog**: 460+ verified feeds across tech, news, science, podcasts, and video channels, automatically synced from remote CDN with local caching.
- **OPML Support**: Import and export OPML 2.0 subscription lists.

### Reading Experience

- **Reader Mode**: Distraction-free article view stripping ads, wrappers, and tracking scripts.
- **Customizable Typography**: 5 themes (System, Light, Sepia, Dark, OLED Black), 4 font families, adjustable font size, and line spacing.
- **In-App Web Browser**: Optional live WebKit browser mode equipped with a built-in content blocker targeting ad and tracking networks.
- **Text-to-Speech**: Native system speech synthesis for reading articles aloud.
- **Smart Folders**: Keyword-based rule engine that dynamically groups matching articles from any feed into folders.

### Power-User & Shortcuts

- **Single-Key Navigation**: Vim-style single-key shortcuts (toggleable in Settings):
  - `J` / `K`: Next / Previous article
  - `M`: Toggle Read / Unread
  - `S`: Toggle Bookmark
  - `O`: Open in external browser
- **External Browser Integration**: Open links in Safari, Chrome, Arc, Brave, Firefox, or the system default browser.

---

## Architecture & Privacy

- **Zero External Dependencies**: Uses only Apple system frameworks (`SwiftUI`, `WebKit`, `AVFoundation`, `MediaPlayer`, `Network`).
- **Offline First**: Articles, downloaded episodes, favicons, and feeds are stored locally in `~/Library/Application Support/EasyRSS`.
- **No Accounts, No Telemetry**: No third-party analytics, no account requirements, and no intermediary servers. Requests are made directly between your Mac and the feed hosts.

---

## Requirements

- **Operating System**: macOS 15.0 (Sequoia) or newer
- **Architecture**: Apple Silicon (arm64) & Intel (x86_64)
- **Build Tools**: Xcode 16.0+ / Swift 6.0, `xcodegen`

---

## Building from Source

```bash
git clone https://github.com/bezelye404/easyRSS.git
cd easyRSS

# Generate Xcode project
xcodegen generate

# Build release binary
xcodebuild -project EasyRSS.xcodeproj -scheme EasyRSS -configuration Release build
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
