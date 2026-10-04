# Changelog

All notable changes to **Versoline** (formerly **easyRSS**) are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Security
- **Nearby sync now requires pairing.** The old local-network sync accepted every invitation from any device speaking the protocol, so anyone nearby could add or delete feeds. Devices must now be paired first: both Macs show the same six-digit code (derived from both devices' keys with a commit-reveal step, so a man in the middle cannot make the codes match) and you confirm it on each. Paired devices re-authenticate with a signed challenge on every connection, sessions require encryption, unauthenticated connections time out, and every incoming event is range-checked (only `http`/`https` feed URLs, size limits).

### Changed (sync)
- **Deletions and edits now propagate** between paired Macs, even if one was offline. Feeds and folders carry a last-edit time and deletions are remembered for 90 days ("last writer wins"): deleting, renaming a folder, moving a feed, pinning, and re-adding a deleted feed all converge on every Mac, whichever order they sync in (covered by randomized convergence tests). Existing feeds have no edit time yet, so any deletion or later edit beats them. A Mac offline for more than 90 days can bring back something deleted meanwhile. Bookmark removal is still union-only.

### UI and UX
- **Calmer sidebar:** four everyday lists (Unread, Today, Bookmarks, All), one collapsible Media group that only appears when there is media, monochrome icons, and a count only on Unread. Folder management and Reading Insights moved to the menu bar.
- **Native toolbars:** the window toolbar is just Refresh and Add (a split button); OPML, folders, console and shortcuts are menu bar commands (File, View, Help). The article controls are in the real window toolbar: reading mode, an "Aa" appearance popover, bookmark, read, and one More menu.
- **Lighter list rows:** one quiet meta line (source, time, media) instead of author icon and capsules, and a one-line summary.
- **Native search** (⌘F) in the toolbar replaces the in-list search bar.
- **Faster navigation:** ⌘K command palette to jump to any list, folder or feed or run any command, and Focus Mode (⇧⌘F) to read without the sidebar and list.
- **Settings:** the theme grid became one row of colour swatches, switches carry their description in the same row, and the window follows the app theme. The Add Feed sheet no longer repeats its own tabs as cards.
- **Welcome screen** with three clear first steps while the library is empty.
- **Motion:** SF Symbol bounce on bookmark and read toggles and numeric transitions, both disabled under Reduce Motion.

### Memory and speed
- Freed heap pages are handed back to the system after launch, after a refresh and after an OPML import (idle footprint with a 3,500-article library: 83 MB to 70 MB in a Release build).
- WebKit is no longer started at launch just to clear its caches (it started a network process, about 6 MB, before any page was opened).
- The article cache scan runs a few seconds after launch instead of during it.
- New setting: play YouTube videos in the browser instead of the built-in player, which avoids the roughly 100 MB WebKit page.
- Debug builds are a separate app, "Versoline Dev" (`com.bezelye.Versoline.dev`), with its own data.

### Removed
- **iCloud Drive sync.** It needed a sandbox exception for the iCloud Drive folder and could clear local bookmarks when feeds changed. It may return later as a new design. Nothing is deleted from an existing iCloud Drive folder.

### Fixed
- **Library overwrite protection**: an unreadable `data.json` is now copied to `data.json.corrupt-<date>`, saving is blocked for that session, and a startup alert explains how to restore. Previously the next save could replace the library with an empty one.
- **Quick Reads / Deep Reads**: reading time is now computed once from the full article body when a feed is parsed (`readingMinutes`). Article bodies are not kept on items, so every article used to count as one minute and Deep Reads stayed empty.
- **Synced changes are saved**: read states, bookmarks, and feeds received from another device were applied in memory but not persisted.
- **Reddit**: `old.reddit.com` links produced a broken feed URL.
- **Reduce Motion**: all app animations now follow the macOS setting (short fade instead of springs and bounces).
- **Background activity**: feeds are refreshed only while the app is in front (once on activation, then every 30 minutes), no longer while it is in the background.
- **Legacy data**: the cache cleanup no longer touches the old `EasyRSS` folder, so it stays exactly as it was.
- **Factory reset** now also forgets the sync identity and paired devices.

### Added
- `data.json.bak`: the last successfully loaded library is kept as a backup.
- Copy/Export in the console redacts URL query strings, URL credentials, and the macOS account name.
- 262 previously untranslated Turkish UI strings, plus `scripts/check-localization.py` (also run in CI).
- GitHub Actions workflow that runs the test suite on every pull request.
- Unit tests (146): parsing, merging, persistence, OPML, cleaning, localization, memory budget, pairing and sync.

### Changed
- `FeedStore` is split into focused files under `Sources/Services/FeedStore/`; podcast/video/quick-read/deep-read queries now share one `ItemStream` implementation. Large view files were split into one type per file.
- Running the test suite no longer touches the real app container.
- The app now declares the local-network permission (`NSLocalNetworkUsageDescription`, Bonjour service `_versoline-sync`) and the `network.server` sandbox entitlement, both needed only for nearby sync.

---

## [0.3.0] - 2026-09-25

### Changed
- **Rebrand to Versoline**: Renamed product and user interface from easyRSS to Versoline (*formerly easyRSS*).
- **Bundle Identifier**: Updated application bundle identifier to `com.bezelye.Versoline`.
- **Target & Scheme**: Migrated build target and Xcode schemes to `Versoline`.
- **User-Agent**: Updated network client identifiers to `Versoline/1.0`.

### Added
- **Non-Destructive Data Migration (`LegacyMigration`)**: Automatic import of legacy data (subscriptions, articles, downloaded podcast episodes, and cached favicons) from `~/Library/Application Support/EasyRSS` to `~/Library/Application Support/Versoline` upon first launch without deleting legacy files.
- **Unit Test Suite**: Added `VersolineTests` target with automated tests covering all migration and edge-case recovery scenarios.
- **Release Packaging**: Added `scripts/build-dmg.sh` for automated compilation and DMG generation.
- **Community Standards**: Added comprehensive `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, GitHub issue templates, and pull request template.

---

## [0.2.4] - 2026-09-19

### Added
- **Deep Memory Compaction**: Added explicit memory pressure handler (`VersolineDeepCompactMemory`) to aggressively purge transient WebKit and network buffers.
- **Seamless Video Reparenting**: Enhanced YouTube video player container reparenting for smooth transitions between inline and fullscreen views without page reloads.

### Improved
- **Theme Engine**: Refactored static `AppTheme` colors to dynamic palette properties.
- **Curated Catalog Memory**: Eviction of catalog memory upon view dismissal.

---

## [0.2.2] - 2026-09-14

### Added
- **10 Matte Color Palettes**: Introduced Slate, Sepia, Sage, Dusk, Monochrome, Nordic, Espresso, Matcha, Bordeaux, and Solarized palettes with light and dark mode synchronization.
- **Theme Grid Picker**: Redesigned theme selection interface with interactive palette swatches.

### Improved
- **Sync Merging Engine**: Added scoped delta synchronization and fine-grained merge resolution for iCloud Drive.
- **Performance**: Cached date formatters and precomputed unread counters to eliminate main-thread stuttering during large feed updates.

---

> **Note on 0.2.3:** a `EasyRSS-0.2.3.dmg` build existed but was never tagged or documented, and no separate 0.2.3 entry can be reconstructed from git history. Changes from 2026-09-14 to 2026-09-19 appear under 0.2.2 and 0.2.4.

## [0.2.1] - 2026-09-08

### Improved
- **Cache Quotas**: Strict 30MB disk quota enforcement for downsampled image thumbnails.
- **Reader Cache Cleanup**: Automated periodic cleanup for articles older than 30 days.
- **Scroll Responsiveness**: Immediate task cancellation for off-screen image requests.

---

## [0.2.0] - 2026-09-07

### Added
- **Smart Streams**: Filter articles into Quick Reads (< 3 min) and Deep Reads (> 7 min) based on estimated word counts.
- **Smart Folders**: Rule-based categorization for grouping matching subscription articles.
- **Curated Feed Catalog**: Browse and discover quality RSS feeds by topic directly within the app.
- **OPML 2.0 Support**: Import and export subscription feeds with folder hierarchy preservation.

---

## [0.1.0] - 2026-09-06

### Added
- Initial public release of the native macOS RSS reader built with Swift 6 and SwiftUI.
- RSS 2.0 and Atom XML feed parsing.
- Streaming podcast playback with speed controls, sleep timer, and offline `.mp3` episode downloading.
- Distraction-free Reader Mode with readability extraction.
- Offline-first local storage residing exclusively on the user's Mac.
