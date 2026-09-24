# Versoline

**A private RSS reader for Mac**  
*Formerly easyRSS*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: macOS 15+](https://img.shields.io/badge/Platform-macOS%2015%2B%20(Sequoia)-black.svg)](https://www.apple.com/macos)
[![Swift: 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Dependencies: 0](https://img.shields.io/badge/Dependencies-0%20(System%20Only)-success.svg)](https://developer.apple.com)
[![Latest Release](https://img.shields.io/github/v/release/bezelye404/Versoline?include_prereleases&color=6366f1)](https://github.com/bezelye404/Versoline/releases/latest)

---

<!-- TODO: Add application screenshot here: docs/images/versoline-hero.png -->
<!-- ![Versoline Interface Preview](docs/images/versoline-hero.png) -->

Versoline is a lightweight, distraction-free RSS reader for macOS built with Swift 6 and SwiftUI with **zero third-party dependencies**. It brings standard RSS/Atom feeds, YouTube channels, Reddit communities, and podcasts together into a unified, privacy-first desktop workspace.

---

## 📥 Download

Download the latest version directly from the GitHub Releases page:

👉 **[Download Versoline v0.3.0 DMG](https://github.com/bezelye404/Versoline/releases/latest)**

### Requirements & Gatekeeper Note
- **Requirements:** macOS 15.0 (Sequoia) or newer. Compatible with both **Apple Silicon** (M1/M2/M3/M4) and **Intel** Macs.
- **Gatekeeper Setup:** Because Versoline is an independent open-source project and uses ad-hoc codesigning (no paid Apple Developer ID certificate), macOS may show an *"unidentified developer"* prompt upon first launch.
  - To open: **Right-click** (or Control-click) `Versoline.app` in `/Applications` and select **Open**, or run the following command in Terminal:
    ```bash
    xattr -cr /Applications/Versoline.app
    ```
---

## ✨ Features

### Feeds & Rich Media
- **RSS & Atom:** High-speed streaming parser for standard RSS 2.0 and Atom feeds.
- **YouTube Integration:** Paste channel handles (`@channel`), channel URLs, or video links directly into the feed prompt. Embedded videos feature seamless reparenting between inline preview and fullscreen view without reloading the player.
- **Reddit Communities:** Follow subreddits or user accounts with sort filters (`hot`, `new`, `top`, `rising`) and time ranges.
- **Podcast Studio:**
  - Search the iTunes podcast directory directly.
  - Streaming audio playback with scrubber, variable speed (0.5x–2.0x), sleep timer, and queue management.
  - Download episodes locally as `.mp3` files for offline listening.
  - Automatic chapter and timestamp detection with instant seeking.
- **Universal Mini Player:** Persistent docked media bar for continuous listening while reading articles.
- **Smart Streams:** Automatically categorizes unread articles into **Quick Reads** (< 3 min) and **Deep Reads** (> 7 min) based on word-count estimations.
- **Curated Feed Catalog:** Browse hundreds of quality feeds organized by topic, cached locally on-demand.
- **OPML 2.0:** One-click import and export preserving your folder structure.

### Focused Reading Experience
- **Distraction-Free Reader Mode:** Extracts core content, strips ads, trackers, banners, and layout bloat.
- **10 Matte Color Palettes:** Carefully tailored palettes (*Slate, Sepia, Sage, Dusk, Monochrome, Nordic, Espresso, Matcha, Bordeaux, Solarized*) harmonizing toolbars, sidebars, cards, badges, and reading surfaces in light and dark modes.
- **Typography & Bionic Reading:** 4 system font families, configurable font sizes and line heights, syntax highlighting for code snippets, and optional Bionic Reading mode for fast scanning.
- **Reading Insights:** Interactive reading statistics rendered with Apple Charts.
- **Quote Cards:** Generate Retina excerpt quote cards from selected text and copy them directly to your clipboard.
- **Built-In Web Browser:** Optional WebKit browser mode equipped with native content blocking rules to block ads and analytics trackers.
- **Text-to-Speech:** System voice synthesis to read long-form articles aloud.
- **Smart Folders:** Rule-based keyword engine to automatically group matching articles from across your subscriptions.

### Keyboard Shortcuts (Vim Navigation)
Configurable single-key keyboard navigation for rapid feed triaging:
- <kbd>J</kbd> / <kbd>K</kbd> — Next / Previous article
- <kbd>M</kbd> — Toggle Read / Unread status
- <kbd>S</kbd> — Toggle Bookmark
- <kbd>O</kbd> — Open in external browser (Safari, Chrome, Arc, Brave, Firefox, or System Default)
- <kbd>⌘</kbd> + <kbd>R</kbd> — Refresh all feeds

---

## 🔒 Architecture & Privacy

- **Zero External Dependencies:** Built entirely with first-party Apple system frameworks (`SwiftUI`, `WebKit`, `AVFoundation`, `MediaPlayer`, `Network`, `Charts`). No third-party packages, dynamic libraries, or analytics SDKs.
- **100% Offline-First & Local:** All subscriptions, cached favicons, offline podcasts, and articles reside locally under `~/Library/Application Support/Versoline`.
- **No Telemetry, No Accounts:** No user accounts, login portals, analytics tracking, or crash-reporting servers. Network requests travel directly from your Mac to the origin feed servers.
- **Resource Efficient:** Ephemeral network sessions, downsampled favicon caching, and automated memory compaction when the app is hidden or backgrounded.

---

## 🛠️ Building from Source

### Prerequisites
- macOS 15.0 (Sequoia) or newer
- Xcode 16.0 or newer (Swift 6.0 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [create-dmg](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`, optional for DMG packaging)

### Build Commands

```bash
# 1. Clone repository
git clone https://github.com/bezelye404/Versoline.git
cd Versoline

# 2. Generate Xcode project from project.yml specification
xcodegen generate

# 3. Build release binary
xcodebuild -project Versoline.xcodeproj -scheme Versoline -configuration Release build

# 4. (Optional) Run automated unit test suite
xcodebuild test -project Versoline.xcodeproj -scheme Versoline -destination 'platform=macOS'

# 5. (Optional) Package a distributable DMG
./scripts/build-dmg.sh
```

---

## 👥 Credits

Curated feed lists in the discovery catalog are maintained with contributions from:
- [@joshuawalcher](https://github.com/joshuawalcher) — [joshuawalcher/rssfeeds](https://github.com/joshuawalcher/rssfeeds)
- [@bakinazik](https://github.com/bakinazik) — [bakinazik/rss](https://github.com/bakinazik/rss)

---

## 📄 License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.
