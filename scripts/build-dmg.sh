#!/bin/bash
set -euo pipefail

# Versoline Release Build & DMG Packaging Script
# Zero third-party runtime dependencies. Uses XcodeGen and create-dmg/hdiutil.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

APP_NAME="Versoline"
VERSION="${1:-0.3.0}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DIST_DIR="$PROJECT_ROOT/dist"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "==> 1. Generating Xcode project via XcodeGen..."
xcodegen generate

echo "==> 2. Building Release binary..."
xcodebuild -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  build

DERIVED_PRODUCTS="$(xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" -configuration Release -showBuildSettings | awk -F ' = ' '/BUILT_PRODUCTS_DIR/ {print $2}' | head -n 1)"
BUILT_APP="${DERIVED_PRODUCTS}/${APP_NAME}.app"

if [ ! -d "$BUILT_APP" ]; then
    echo "Error: Built application not found at $BUILT_APP" >&2
    exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$DMG_NAME"

echo "==> 3. Packaging DMG: $DMG_NAME..."
if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
      --volname "$APP_NAME" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 100 \
      --icon "${APP_NAME}.app" 175 190 \
      --hide-extension "${APP_NAME}.app" \
      --app-drop-link 425 190 \
      "$DIST_DIR/$DMG_NAME" \
      "$BUILT_APP" || true
else
    echo "create-dmg not found, falling back to hdiutil..."
    STAGING_DIR="$(mktemp -d /tmp/versoline_dmg_XXXXXX)"
    cp -R "$BUILT_APP" "$STAGING_DIR/"
    ln -s /Applications "$STAGING_DIR/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DIST_DIR/$DMG_NAME"
    rm -rf "$STAGING_DIR"
fi

echo "==> 4. DMG Package generated successfully at: $DIST_DIR/$DMG_NAME"
ls -lh "$DIST_DIR/$DMG_NAME"
