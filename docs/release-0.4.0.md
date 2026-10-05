# Versoline 0.4.0

A new reader, fewer duplicate stories, more control over the library, and a fix for memory growth while reading.

## What is new

- **Native reader.** Articles are drawn with SwiftUI instead of a web view, so reading no longer starts WebKit's helper processes. Menus, share bars, related links and ads are removed from the page; the web view is still one click away.
- **Reader tools:** translate an article on your Mac, highlights and notes on paragraphs, Find in Article (⌥⌘F), continue where you left off, and tables.
- **The same story, once.** When several of your feeds report the same news, lists show one row with the number of sources, and a Top Stories list shows what three or more feeds are covering. It is computed on your Mac and can be turned off.
- **Library:** backup and restore, marking older articles as read (by hand or automatically), rules that mark new articles read or bookmark them, a command palette (⌘K) and Focus Mode (⇧⌘F).
- **Feeds:** add a feed from a site or article address, open `feed://` links and OPML files with the app, and feeds that keep failing are retried less often.
- **Optional:** bookmarks in Spotlight, an unread count on the Dock icon, and Shortcuts actions to refresh the feeds and read the unread count.
- **Nearby sync** between your own Macs now requires pairing with a confirmed six-digit code, and deletions and edits propagate.

## Fixed

- Memory grew by about 1 MB for every article read, without limit. Opening 100 articles took the app from 81 MB to 203 MB; it now goes from 48 MB to 74 MB and stays there.
- Podcast downloads could fail or save an error page as an episode.
- Feed Health reported working feeds as broken when their server rejected HEAD requests.
- Several duplicate-identity and library-protection problems (see the [changelog](../CHANGELOG.md)).

## Privacy

- Site icons are now fetched from the site itself. Earlier versions asked an icon service for them by host name, which told that service which sites you follow.
- Feeds, article pages and images are only fetched over `http` and `https`.

## Notes

- Requires macOS 15 (Sequoia) or later. Apple silicon and Intel.
- The app is signed ad hoc. If macOS says the developer cannot be verified, right-click the app and choose **Open**, or run `xattr -cr /Applications/Versoline.app`.
- Versoline imports its data from the earlier easyRSS folder on first launch and leaves that folder untouched.
