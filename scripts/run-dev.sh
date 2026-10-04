#!/bin/bash
set -euo pipefail

# Builds Versoline and launches it, replacing the running copy. No DMG, no installing.
# Usage: scripts/run-dev.sh [Debug|Release]      (default: Debug)
#
# The app is built into build/DerivedData (ignored by git), so repeated runs are incremental.

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CONFIG="${1:-Debug}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "==> Generating project..."
xcodegen generate >/dev/null

echo "==> Building ($CONFIG)..."
xcodebuild -project Versoline.xcodeproj -scheme Versoline -configuration "$CONFIG" \
  -derivedDataPath build/DerivedData -quiet build

APP="build/DerivedData/Build/Products/$CONFIG/Versoline.app"
[ -d "$APP" ] || { echo "Build output not found: $APP" >&2; exit 1; }

if pgrep -x Versoline >/dev/null; then
  echo "==> Quitting the running copy..."
  osascript -e 'tell application "Versoline" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do pgrep -x Versoline >/dev/null || break; sleep 0.25; done
  pkill -x Versoline 2>/dev/null || true
fi

echo "==> Launching $APP"
open "$APP"
