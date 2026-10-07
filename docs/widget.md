# Widget

The widget shows the unread count and the newest headlines (top stories first). It is a WidgetKit extension
(`Widget/`) that never uses the network and never reads the library.

## How data gets there

1. The app builds a small snapshot (`WidgetSnapshot`: unread count, up to 8 headlines, the app's palette name) and writes
   it as one JSON file, `widget-snapshot.json`, into the app group container (`group.com.bezelye.Versoline`, or `.dev`).
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

## Signing

The app group entitlement needs a provisioning profile in Xcode's own signing, so `scripts/sign-app-groups.sh` adds it after
the build (the scripts that build for people run it). A plain `xcodebuild` build has no group access: the app works, the
widget stays empty.
