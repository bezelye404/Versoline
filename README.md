# easyRSS

A fast, lightweight, and native RSS reader designed specifically for macOS. Built with Swift and SwiftUI for maximum performance, minimal resource usage, and a seamless desktop experience.

---

## Overview

easyRSS is designed to give you complete control over your news feeds without algorithmic timelines, telemetry, or clutter. It focuses on clean typography, keyboard navigation, and fast offline-first reading.

### Key Highlights

- **Pure Native Experience**: Built using SwiftUI and WebKit specifically for macOS (14.0+ Sonoma and later).
- **Distraction-Free Reader Mode**: Clean typography, customizable font sizes, and customizable themes that strip out unnecessary web clutter.
- **In-App Web Browser with Native Ad & Popup Blocking**:
  - Integrated WebKit Content Blocker rule engine targeting over 75 global and regional ad networks.
  - Hardened JavaScript-level popup, pop-under, and dialog neutralizer.
  - Completely isolated from local RSS reader content.
- **Privacy & Local Storage**: No account required, no remote servers, zero tracking. All feeds, bookmarks, and read states are saved locally on your Mac.
- **OPML 2.0 Compatibility**: Seamlessly import existing feed lists or export your subscriptions anytime.
- **Offline Capable**: Read previously fetched articles without an active internet connection.

---

### Feeds List

The curated feed collection in [`rss.md`](rss.md) is provided by [@joshuawalcher](https://github.com/joshuawalcher) from [joshuawalcher/rssfeeds](https://github.com/joshuawalcher/rssfeeds).

---

### Download & Installation

Download the latest `.dmg` installer from the **[Releases](../../releases)** page.

---

## Requirements

- **Operating System**: macOS 14.0 (Sonoma) or newer
- **Architecture**: Apple Silicon (M-series) and Intel (x86_64)
- **Development Toolchain**: Xcode 15.0+ / Swift 5.9+

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
