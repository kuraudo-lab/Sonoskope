#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/distribution-config.sh
if [[ "$distribution" == developer-id ]]; then require_distribution_credentials; fi
version="${1:?Provide the version}"
architecture="${2:?Provide the architecture}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$architecture" == arm64 || "$architecture" == x86_64 ]]
app="$PWD/dist/Sonoskope.app"
stem="$PWD/dist/Sonoskope-${version}-macos-${architecture}"
workspace="$(mktemp -d "$PWD/.build/installers.XXXXXX")"
trap 'rm -rf "$workspace"' EXIT
mkdir -p "$workspace/dmg" "$workspace/pkgroot"
ditto "$app" "$workspace/dmg/Sonoskope.app"
ln -s /Applications "$workspace/dmg/Applications"
cat > "$workspace/dmg/Install.txt" <<'TEXT'
Sonoskope

Quit any running copy, then drag Sonoskope.app onto Applications.
Eject this disk image and open Sonoskope from Applications.
Allow microphone/audio access only when you choose to enable analysis.

请先退出正在运行的 Sonoskope，再将 Sonoskope.app 拖到 Applications。
推出此磁盘映像，从“应用程序”中打开 Sonoskope。
仅在你选择开启分析时，按提示授予麦克风或音频录制权限。
TEXT
if [[ "$distribution" == preview ]]; then
  cat >> "$workspace/dmg/Install.txt" <<'TEXT'

Developer preview: not notarized by Apple; macOS may block first launch.
开发预览版：尚未经过 Apple 公证，macOS 可能阻止首次启动。
TEXT
fi
hdiutil create -quiet -ov -volname "Sonoskope $version" -srcfolder "$workspace/dmg" -fs HFS+ -format UDZO "$stem.dmg"
ditto "$app" "$workspace/pkgroot/Sonoskope.app"
python3 - "$workspace/components.plist" <<'PYTHON'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
    plistlib.dump([dict(RootRelativeBundlePath='Sonoskope.app',BundleIsRelocatable=False,
                       BundleIsVersionChecked=True,BundleHasStrictIdentifier=True,
                       BundleOverwriteAction='upgrade')],f)
PYTHON
pkgbuild --root "$workspace/pkgroot" --component-plist "$workspace/components.plist" \
  --identifier lab.kuraudo.Sonoskope --version "$version" --install-location /Applications \
  --ownership recommended "$stem.pkg"

if [[ "$distribution" == developer-id ]]; then
  codesign --force --sign "$SONOSKOPE_APPLICATION_IDENTITY" ${signing_keychain[@]+"${signing_keychain[@]}"} --timestamp "$stem.dmg"
  productsign --sign "$SONOSKOPE_INSTALLER_IDENTITY" ${signing_keychain[@]+"${signing_keychain[@]}"} --timestamp "$stem.pkg" "$workspace/signed.pkg"
  mv "$workspace/signed.pkg" "$stem.pkg"
fi
