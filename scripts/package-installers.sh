#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
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
This developer preview is not notarized. macOS may ask you to allow it in
System Settings > Privacy & Security. Allow microphone/audio access when requested.

请先退出正在运行的 Sonoskope，再将 Sonoskope.app 拖到 Applications。
推出此磁盘映像，从“应用程序”中打开 Sonoskope。
此开发预览版尚未经过 Apple 公证，macOS 可能需要你在“系统设置 > 隐私与安全性”中允许打开。
请按提示授予麦克风或音频录制权限。
TEXT
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
