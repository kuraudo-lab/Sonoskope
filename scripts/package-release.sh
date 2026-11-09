#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/distribution-config.sh
if [[ "$distribution" == developer-id ]]; then require_distribution_credentials; fi
version="${1:?Provide a release version such as 0.1.0}"
architecture="${2:-$(uname -m)}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version" >&2
  exit 1
fi
if [[ "$architecture" != "arm64" && "$architecture" != "x86_64" ]]; then
  echo "Unsupported architecture" >&2
  exit 1
fi
actual_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' App/Info.plist)"
if [[ "$version" != "$actual_version" ]]; then
  echo "Tag version does not match Info.plist" >&2
  exit 1
fi
SONOSKOPE_ARCHITECTURE="$architecture" bash scripts/build-app.sh
bash scripts/check-app-localizations.sh dist/Sonoskope.app
actual_arch="$(lipo -archs dist/Sonoskope.app/Contents/MacOS/Sonoskope)"
if [[ "$actual_arch" != "$architecture" ]]; then
  echo "Built architecture does not match asset label: $actual_arch" >&2
  exit 1
fi
if [[ "$distribution" == developer-id ]]; then
  submission="$(mktemp -d "$PWD/.build/notary-app.XXXXXX")"
  trap 'rm -rf "$submission"' EXIT
  ditto -c -k --sequesterRsrc --keepParent dist/Sonoskope.app "$submission/app.zip"
  bash scripts/notarize-file.sh "$submission/app.zip" "$PWD/dist/Sonoskope.app"
  spctl --assess --type execute --verbose=2 dist/Sonoskope.app
fi
asset="Sonoskope-${version}-macos-${architecture}.zip"
ditto -c -k --sequesterRsrc --keepParent dist/Sonoskope.app "dist/$asset"
bash scripts/package-installers.sh "$version" "$architecture"
if [[ "$distribution" == developer-id ]]; then
  for format in dmg pkg; do
    container="$PWD/dist/Sonoskope-${version}-macos-${architecture}.$format"
    bash scripts/notarize-file.sh "$container" "$container"
  done
  codesign --verify --strict "dist/Sonoskope-${version}-macos-${architecture}.dmg"
  pkgutil --check-signature "dist/Sonoskope-${version}-macos-${architecture}.pkg"
  spctl --assess --type install --verbose=2 "dist/Sonoskope-${version}-macos-${architecture}.pkg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "dist/Sonoskope-${version}-macos-${architecture}.dmg"
fi
bash scripts/check-release-containers.sh "$version" "$architecture"
python3 - "$version" "$architecture" <<'PYTHON'
from pathlib import Path
import hashlib,sys
for extension in ['zip','dmg','pkg']:
    asset=Path('dist')/('Sonoskope-'+sys.argv[1]+'-macos-'+sys.argv[2]+'.'+extension)
    digest=hashlib.sha256(asset.read_bytes()).hexdigest()
    asset.with_suffix(asset.suffix+'.sha256').write_text(digest+'  '+asset.name+'\n')
    print(asset.name,digest)
PYTHON
