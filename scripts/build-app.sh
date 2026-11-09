#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration"
bin_path="$(swift build -c "$configuration" --show-bin-path)"
app_path="$PWD/dist/Sonoskope.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/Sonoskope" "$app_path/Contents/MacOS/Sonoskope"
cp App/Info.plist "$app_path/Contents/Info.plist"
# SwiftPM libraries resolve Bundle.module inside the app's Resources directory.
for bundle in "$bin_path"/*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$app_path/Contents/Resources/"
done
for localization in App/*.lproj; do
  cp -R "$localization" "$app_path/Contents/Resources/"
done
test -d "$app_path/Contents/Resources/Sonoskope_SonoskopeCore.bundle"
/usr/bin/codesign --force --sign "${SONOSKOPE_SIGN_IDENTITY:--}" "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
printf '%s\n' "$app_path"
