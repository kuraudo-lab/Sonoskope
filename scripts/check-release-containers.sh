#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Provide the version}"
architecture="${2:?Provide the architecture}"
asset_directory="${3:-$PWD/dist}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$architecture" == arm64 || "$architecture" == x86_64 ]]
mkdir -p .build
check_directory="$(mktemp -d "$PWD/.build/installer-check.XXXXXX")"
mounted=false
cleanup() {
  if [[ "$mounted" == true ]]; then hdiutil detach -quiet "$check_directory/mount" || true; fi
  rm -rf "$check_directory"
}
trap cleanup EXIT
mkdir -p "$check_directory/mount"
stem="$asset_directory/Sonoskope-${version}-macos-${architecture}"
hdiutil verify -quiet "$stem.dmg"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$check_directory/mount" "$stem.dmg"
mounted=true
[[ "$(readlink "$check_directory/mount/Applications")" == /Applications ]]
pkgutil --expand-full "$stem.pkg" "$check_directory/expanded"
python3 - "$check_directory" "$version" "$architecture" <<'PYTHON'
from pathlib import Path
import hashlib,plistlib,subprocess,sys,xml.etree.ElementTree as ET
root=Path(sys.argv[1]);version=sys.argv[2];arch=sys.argv[3]
metadata=ET.parse(str(root/'expanded/PackageInfo')).getroot()
assert metadata.attrib['identifier']=='lab.kuraudo.Sonoskope'
assert metadata.attrib['version']==version
assert metadata.attrib['install-location']=='/Applications'
assert metadata.find('scripts') is None
assert metadata.attrib.get('relocatable')=='false'
assert not metadata.findall('relocate/bundle')
assert not (root/'expanded/Scripts').exists()
payload=root/'expanded/Payload'
assert {p.name for p in payload.iterdir()}=={'Sonoskope.app'}
apps=[root/'mount/Sonoskope.app',payload/'Sonoskope.app']
for app in apps:
    with (app/'Contents/Info.plist').open('rb') as f: info=plistlib.load(f)
    assert info['CFBundleIdentifier']=='lab.kuraudo.Sonoskope'
    assert info['CFBundleShortVersionString']==version
    assert info['CFBundleIconFile']=='AppIcon'
    assert (app/'Contents/Resources/AppIcon.icns').stat().st_size>1000
    actual=subprocess.check_output(['lipo','-archs',str(app/'Contents/MacOS/Sonoskope')],universal_newlines=True).strip()
    assert actual==arch,actual
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
for relative in ['Contents/MacOS/Sonoskope','Contents/Resources/AppIcon.icns']:
    assert hashlib.sha256((apps[0]/relative).read_bytes()).digest()==hashlib.sha256((apps[1]/relative).read_bytes()).digest()
print('DMG and PKG: matching signed app, icon, version and architecture; /Applications target, no relocation or install scripts.')
PYTHON
