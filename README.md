# easyRSS

An RSS reader for macOS built with Swift and SwiftUI, with zero third-party dependencies.

---

## Features

### Feeds & Content

- **RSS & Atom**: Supports standard RSS 2.0 and Atom feeds.
- **YouTube Channels & Videos**:
  - Resolves channel handles (`@...`), channel URLs, and video links directly into feed subscriptions.
  - Videos section in the sidebar with embedded playback and zero-reload reparenting between inline and fullscreen views.
- **Subreddits & Users**: Add feeds for subreddits or Reddit user profiles with sorting (`hot`, `new`, `top`, `rising`) and time filters.
- **Podcasts**:
  - iTunes podcast directory search.
  - Streaming playback with progress scrubber, playback speed (0.5x–2.0x), sleep timer, and queue management.
  - Offline episode download management (`.mp3`).
  - Chapter and timestamp detection with direct seeking.
- **Universal Mini Player**: Docked media player for podcasts and videos with playback controls, volume slider, fullscreen toggle, and origin article navigation.
- **Smart Streams**: Filter articles into Quick Reads (< 3 min) and Deep Reads (> 7 min) based on reading time estimation.
- **Curated Catalog**: Feed catalog organized by categories, loaded on-demand with local disk caching and memory eviction upon dismissal.
- **OPML Support**: Import and export OPML 2.0 subscription files.

### Reading Experience

- **Reader Mode**: Distraction-free article extraction removing ads, boilerplate layouts, and scripts.
- **Themes & Palettes**: 10 coordinated matte color palettes (Slate, Sepia, Sage, Dusk, Monochrome, Nordic, Espresso, Matcha, Bordeaux, Solarized) harmonizing window toolbar, sidebar, card hover states, unread count badges, and reader backgrounds in light and dark modes.
- **Typography & Bionic Reading**: 4 font families, adjustable font size, line spacing, native Bionic Reading mode, and syntax highlighting for code blocks.
- **Reading Insights**: Reading statistics overview rendered via Apple Charts.
- **Quote Cards**: Generate formatted excerpt cards from article text and copy them to the clipboard.
- **In-App Web Browser**: Optional WebKit browser mode with built-in content blocking rules for ad and tracker prevention.
- **Text-to-Speech**: System speech synthesis for reading article content aloud.
- **Smart Folders**: Rule-based categorization grouping matching articles from subscriptions into folders.

### Shortcuts & Navigation

- **Single-Key Navigation**: Vim-style keyboard navigation (configurable in Settings):
  - `J` / `K`: Next / Previous article
  - `M`: Toggle Read / Unread
  - `S`: Toggle Bookmark
  - `O`: Open in external browser
- **External Browser Integration**: Open article links in Safari, Chrome, Arc, Brave, Firefox, or the system default browser.

---

## Architecture & Privacy

- **Zero External Dependencies**: Built entirely on Apple system frameworks (`SwiftUI`, `WebKit`, `AVFoundation`, `MediaPlayer`, `Network`, `Charts`). No third-party packages, dynamic libraries, or binary dependencies.
- **Resource Management**: Downsampled image caching, single-instance WebProcess reparenting for video playback, ephemeral network requests, and on-demand data structures to keep memory consumption low.
- **Local Storage**: Subscriptions, saved articles, offline podcast episodes, and cached favicons reside locally in `~/Library/Application Support/EasyRSS`.
- **Privacy First**: No user accounts, telemetry, crash reporting services, or proxy servers. Network requests connect directly to origin feed hosts.

---

## Requirements

- **Operating System**: macOS 15.0 (Sequoia) or newer
- **Architecture**: Apple Silicon (arm64) and Intel (x86_64)
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
