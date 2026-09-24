# Versoline v0.3.0

> **Welcome to Versoline!**  
> Starting with version `0.3.0`, **easyRSS** has officially transitioned to its new name: **Versoline** (*A private RSS reader for Mac*).

---

### 🌟 What's New in v0.3.0

- **Brand & Identity:** Complete transition to Versoline across all UI elements, menu bar status popover, dock icon, and internal system identifiers.
- **Automatic Non-Destructive Data Migration:**
  - Upgrading users do not need to manually export or re-import feeds!
  - Upon first launch, Versoline automatically detects and clones existing data (subscriptions, saved articles, offline podcast episodes, and cached favicons) from `~/Library/Application Support/EasyRSS` into the new `~/Library/Application Support/Versoline` directory.
  - Your legacy `EasyRSS` files are left intact as an archival safeguard.
- **Unit Test Suite:** Introduced automated test suite (`VersolineTests`) ensuring rock-solid migration and data recovery.
- **Optimized Packaging:** Clean, standardized disk image distribution (`Versoline-0.3.0.dmg`).

---

### 🛡️ Core Highlights

- **Zero Third-Party Dependencies:** 100% native Swift 6 and SwiftUI built exclusively on Apple system frameworks (`WebKit`, `AVFoundation`, `MediaPlayer`, `Network`, `Charts`).
- **All-in-One Feed Hub:** Standard RSS 2.0 / Atom feeds, YouTube channels/videos, Reddit subreddits, and podcasts in one distraction-free interface.
- **Integrated Podcast Studio:** Streaming, sleep timer, speed control (0.5x–2.0x), offline `.mp3` episode manager, and timestamp seeking.
- **10 Matte Color Palettes:** Slate, Sepia, Sage, Dusk, Monochrome, Nordic, Espresso, Matcha, Bordeaux, and Solarized with full light and dark mode parity.
- **Focus Features:** Distraction-free Reader Mode, native Bionic Reading, Smart Streams (Quick Reads <3m / Deep Reads >7m), and Vim-style single-key navigation (<kbd>J</kbd>/<kbd>K</kbd>/<kbd>M</kbd>/<kbd>S</kbd>/<kbd>O</kbd>).
- **100% Local & Private:** No accounts, no telemetry, no tracking servers.

---

### 📥 Installation & Gatekeeper Note

1. Download **`Versoline-0.3.0.dmg`** below and drag `Versoline.app` into your `/Applications` folder.
2. **First-Launch Note:** As Versoline is an independent open-source application with ad-hoc signing (no paid Apple Developer certificate), macOS Gatekeeper may prompt upon first open:
   - **Right-click** (or Control-click) `Versoline.app` in `/Applications` and select **Open**, or run:
     ```bash
     xattr -cr /Applications/Versoline.app
     ```
3. Once you confirm your feeds have loaded in Versoline, you may safely delete the old `EasyRSS.app`.

---

**Full Changelog:** https://github.com/bezelye404/Versoline/compare/v0.2.4...v0.3.0
