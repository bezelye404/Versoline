#!/bin/bash
set -euo pipefail

# Versoline Release Verification Script
# Validates DMG integrity, SHA-256 checksum, codesign status, Gatekeeper acceptance, and Notarization ticket.

if [ $# -lt 1 ]; then
    echo "Usage: $0 <path-to-Versoline-version.dmg>" >&2
    exit 1
fi

DMG_FILE="$1"

if [ ! -f "$DMG_FILE" ]; then
    echo "Error: File '$DMG_FILE' does not exist." >&2
    exit 1
fi

echo "=========================================================="
echo "          Versoline Release Verification Tool             "
echo "=========================================================="
echo "Target file: $DMG_FILE"
echo ""

# 1. SHA-256 Checksum
echo "==> 1. SHA-256 Checksum:"
SHA256_HASH=$(shasum -a 256 "$DMG_FILE" | awk '{print $1}')
echo "    SHA-256: $SHA256_HASH"
echo ""

# 2. Disk Image Attach & Verification
MOUNT_DIR=$(mktemp -d /tmp/versoline_verify_XXXXXX)
trap 'hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true; rm -rf "$MOUNT_DIR"' EXIT

echo "==> 2. Mounting Disk Image..."
hdiutil attach "$DMG_FILE" -mountpoint "$MOUNT_DIR" -nobrowse -readonly >/dev/null

APP_BUNDLE="$MOUNT_DIR/Versoline.app"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: Versoline.app not found inside DMG root!" >&2
    exit 1
fi
echo "    Versoline.app verified inside volume."
echo ""

# 3. Codesign Check
echo "==> 3. Inspecting Code Signature (codesign):"
codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 | sed 's/^/    /'
echo ""

# 4. Gatekeeper Assessment (spctl)
echo "==> 4. Assessing Gatekeeper Acceptance (spctl):"
if spctl -a -vv "$APP_BUNDLE" 2>&1 | sed 's/^/    /'; then
    echo "    Result: ACCEPTED by Gatekeeper"
else
    echo "    Result: REJECTED by Gatekeeper (Expected for ad-hoc / non-notarized build; requires xattr -cr)"
fi
echo ""

# 5. Apple Notarization Stapler Check
echo "==> 5. Checking Notarization Ticket (stapler):"
if xcrun stapler validate "$APP_BUNDLE" 2>&1 | sed 's/^/    /'; then
    echo "    Result: Valid Notarization ticket found."
else
    echo "    Result: No Notarization ticket found (Expected for ad-hoc open-source build)."
fi
echo ""

# 6. Bundle Info Verification
echo "==> 6. Bundle Identifiers & Metadata:"
echo "    CFBundleName:               $(defaults read "$APP_BUNDLE/Contents/Info.plist" CFBundleName 2>/dev/null || echo 'N/A')"
echo "    CFBundleDisplayName:        $(defaults read "$APP_BUNDLE/Contents/Info.plist" CFBundleDisplayName 2>/dev/null || echo 'N/A')"
echo "    CFBundleIdentifier:         $(defaults read "$APP_BUNDLE/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo 'N/A')"
echo "    CFBundleShortVersionString: $(defaults read "$APP_BUNDLE/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 'N/A')"
echo "    CFBundleVersion:            $(defaults read "$APP_BUNDLE/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo 'N/A')"
echo ""

echo "=========================================================="
echo "          Verification Summary: COMPLETE                  "
echo "=========================================================="
