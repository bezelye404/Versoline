#!/bin/bash
set -euo pipefail

# Memory benchmark: builds Versoline, opens N articles in the reader one after another on a throw-away copy of the
# library, and prints the app's memory footprint after each step.
# Usage: scripts/benchmark.sh [Release|Debug] [articles] [seconds per article] [both|list|article]
#        (default: Release 12 3 both; "list" only switches the list, "article" only opens the article)
#
# Release is what users run, so it is the default. The numbers include network time: each article is fetched and
# extracted for real. Run it a few times and compare medians, not single runs.

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Built outside the project folder: when the project sits on the Desktop or in Documents, macOS asks for access to
# those folders each time a freshly built copy of the app starts from there.
DERIVED_DATA="${VERSOLINE_DERIVED_DATA:-$HOME/Library/Caches/Versoline/DerivedData}"

CONFIG="${1:-Release}"
COUNT="${2:-12}"
SECONDS_EACH="${3:-3}"
MODE="${4:-both}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "==> Building ($CONFIG)..."
xcodegen generate >/dev/null
xcodebuild -project Versoline.xcodeproj -scheme Versoline -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" -quiet build

APP="$DERIVED_DATA/Build/Products/$CONFIG/Versoline.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
BINARY="$(pwd)/$APP/Contents/MacOS/Versoline"
RESULT="$HOME/Library/Containers/$BUNDLE_ID/Data/tmp/benchmark.json"

if pgrep -f "$BINARY" >/dev/null; then
  echo "==> Quitting the running copy of this build..."
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do pgrep -f "$BINARY" >/dev/null || break; sleep 0.25; done
  pkill -f "$BINARY" 2>/dev/null || true
fi

# A Release build has its own library, usually empty on a development Mac: give it a copy of one to read.
# Defaults to the library of the Debug "Versoline Dev" app; set BENCHMARK_LIBRARY to use another data.json.
LIBRARY="${BENCHMARK_LIBRARY:-$HOME/Library/Containers/com.bezelye.Versoline.dev/Data/Library/Application Support/Versoline/data.json}"
TMP_DIR="$HOME/Library/Containers/$BUNDLE_ID/Data/tmp"
mkdir -p "$TMP_DIR"
if [ -f "$LIBRARY" ]; then cp "$LIBRARY" "$TMP_DIR/benchmark-library.json"; else rm -f "$TMP_DIR/benchmark-library.json"; fi

rm -f "$RESULT"
echo "==> Running ($COUNT articles, ${SECONDS_EACH}s each; the app quits when done)..."
open -n -W "$APP" --args --benchmark "--benchmark-count=$COUNT" "--benchmark-seconds=$SECONDS_EACH" "--benchmark-mode=$MODE" ${BENCHMARK_FLAGS:-}

[ -f "$RESULT" ] || { echo "No result file at $RESULT" >&2; exit 1; }
python3 - "$RESULT" "$CONFIG" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
print(f"\n{sys.argv[2]} build: {r['feeds']} feeds, {r['items']} items, {r['articles']} articles opened")
print(f"{'step':<22}{'footprint':>12}{'peak':>12}   WebKit started")
for s in r["samples"]:
    print(f"{s['label']:<22}{s['footprintMB']:>9.1f} MB{s['peakMB']:>9.1f} MB   {'yes' if s['webKitStarted'] else 'no'}")
first, last = r["samples"][0]["footprintMB"], r["samples"][-1]["footprintMB"]
print(f"\ngrowth while reading: {last - first:+.1f} MB")
PY
