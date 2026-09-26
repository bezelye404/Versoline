# Versoline

### A private, distraction-free RSS and podcast reader for macOS.

[![Platform: macOS 15+](https://img.shields.io/badge/Platform-macOS%2015%2B%20(Sequoia)-black.svg)](https://www.apple.com/macos)
[![Swift: 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Dependencies: 0](https://img.shields.io/badge/Dependencies-0%20(System%20Only)-success.svg)](https://developer.apple.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/bezelye404/Versoline?include_prereleases&color=6366f1)](https://github.com/bezelye404/Versoline/releases/latest)

---

Versoline is a lightweight, distraction-free feed reader crafted exclusively for macOS with Swift 6 and SwiftUI.

Built with **strictly zero third-party dependencies**, **no user accounts**, and **zero telemetry**, Versoline brings your daily articles, audio podcasts, YouTube channels, and Reddit feeds together into one calm, private desktop space.

👉 **[Download Versoline v0.3.0 for macOS](https://github.com/bezelye404/Versoline/releases/latest)**  
*Requires macOS 15.0 Sequoia or newer. Universal binary for Apple Silicon (M1–M4) & Intel Macs.*

---

## Why Versoline?

The modern web is dominated by algorithmic timelines designed to capture attention rather than inform. Reading has become fragmented across noisy social platforms, browser tabs, and bloated web wrappers that track your every click.

Versoline is designed around a simpler, quieter philosophy:

* **Calm by Default:** A clean three-column native macOS design with 10 desaturated matte palettes and typography crafted for hours of comfortable reading.
* **One Inbox for Your Media:** Read long-form writing, stream or download podcasts, follow YouTube channels, and browse Reddit subreddits without switching contexts.
* **Radical Privacy:** No accounts, no analytics, no intermediary proxy servers. Your Mac connects directly to the source publishers, and all data stays strictly on your machine.
* **Featherlight & Native:** Built exclusively with first-party Apple system frameworks. Instant launch times, minimal battery consumption, and a lean memory footprint.

---

## ✨ Features

### 📡 Unified Media & Feed Hub
- **Fast RSS 2.0 & Atom Parsing:** High-performance streaming parser for standard feeds, blogs, and news publications.
- **Integrated Podcast Studio:**
  - Search the iTunes podcast directory directly from within the app.
  - Background audio playback with variable speeds (0.5x–2.0x), sleep timer, and queue management.
  - Download full episodes locally as `.mp3` files for offline listening.
  - Automatic chapter and timestamp detection with instant timeline seeking.
- **Docked Mini Player:** A persistent, compact audio bar that lets you keep listening while triaging unread feeds.
- **YouTube Channels & Playlists:** Paste channel handles (`@channel`), channel URLs, or video links. Videos play inside a seamless embedded player that reparents between list cards and fullscreen without interrupting playback or reloading.
- **Reddit Communities:** Follow subreddits or user accounts with sort filters (`hot`, `new`, `top`, `rising`) and customizable time windows.
- **Smart Streams:** Automatically organizes your unread queue into **Quick Reads** (< 3 min) and **Deep Reads** (> 7 min) based on word-count estimations.
- **Curated Feed Catalog:** Browse a rich library of pre-configured, reputable feeds organized by topic (Technology, Design, Science, and News).
- **OPML 2.0 Import & Export:** Effortlessly transfer your subscriptions with complete folder taxonomy intact.

### 📖 Thoughtful Reading Experience
- **Distraction-Free Reader Mode:** Strips ads, layout bloat, paywall banners, and trackers, leaving only clean typography and imagery.
- **10 Matte Color Palettes:** Carefully tuned color palettes (*Slate, Sepia, Sage, Dusk, Monochrome, Nordic, Espresso, Matcha, Bordeaux, Solarized*) with complete light and dark mode parity.
- **Bionic Reading:** Optional typographic fixation mode to guide your eyes through dense articles for faster scanning.
- **Custom Typography:** Choose between system fonts (San Francisco, New York serif, Monospace), configure line heights, font sizes, and view code blocks with syntax highlighting.
- **Retina Quote Cards:** Create beautiful, high-resolution excerpt cards from highlighted text, ready to paste into Notes or share.
- **Text-to-Speech:** Listen to long-form articles read aloud using macOS system voice synthesis.
- **Smart Folders:** Rule-based keyword engine to automatically group matching articles from across all subscriptions.
- **Reading Insights:** Interactive reading statistics rendered with Apple Charts to help you track your reading habits.
- **In-App Web Browser:** Optional native WebKit browser equipped with content-blocking rules to block external ads and trackers.

### ⌨️ Keyboard Ergonomics (Vim Navigation)
Process your daily reading queue at speed without reaching for the mouse:
- <kbd>J</kbd> / <kbd>K</kbd> — Next / Previous article
- <kbd>M</kbd> — Toggle Read / Unread status
- <kbd>S</kbd> — Star / Bookmark article
- <kbd>O</kbd> — Open original article in your browser of choice (Safari, Arc, Chrome, Brave, Firefox, or System Default)
- <kbd>⌘</kbd> + <kbd>R</kbd> — Refresh all feeds

---

## 🔒 Privacy & Architecture

- **Zero Third-Party Dependencies:** 100% native Swift 6 and SwiftUI. Built strictly on first-party Apple frameworks (`WebKit`, `AVFoundation`, `MediaPlayer`, `Network`, `Charts`). No third-party packages, dynamic libraries, or closed-source tracking SDKs.
- **100% Local Storage:** All feeds, articles, offline audio episodes, and cached favicons reside locally on your disk under `~/Library/Application Support/Versoline`.
- **Direct Networking:** Your computer communicates directly with the source RSS and podcast servers. There are no cloud relays, proxy servers, or caching middle tiers.
- **Ephemeral WebSessions:** Reader Mode uses isolated, ephemeral WebKit data stores (`WKWebsiteDataStore.nonPersistent()`), ensuring that cookies and cross-site trackers cannot accumulate.
- **Memory & Resource Care:** Employs pre-decode CoreGraphics thumbnail downsampling (`CGImageSourceCreateThumbnailAtIndex`) and memory compaction when the app is backgrounded to maintain a strict RAM ceiling.

---

## 📥 Installation

1. Download the latest **[Versoline v0.3.0 DMG](https://github.com/bezelye404/Versoline/releases/latest)**.
2. Open the `.dmg` file and drag **Versoline.app** into your **Applications** folder.

### Gatekeeper Note
Because Versoline is an independent open-source project with ad-hoc signing (no annual paid Apple Developer certificate), macOS Gatekeeper may present an *"unidentified developer"* prompt upon first launch.

To open Versoline:
- **Right-click** (or Control-click) `Versoline.app` in `/Applications` and select **Open**, or run the following command in Terminal:
  ```bash
  xattr -cr /Applications/Versoline.app
  ```

---

## 🛠️ Building from Source

### Prerequisites
- macOS 15.0 (Sequoia) or newer
- Xcode 16.0 or newer (Swift 6 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [create-dmg](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`, optional for disk packaging)

### Build Commands

```bash
# 1. Clone the repository
git clone https://github.com/bezelye404/Versoline.git
cd Versoline

# 2. Generate the Xcode project from the project.yml specification
xcodegen generate

# 3. Build the Release binary
xcodebuild -project Versoline.xcodeproj -scheme Versoline -configuration Release build

# 4. (Optional) Run the automated test suite
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
