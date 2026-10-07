# Changelog

All notable changes to **Versoline** (formerly **easyRSS**) are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

## [0.5.0] - 2026-10-07

### Added
- **Calendar.** A month view that shows how many articles arrived on each day, with a marker for days that have bookmarks. Pick a day to see its articles, or only its bookmarks.
- **Widget.** A Notification Center and desktop widget (small, medium and large) with the unread count and the newest headlines, top stories first. It reads one small file the app writes into its app group container; it never uses the network. It follows the app's color palette, or any of the ten palettes can be chosen per widget (Edit Widget). Tapping a headline opens the article in Versoline.
- **Language setting.** Settings > General can pin the app to English or Turkish, or follow the system.
- **Homebrew.** `brew install --cask bezelye404/versoline/versoline`, from the `homebrew-versoline` tap, which updates itself when a release is published.

### Changed
- The calendar reads the library in place and keeps only the month's results; the first version held a sorted copy of every article while it was open (about 2.5 to 8.7 MB for 10,000 articles).
- The release script signs the app and the widget again after the build to add the app group entitlement, which Xcode does not accept without a provisioning profile (`scripts/sign-app-groups.sh`).

## [0.4.1] - 2026-10-07

### Fixed
- The counts in the sidebar section headers (Smart Streams, Feeds, folders, Pinned) lined up further right than the counts in the rows below them. They now share the same right edge.

## [0.4.0] - 2026-10-05

### Added
- **Native reader.** Articles are parsed into blocks (headings, paragraphs, lists, quotes, code, tables, images with captions) and drawn with SwiftUI, so reading no longer starts WebKit's helper processes. Page extraction uses a DOM parser with Readability-style scoring and JSON-LD as a fallback; menus, share bars, related links and ads are dropped. The web view remains for Web mode and as a fallback.
- **Reader features:** translate an article on your Mac (Apple's Translation framework), highlights and notes on paragraphs with a Highlights list and Markdown export, Find in Article (⌥⌘F), continue where you left off, and tables.
- **The same story, once.** Lists that mix feeds fold the same news from several feeds into one row ("7 sources"), the article lists the other versions, and a Top Stories list shows what three or more feeds are telling. Computed on your Mac from titles and summaries; Settings > General can turn it off.
- **Library tools:** backup and restore of the library and preferences, "Mark Older Articles as Read" (by hand or automatically), rules that mark new articles read or bookmark them, a command palette (⌘K), Focus Mode (⇧⌘F), and a Welcome screen for an empty library.
- **Feeds:** add a feed from a site or article address (feed discovery), open `feed://` links and `.opml` files with the app, and automatic back-off for feeds that keep failing.
- **System integration (opt-in):** bookmarks in Spotlight, an unread count on the Dock icon, and two Shortcuts actions (Refresh Feeds, Get Unread Count).
- **Nearby sync requires pairing.** Both Macs show the same six-digit code (derived from both devices' keys with a commit-reveal step) and you confirm it on each. Paired devices re-authenticate with a signed challenge on every connection, sessions are encrypted, and incoming events are range-checked. Deletions and edits now propagate between paired Macs, even if one was offline (last writer wins, deletions remembered for 90 days).
- A separate "Versoline Dev" app for Debug builds (`com.bezelye.Versoline.dev`) with its own data, `scripts/run-dev.sh`, and `scripts/benchmark.sh` with `docs/benchmark.md` for measuring memory while reading.
- `data.json.bak` (the last library that loaded), redacted console export, a localization check (`scripts/check-localization.py`) and a GitHub Actions workflow that runs the tests on every pull request.

### Changed
- **Interface:** a calmer sidebar (Unread, Today, Bookmarks, All Articles, plus media lists when there is media), native window toolbars, lighter list rows, native search, Settings in five tabs that follow the app theme, pastel player controls, and no Reader/Web switch on podcast episodes.
- Items without a real article (social posts, promos, home-page links) and duplicates are dropped when a feed is read; entries without a link get an identity from their guid or enclosure.
- Large feeds are read only as far as the newest items needed and as a stream: a podcast feed with 2,759 episodes went from 0.67 s and about 19 MB of extra memory to 0.15 s and 6 MB per refresh.
- Adding a feed or importing OPML keeps the newest items of oldest-first feeds, not the oldest.
- `FeedStore` is split into focused files and the stream queries share one implementation.
- The in-app YouTube player has a capped inline size and frees its web page 90 seconds after pausing; a new setting plays YouTube in the browser instead (avoids about 100 MB of WebKit memory).
- Heap pages freed by a refresh or an OPML import are handed back to the system, and WebKit is no longer started at launch.

### Fixed
- **Reading no longer grows the memory without end.** The animated digits on the sidebar counts kept about 1.4 MB for every count that changed: opening 100 articles took the app from 81 MB to 203 MB. Without the animation it goes from 48 MB to 74 MB and stays there.
- Podcast downloads moved the temporary file after the system had already deleted it, saved HTTP error pages as episodes and showed no real progress.
- Feed Health called feeds broken when their server rejected HEAD requests.
- An updated content-blocker rule set is compiled again instead of the old compiled list being reused.
- Items that older versions left with one shared id (a whole podcast feed showing the same episode over and over) get their own id on launch.
- **Library overwrite protection:** an unreadable `data.json` is copied to `data.json.corrupt-<date>`, saving is blocked for the session and a startup alert explains how to restore.
- Quick Reads and Deep Reads: reading time is computed once from the full article body (every article used to count as one minute).
- Changes received from another device are saved, `old.reddit.com` links give a working feed, animations follow Reduce Motion, feeds refresh only while the app is in front, and a factory reset also forgets the sync identity, annotations, reading positions and Spotlight entries.

### Security and privacy
- **Site icons come from the site itself.** They used to be requested from an icon service by host name, which told that service every site you follow.
- Feeds, article pages, images and audio are only fetched over `http` and `https`; an OPML file or feed naming a `file:` address is refused.
- The app's identifiers, user agents and support folder are read from the bundle instead of being written out in the code.

### Removed
- **iCloud Drive sync.** It needed a sandbox exception for the iCloud Drive folder and could clear local bookmarks when feeds changed. It may return later as a new design; nothing is deleted from an existing iCloud Drive folder.

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
