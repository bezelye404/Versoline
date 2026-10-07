# Widget

The widget shows the unread count and the newest headlines (top stories first). It is a WidgetKit extension
(`Widget/`) that never uses the network and never reads the library.

## How data gets there

1. The app builds a small snapshot (`WidgetSnapshot`: unread count, up to 8 headlines, the app's palette name) and writes
   it as one JSON file, `widget-snapshot.json`, into `~/Library/Application Support/Versoline Widget` (`Versoline Dev Widget` for the dev build).
2. The widget reads that file when WidgetKit asks for a timeline. Its timeline policy is `.never`: it does not wake up
   on its own.
3. When the file changes, the app calls `WidgetCenter.reloadAllTimelines()`.

## When the app updates it

`ContentView` watches the unread count, the item count, the number of grouped stories, the palette and the muted keywords.
A change starts a 5 second timer; further changes restart it, so a refresh or a run of "mark as read" produces one update.
The app also updates when it loses focus and when it quits, so the widget is never left behind by the last few seconds.
A snapshot is written, and the widget redrawn, only if its content differs from the file already there. A library that
failed to load is never written (it would look like "all caught up").

Nothing runs in the background: while the app is closed the widget shows what the app last wrote.

## Cost

Measured on a library of 10,000 articles (Debug test build, so a Release build is faster):

| | |
|---|---|
| Building a snapshot | about 11 ms, two passes over the articles, no copy of them; 100 updates left the footprint unchanged (+0.05 MB) |
| Snapshot file | a few KB |
| Widget extension process | 4 to 10 MB footprint, measured with `footprint` on the running extension (one placed widget) |

## Colors

The widget can follow the app's palette or use any of the ten palettes (Edit Widget > Palette). The colors live in
`WidgetPalette`, a table compiled into both targets; `WidgetPaletteTests` compares it with `AppColorPalette`, so a change to
a palette in the app fails the test until the table is updated.

## Why a folder and not an app group

The app and the widget are separate sandboxed processes, so they need a place both can reach. An app group is the usual
answer, but the app is signed ad hoc, and macOS then shows "wants to access data from other apps" every time the app
opens a group container. Instead the app has a sandbox temporary-exception entitlement to write one folder in the user's
real Library (`com.apple.security.temporary-exception.files.home-relative-path.read-write`) and the widget one to read it
(`...read-only`). The folder's name comes from `WIDGET_DATA_DIR` in `project.yml`, so the dev build uses its own. The
exception grants access to that one folder only, and it needs no provisioning profile, so a plain `xcodebuild` build
works. If the app is ever signed with a Developer ID, an app group becomes silent and is the cleaner choice again.
