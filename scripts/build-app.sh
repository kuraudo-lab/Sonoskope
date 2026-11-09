#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/distribution-config.sh
configuration="${1:-release}"
if [[ "$distribution" == developer-id ]]; then require_distribution_credentials; fi
build_options=(-c "$configuration")
if [[ -n "${SONOSKOPE_ARCHITECTURE:-}" ]]; then
  case "$SONOSKOPE_ARCHITECTURE" in arm64|x86_64) ;; *) echo 'Unsupported architecture' >&2; exit 1 ;; esac
  build_options+=(--build-system native --triple "${SONOSKOPE_ARCHITECTURE}-apple-macosx14.2"
    --scratch-path ".build/distribution-${SONOSKOPE_ARCHITECTURE}")
fi
swift build "${build_options[@]}"
bin_path="$(swift build "${build_options[@]}" --show-bin-path)"
app_path="$PWD/dist/Sonoskope.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/Sonoskope" "$app_path/Contents/MacOS/Sonoskope"
cp App/Info.plist "$app_path/Contents/Info.plist"
architecture="$(lipo -archs "$bin_path/Sonoskope")"
case "$architecture" in arm64|x86_64) ;; *) echo 'Expected one application architecture' >&2; exit 1 ;; esac
/usr/libexec/PlistBuddy -c "Set :SUFeedURL https://raw.githubusercontent.com/kuraudo-lab/Sonoskope/main/updates/appcast-${architecture}.xml" "$app_path/Contents/Info.plist"
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
  sign_identity="$SONOSKOPE_APPLICATION_IDENTITY"
fi
artifact_root=".build"
if [[ -n "${SONOSKOPE_ARCHITECTURE:-}" ]]; then artifact_root=".build/distribution-${SONOSKOPE_ARCHITECTURE}"; fi
framework="$artifact_root/artifacts/sonoskope/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
bash scripts/embed-sparkle.sh "$app_path" "$framework" "${sign_identity:--}"
cp "$artifact_root/artifacts/sonoskope/Sparkle/LICENSE" "$app_path/Contents/Resources/Sparkle-LICENSE"
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
