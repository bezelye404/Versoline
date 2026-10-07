#!/bin/bash
set -euo pipefail

# Builds Versoline and launches it, replacing the previous run of the same build. No DMG, no installing.
# Usage: scripts/run-dev.sh [Debug|Release]      (default: Debug)
#
# Debug is "Versoline Dev" (bundle id com.bezelye.Versoline.dev): a separate app with its own sandbox
# container and settings, so it never touches your real library and can run next to the installed
# Versoline. Release uses the real identity and therefore the real data.
#
# The app is built into ~/Library/Caches/Versoline/DerivedData (VERSOLINE_DERIVED_DATA overrides it), so repeated
# runs are incremental.

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Built outside the project folder: when the project sits on the Desktop or in Documents, macOS asks for access to
# those folders each time a freshly built copy of the app starts from there.
DERIVED_DATA="${VERSOLINE_DERIVED_DATA:-$HOME/Library/Caches/Versoline/DerivedData}"

CONFIG="${1:-Debug}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "==> Generating project..."
xcodegen generate >/dev/null

echo "==> Building ($CONFIG)..."
xcodebuild -project Versoline.xcodeproj -scheme Versoline -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" -quiet build

APP="$DERIVED_DATA/Build/Products/$CONFIG/Versoline.app"
[ -d "$APP" ] || { echo "Build output not found: $APP" >&2; exit 1; }
scripts/sign-app-groups.sh "$APP"

if [ "$CONFIG" = "Debug" ]; then BUNDLE_ID="com.bezelye.Versoline.dev"; else BUNDLE_ID="com.bezelye.Versoline"; fi
BINARY="$(pwd)/$APP/Contents/MacOS/Versoline"

if pgrep -f "$BINARY" >/dev/null; then
  echo "==> Quitting the previous run ($BUNDLE_ID)..."
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do pgrep -f "$BINARY" >/dev/null || break; sleep 0.25; done
  pkill -f "$BINARY" 2>/dev/null || true   # only the copy built here, never another Versoline
fi

echo "==> Launching $APP ($BUNDLE_ID)"
open "$APP"
