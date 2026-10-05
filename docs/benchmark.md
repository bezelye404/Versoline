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
| Idle after launch, no refresh | 48 MB |
| Idle after the first refresh | about 67 MB (the refresh leaves about 20 MB resident) |
| Control (`none`, 36 steps) | flat |
| Opening 100 articles (`both`) | 48 → 74 MB (before the fix below: 81 → 203 MB, no plateau) |
| Marking 36 items read (`mark-only`) | +5 MB (before the fix: +50 MB) |

WebKit's helper processes are never started by reading (the "WebKit started" column stays `no`), except for the few
articles that fall back to the web view.

## The reading leak: `.contentTransition(.numericText())`

Reading used to grow the footprint by about 1.4 MB per article without levelling off. It was found by switching things
off and repeating the run: article images, drawing the article, fetching, extracting and saving were all ruled out, and
`mark-only` (no article shown) reproduced it. Skipping only the unread-count updates in the read-state change took the
growth from +50 MB to +5 MB, and the counts feed the sidebar. Every count in the sidebar had
`.contentTransition(.numericText())`: each change drew intermediate frames of the morphing digits through CoreGraphics'
software text path, and its glyph bitmap cache kept them (`heap` showed it as `CGGlyphBuilderLockBitmaps`; `leaks` found
nothing, because the cache is reachable). Removing the transition fixed it: three runs of `mark-only` gave +4.8, +5.5
and +4.9 MB. `NoNumericTextTransitionTests` keeps it from coming back.

## Tips for measuring

- Compare several runs; single runs can differ by tens of megabytes when something else on the Mac steals focus. The
  benchmark disables the focus-triggered memory purge so the app's state does not depend on which window is in front.
- `BENCHMARK_FLAGS="--benchmark-..."` passes extra launch arguments. `heap <pid>` and `footprint -p <pid>` work on a
  run started with `--benchmark-hold=60`; start it with `MallocStackLogging=1` to get allocation sites in `heap` output.
