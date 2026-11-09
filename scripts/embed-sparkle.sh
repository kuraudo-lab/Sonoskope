#!/bin/bash
# Embed the pinned binary dependency and sign nested helpers inside-out.
set -euo pipefail
app="${1:?App bundle required}"
framework="${2:?Sparkle framework required}"
identity="${3:--}"
mkdir -p "$app/Contents/Frameworks"
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
embedded="$app/Contents/Frameworks/Sparkle.framework"
options=(--force --sign "$identity")
if [[ "$identity" == 'Developer ID Application: '* ]]; then
  options+=(--options runtime --timestamp)
fi
if [[ -n "${SONOSKOPE_SIGNING_KEYCHAIN:-}" ]]; then
  options+=(--keychain "$SONOSKOPE_SIGNING_KEYCHAIN")
fi
for component in "$embedded/Versions/B/Autoupdate" "$embedded/Versions/B/Updater.app" "$embedded/Versions/B/XPCServices/"*.xpc; do
  codesign "${options[@]}" --preserve-metadata=identifier,entitlements "$component"
done
codesign "${options[@]}" "$embedded"
