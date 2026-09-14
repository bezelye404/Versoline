# easyRSS

A very lightweight, swiss-knife RSS reader built for macOS. Written in Swift and SwiftUI with zero third-party dependencies.

---

## Features

### Feeds & Content

- **RSS & Atom**: Supports standard RSS 2.0 and Atom feeds.
- **YouTube Channels & Videos**:
  - Paste any channel handle (`@...`), channel URL, or video link to resolve and subscribe.
  - Dedicated Videos section in the sidebar with native embedded playback and zero-reload fullscreen mode.
- **Subreddits & Users**: Add feeds for any subreddit or Reddit user with custom sorting (`hot`, `new`, `top`, `rising`) and time filters.
- **Podcasts**:
  - In-app iTunes podcast search engine.
  - Streaming playback with scrub bar, playback speed (0.5x–2.0x), sleep timer, and up-next queue.
  - Offline episode download management (`.mp3`).
  - Chapter and timestamp detection with instant seek.
- **Universal Mini Player**: Persistent bottom dock player for podcasts and videos with playback speed, scrubber, volume control, fullscreen toggle, and single-click navigation back to the origin article.
- **Smart Streams**: Automatic filtering for Quick Reads (< 3 min) and Deep Reads (> 7 min).
- **Curated Catalog**: 460+ verified feeds across tech, news, science, podcasts, and video channels, synced from remote CDN with local caching.
- **OPML Support**: Import and export OPML 2.0 subscription lists.

### Reading Experience

- **Reader Mode**: Distraction-free article view stripping ads, wrappers, and tracking scripts.
- **Themes & Palettes**: 5 full-app color palettes (Slate, Sepia, Sage, Dusk, Monochrome) coordinating the sidebar, list, card accents, and reader backgrounds in dynamic light and dark modes.
- **Typography & Bionic Reading**: 4 font families, adjustable font size, line spacing, native Bionic Reading mode, and code syntax highlighting.
- **Reading Insights**: Reading habits overview powered by Apple Charts.
- **Quote Cards**: Generate formatted quote snippet cards from article excerpts and copy them to the clipboard.
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

- **Zero External Dependencies**: Uses only Apple system frameworks (`SwiftUI`, `WebKit`, `AVFoundation`, `MediaPlayer`, `Network`, `Charts`).
- **Low Resource Usage**: Downsampled favicon caching, single-instance video WebProcess reparenting, and lightweight in-memory storage keeping memory usage minimal.
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

## Credits

Feed collections in the curated catalog are sourced from:

- [@joshuawalcher](https://github.com/joshuawalcher) — [joshuawalcher/rssfeeds](https://github.com/joshuawalcher/rssfeeds)
- [@bakinazik](https://github.com/bakinazik) — [bakinazik/rss](https://github.com/bakinazik/rss)

---

## License

MIT License. See [LICENSE](LICENSE) for details.
