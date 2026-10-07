# Versoline: RSS reader and podcast player for macOS

Versoline is a native macOS app for reading RSS and Atom feeds, listening to podcasts and following YouTube channels and Reddit communities. It is written in Swift and SwiftUI, uses only Apple's frameworks, has no accounts and no analytics, and keeps its data on your Mac.

[![Platform: macOS 15+](https://img.shields.io/badge/Platform-macOS%2015%2B-black.svg)](https://www.apple.com/macos)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Third-party dependencies: 0](https://img.shields.io/badge/Dependencies-0-success.svg)](#privacy-and-data)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/bezelye404/Versoline?color=6366f1)](https://github.com/bezelye404/Versoline/releases/latest)

**[Download Versoline for macOS](https://github.com/bezelye404/Versoline/releases/latest)** · requires macOS 15 (Sequoia) or later · Apple silicon and Intel

Or with Homebrew:

```bash
brew install --cask bezelye404/versoline/versoline
```

---

## Features

### Feeds and sources

- **RSS 2.0 and Atom** feeds, parsed with a streaming parser. Very large feeds are read only as far as the newest items.
- **Add by site address.** Paste a site or an article link and Versoline looks for the feed the page advertises, then for the usual feed paths. `feed://` links and OPML files open directly in the app.
- **YouTube channels and playlists** (paste a handle, a channel link or a video link) and **Reddit** subreddits and users with sort and time filters.
- **OPML import and export** with folders, and a catalog of curated feeds in English and Turkish.
- **Feed Health** lists feeds that return errors or have not published for months. Feeds that keep failing are retried less often during automatic refreshes.
- Refreshes run while the app is in front: once when it becomes active, then every 30 minutes.

### Reading

- **Reader view** built with native SwiftUI text, without a web view: headings, paragraphs, lists, quotes, code, tables and images with captions. Page furniture such as menus, share bars, related links and ads is removed. The web page is one click away.
- **Typography and themes:** system, serif, sans-serif and monospaced fonts, font size and line height, ten colour palettes, Bionic Reading.
- **Translate an article on your Mac** with Apple's Translation framework when its language differs from yours.
- **Find in Article** (⌥⌘F), **highlights and notes** on paragraphs, and **continue where you left off** in long articles.
- **Text to speech** with the system voices, and **quote cards** (an image of selected text to paste or share).

### Keeping up

- **Same story, once.** When several of your feeds report the same news, lists show one row with the number of sources and the article offers the other versions. A **Top Stories** list shows what three or more of your feeds are covering. Grouping is computed on your Mac from titles and summaries, and can be switched off.
- **Smart streams** by topic and by reading time, **muted keywords**, and **rules** that mark new articles read or bookmark them.
- **Mark older articles as read** by hand or automatically, so the Unread list stays about what is new.
- **Bookmarks** (also searchable in Spotlight, if you turn that on), a Highlights list, and an unread count on the Dock icon (optional).
- **Calendar:** a month view that shows how many articles arrived on each day and which days have bookmarks; pick a day to see its articles. It covers the articles still stored on your Mac.
- **Shortcuts actions** to refresh the feeds and read the unread count.
- **Permissions & Access reset** (Settings > Storage): turns off every optional integration (Dock badge, menu bar icon, Spotlight, widget data, nearby sync) and forgets paired Macs in one step.
- **Widget** (small, medium and large) with the unread count and the newest headlines, top stories first. It follows the app's colour palette, or you can pick one of the ten palettes for each widget. It updates when the app does and uses no network.

### Podcasts and video

- Search the Apple Podcasts directory, stream or download episodes, playback speeds from 0.75x to 2x, a sleep timer, a queue and chapter timestamps.
- Videos play in an embedded player, or open in your browser if you prefer (a setting; the embedded player loads a web page and uses more memory while it is open).

### Library

- **Backup and restore** of the whole library and your preferences as one file.
- **Command palette** (⌘K) to jump to any list, folder or feed, and **Focus Mode** (⇧⌘F) to read without the sidebar.
- Optional **nearby sync** between your own Macs (see below).
- Interface in English and Turkish, selectable in Settings > General.

---

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| J / K | Next / previous article |
| M | Toggle read |
| S | Toggle bookmark |
| O | Open the article in your browser |
| Space / ⇧ Space | Page down / page up |
| ⌘R | Refresh all feeds |
| ⌘K | Command palette |
| ⌥⌘F | Find in the article |
| ⇧⌘F | Focus Mode |
| ? | Show all shortcuts |

---

## Privacy and data

Versoline has no account system, no analytics and no crash reporting. Everything it stores lives in `~/Library/Application Support/Versoline`, inside the app's sandbox container. The one exception is the widget's snapshot: a single small file (the unread count and a few headlines) in `~/Library/Application Support/Versoline Widget`, outside the sandbox container, because a widget cannot read the app's own folder.

The network requests it makes are all made from your Mac, and each has a reason:

| Request | To whom | When |
| --- | --- | --- |
| Feed updates | The sites whose feeds you follow | On refresh |
| Article pages | The site of an article | When you open it in the reader or the web view |
| Site icons | The site itself (`/favicon.ico` or the icon its home page names) | When a feed is shown |
| Article images, YouTube thumbnails | Their publishers | When shown |
| Podcast search | Apple's iTunes Search API | When you search |
| Feed discovery, YouTube and Reddit lookups | The site you typed | When you add a feed |
| Curated feed catalog | This repository on GitHub | When Add Feed is opened |
| Translation language packs | Apple, through macOS | The first time a language pair is used |

Translation itself, story grouping, Spotlight indexing, highlights and notes all run on your Mac. Fetched feeds, articles and images are only ever requested over `http` or `https`.

**Nearby sync** is off by default. When you turn it on, your own Macs can exchange feeds, folders, bookmarks, read state and preferences directly over the local network. Devices must be paired first: both Macs show the same six-digit code and you confirm that they match. The connection is encrypted and unpaired devices are refused. No server is involved, and macOS asks for local network permission only for this feature.

**Logs** stay in memory (at most 200 entries). When you copy or export them, query strings, credentials in URLs and your macOS account name are removed first.

---

## Install

**With Homebrew:**

```bash
brew install --cask bezelye404/versoline/versoline
```

The cask comes from the [homebrew-versoline](https://github.com/bezelye404/homebrew-versoline) tap and clears the quarantine flag, so the Gatekeeper note below does not apply. Update with `brew upgrade --cask versoline`.

**Or by hand:**

1. Download the `.dmg` from the [latest release](https://github.com/bezelye404/Versoline/releases/latest).
2. Open it and drag **Versoline** to **Applications**.

Versoline is signed ad hoc, without a paid Apple Developer certificate, so macOS may say the developer cannot be verified the first time. Right-click the app in Applications and choose **Open**, or run:

```bash
xattr -cr /Applications/Versoline.app
```

If you used the earlier name **easyRSS**, Versoline imports its data on first launch and leaves the old folder untouched.

---

## Build from source

You need macOS 15 or later, Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/bezelye404/Versoline.git
cd Versoline
xcodegen generate
xcodebuild -project Versoline.xcodeproj -scheme Versoline -configuration Release build
```

Run the tests and the localization check:

```bash
xcodebuild test -project Versoline.xcodeproj -scheme Versoline -destination 'platform=macOS'
python3 scripts/check-localization.py
```

The widget reads its data from a small folder the app writes to; both are allowed to reach it through a sandbox entitlement, so a plain `xcodebuild` build works the same as a release. See [docs/widget.md](docs/widget.md).

`scripts/run-dev.sh` builds and launches a separate "Versoline Dev" app with its own data, and `scripts/benchmark.sh` measures memory use while reading (see [docs/benchmark.md](docs/benchmark.md)). `scripts/build-dmg.sh` packages a release; the steps are in [docs/RELEASING.md](docs/RELEASING.md).

---

## Frequently asked questions

**Does Versoline need an account or an internet connection?** No account. It needs the network to fetch feeds and articles; articles and episodes you have already loaded or downloaded stay available offline.

**Where is my data, and how do I move it to another Mac?** In `~/Library/Application Support/Versoline`. Use **File > Export Backup** and **Restore Backup**, export your subscriptions as OPML, or turn on nearby sync between your own Macs.

**How do I import my subscriptions from another reader?** Export an OPML file from it and choose **File > Import OPML**, or open the file with Versoline.

**Can I follow a site that has no visible RSS link?** Paste the site address in Add Feed. If the site advertises a feed, or uses a common feed path, Versoline finds it.

**Which languages does the app support?** English and Turkish. Choose one in Settings > General, or follow the system.

**Why is the widget empty?** It shows what the app last wrote, so open Versoline once.

---

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first: the project keeps to Apple's frameworks only, makes no network requests except to the sites a user reads, stores nothing outside the app's folder, and keeps memory use low.

## Credits

Some of the curated feed lists come from [joshuawalcher/rssfeeds](https://github.com/joshuawalcher/rssfeeds) and [bakinazik/rss](https://github.com/bakinazik/rss).

## License

MIT. See [LICENSE](LICENSE).
