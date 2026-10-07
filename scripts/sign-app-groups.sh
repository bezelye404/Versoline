#!/bin/bash
set -euo pipefail

# Adds the app group entitlement to a built Versoline.app and its widget, and signs both again (ad hoc).
# Xcode refuses the "application-groups" entitlement without a provisioning profile, so it is added here, after the
# build. The group comes from `AppGroupIdentifier` in each Info.plist (set per configuration in project.yml).
# Usage: scripts/sign-app-groups.sh path/to/Versoline.app

APP="${1:?usage: sign-app-groups.sh path/to/Versoline.app}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sign() {
  local bundle="$1" name="$2"
  local group entitlements="$WORK/$name.plist"
  group="$(/usr/libexec/PlistBuddy -c 'Print :AppGroupIdentifier' "$bundle/Contents/Info.plist")"
  # Keep the entitlements Xcode signed with, and add the group.
  if ! codesign -d --entitlements :- "$bundle" 2>/dev/null > "$entitlements" || [ ! -s "$entitlements" ]; then
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n' > "$entitlements"
  fi
  /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" "$entitlements" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups array" "$entitlements"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups:0 string $group" "$entitlements"
  codesign --force --sign - --options runtime --entitlements "$entitlements" "$bundle"
}

for appex in "$APP"/Contents/PlugIns/*.appex; do
  [ -d "$appex" ] && sign "$appex" "$(basename "$appex" .appex)"
done
sign "$APP" app
codesign --verify --deep --strict "$APP"
echo "==> Signed with app group: $(/usr/libexec/PlistBuddy -c 'Print :AppGroupIdentifier' "$APP/Contents/Info.plist")"
