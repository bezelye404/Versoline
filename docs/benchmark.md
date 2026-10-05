# Memory benchmark

`scripts/benchmark.sh` measures how much memory Versoline holds while reading. It builds the app, starts it with
`--benchmark`, opens articles one after another and prints the app's memory footprint (the number Activity Monitor's
"Memory" column and `footprint` report) after each step. It runs on a throw-away copy of a library, so read and bookmark
state are never changed, and the feed refresh is left out so network timing does not move the numbers.

```bash
scripts/benchmark.sh                          # Release, 12 articles, 3 s each
scripts/benchmark.sh Release 36 2 mark-only   # config, articles, seconds per article, mode
BENCHMARK_LIBRARY=/path/to/data.json scripts/benchmark.sh
```

Modes: `both` (switch to the article's feed and open it), `list`, `article`, `mark-only` (mark read without showing it)
and `none` (a control: nothing happens, the footprint must stay flat).

A Release build has its own, usually empty, library; the script copies the library of the "Versoline Dev" app (or
`BENCHMARK_LIBRARY`) next to it. Extra launch arguments: `--benchmark-refresh` (include the refresh), `--benchmark-hold=N`
(keep the app open N seconds afterwards so `footprint -p <pid>` or `heap <pid>` can be run on it).

## Reference numbers (Release, 43 feeds, 1,662 items, Apple Silicon, October 2026)

| | footprint |
|---|---|
| Idle after launch, no refresh | 46 MB |
| Idle after the first refresh | 67 MB (the refresh leaves about 20 MB resident) |
| Control (`none`, 36 steps) | flat (+0.0 to +0.4 MB) |
| Opening 12 articles (`both`) | 67 → 92 MB |
| Opening 100 articles (`both`) | 81 → 203 MB, no plateau |

WebKit's helper processes are never started by reading (the "WebKit started" column stays `no`), except for the few
articles that fall back to the web view.

## What is known about the growth while reading

About 1 MB per article stays resident and does not level off. Each of these was ruled out by switching it off and
repeating the run: article images, drawing the article, fetching and extracting the page, and writing the library to disk.
Switching only the list (`list`, 100 steps) levels off at +9 MB. Marking items read without showing them
(`mark-only`) reproduces most of the growth, so it is tied to the read-state update path and what redraws because of it,
not to the reader. The memory is live in the heap rather than leaked (`leaks` finds 52 KB), most of the live growth is
CoreGraphics glyph bitmaps drawn by SwiftUI's software text path, and the rest is heap fragmentation that
`malloc_zone_pressure_relief` does not return. Single runs vary by tens of megabytes; compare medians of several runs.
The next step is Instruments (Allocations, "Persistent" bytes by call stack) on a Debug build launched with
`--benchmark --benchmark-mode=mark-only --benchmark-count=36 --benchmark-hold=60`.
