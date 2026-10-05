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
- **Settings in five tabs** (General, Reader, Feeds, Sync, Storage): muted keywords and feed health share the Feeds tab, and the single-key navigation switch moved into General (the cheat sheet is in the Help menu).
- Podcast episodes no longer show the Reader/Web switch; the episode page is the player.
- **Welcome screen** with three clear first steps while the library is empty.
- **Motion:** SF Symbol bounce on bookmark and read toggles and numeric transitions, both disabled under Reduce Motion.

### Reader
- **Better article extraction:** the page is parsed as a DOM and scored like Readability (paragraph density, link density, class and id hints, JSON-LD `articleBody` as a fallback) instead of regex-matching the biggest `<article>`. Content that Next.js streams inside hidden placeholders is now recognised, and "Fetch Full Article" says so when a page yields nothing instead of doing nothing.
- **Native reader:** articles are parsed into blocks (headings, paragraphs, lists, quotes, code, images with captions) and drawn with plain SwiftUI, so reading no longer starts WebKit's helper processes (about 50 MB and three processes per reading session). Links, bold, italic and inline code are kept; Bionic Reading, font, line height and the colour themes work as before. Page furniture such as breadcrumbs, "follow us" lines, related-post lists, navigation, sidebars and footers is dropped, and images are downsampled and loaded lazily. Code blocks are plain monospaced (no syntax colours). The web view is still used for the "Web" mode and as a fallback when nothing readable is found.

### Library
- **Find bookmarks in Spotlight:** Settings > General > "Find Bookmarks in Spotlight" (off by default) adds the title, summary and link of bookmarked articles to Spotlight on your Mac; choosing a result opens the article. Versoline keeps nothing extra and sends nothing.
- **Rules for new articles:** Settings > Feeds > Rules: in one feed or in all of them, articles whose title or summary contains a word are marked as read or bookmarked when a refresh brings them (case, accents and the Turkish dotless i do not matter). "Apply to Existing Articles" runs the rules over what is already there. Muted keywords still hide; rules never hide or delete anything.
- **Backup and restore:** File > Export Backup writes one JSON file with your subscriptions, folders, articles with their read and bookmark state, and your reading preferences; File > Restore Backup replaces the library with it after showing what is in it. The library being replaced is kept as `data.json.before-restore`. Article bodies are not included; they are fetched again when opened.
- **Taming a long Unread list:** File > Mark Older Articles as Read (a day, 3 days, a week, 2 weeks; it shows how many first), a command palette entry, and Settings > General > "Mark Old Unread as Read" to do it automatically after a refresh. Bookmarks and articles without a date are left alone.

### Translation
- **Translate an article on your Mac:** when an article is in a language other than yours, the reader toolbar shows "Translate from English" (or the language it recognised). It uses Apple's Translation framework, so the text is translated on the device, the system downloads a language pack the first time, and nothing about the article is sent to a server or stored. "Show Original" switches back. Links and bold or italic text inside translated paragraphs are lost; code blocks and images stay as they are.

### Feeds
- **Open feed links and OPML files with Versoline:** a `feed://` (or `feeds://`) link from a web page or mail opens Add Feed with the address filled in, and an `.opml` file opened from Finder asks whether to import its subscriptions. They go to the window that is already open.
- **The same story, once:** when several of your feeds report the same news, lists that mix feeds (Unread, Today, All Articles, the smart streams) show one row with "7 sources", and a "Same story in N other feeds" menu in the article opens the other versions. Reading the lead marks the other versions read. A new **Top Stories** list shows what three or more of your feeds are telling right now. It is found on your Mac from titles and summaries (word stems, TF-IDF, time window; no model, nothing stored or sent) and can be switched off in Settings > General ("Group the Same Story"). On a real library of 43 feeds about half of the last two days' items fell into a story.
- **Add a feed from a site address:** paste `example.com` or an article link and Versoline looks for the feed the page advertises (`<link rel="alternate">`, skipping comment feeds), then for the usual paths (`/feed`, `/rss`, the section's `index.xml`, ...). Only the address you typed and that site's own paths are contacted.
- **Articles only:** items without a real article (social posts, promos, home-page links) and duplicates are dropped; entries without a link get an identity from their guid or enclosure, so read and bookmark state no longer collides between them.

- Items that older versions left with one shared id (a whole podcast feed could show the same episode over and over in the list) get their own id on the next launch.

### Memory and speed
- **Reading no longer grows the memory without end.** The animated digits on the sidebar counts (`numericText`) kept about 1.4 MB for every count that changed: opening 100 articles took the app from 81 MB to 203 MB. Without the animation it goes from 48 MB to 74 MB and stays there. `scripts/benchmark.sh` measures this (see `docs/benchmark.md`).
- **Failing feeds back off:** a feed whose address is gone, whose server errors or whose XML is unreadable is skipped by automatic refreshes for 30 minutes after the first failure, doubling up to a day. Being offline or timing out never counts against a feed, a refresh you start by hand tries everything, and a restart clears the waiting times.
- Freed heap pages are handed back to the system after launch, after a refresh and after an OPML import (idle footprint with a 3,500-article library: 83 MB to 70 MB in a Release build).
- WebKit is no longer started at launch just to clear its caches (it started a network process, about 6 MB, before any page was opened).
- The article cache scan runs a few seconds after launch instead of during it.
- **Big feeds are no longer parsed to the end.** The parser keeps only the newest items it needs and stops once a newest-first feed has gone past them, and it reads the XML as a stream. A podcast feed with 2,759 episodes (5.4 MB) went from 0.67 s and about 19 MB of extra memory to 0.15 s and 6 MB per refresh; the 43 feeds of a real library gave identical results. Adding a feed or importing OPML now keeps the newest items of oldest-first feeds, not the oldest.
- The in-app YouTube player has pastel controls, a capped inline size, and frees its web page 90 seconds after pausing.
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
