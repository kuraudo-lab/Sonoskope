#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/distribution-config.sh
configuration="${1:-release}"
if [[ "$distribution" == developer-id ]]; then require_distribution_credentials; fi
swift build -c "$configuration"
bin_path="$(swift build -c "$configuration" --show-bin-path)"
app_path="$PWD/dist/Sonoskope.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/Sonoskope" "$app_path/Contents/MacOS/Sonoskope"
cp App/Info.plist "$app_path/Contents/Info.plist"
cp LICENSE "$app_path/Contents/Resources/LICENSE"
bash scripts/build-icon.sh
cp .build/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
# SwiftPM libraries resolve Bundle.module inside the app's Resources directory.
for bundle in "$bin_path"/*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$app_path/Contents/Resources/"
done
for localization in App/*.lproj; do
  cp -R "$localization" "$app_path/Contents/Resources/"
done
test -d "$app_path/Contents/Resources/Sonoskope_SonoskopeCore.bundle"
# A local certificate preserves the app identity across development rebuilds.
# Preview builds can use a local development identity; public distribution is explicit.
sign_identity="${SONOSKOPE_SIGN_IDENTITY:-}"
if [[ -z "$sign_identity" && -f .local/signing-identity ]]; then
  sign_identity="$(cat .local/signing-identity)"
fi
if [[ "$distribution" == developer-id ]]; then
  /usr/bin/codesign --force --sign "$SONOSKOPE_APPLICATION_IDENTITY" \
    ${signing_keychain[@]+"${signing_keychain[@]}"} --options runtime --timestamp \
    --entitlements App/Distribution.entitlements "$app_path"
  bash scripts/check-distribution-app.sh "$app_path"
else
  /usr/bin/codesign --force --sign "${sign_identity:--}" "$app_path"
fi
/usr/bin/codesign --verify --strict "$app_path"
printf '%s\n' "$app_path"
