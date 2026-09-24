# Changelog

All notable changes to **Versoline** (formerly **easyRSS**) are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
