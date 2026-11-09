#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_image="$PWD/assets/brand/sonoskope-icon.png"
mkdir -p .build
icon_workspace="$(mktemp -d "$PWD/.build/app-icon.XXXXXX")"
trap 'rm -rf "$icon_workspace"' EXIT
iconset="$icon_workspace/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$source_image" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$source_image" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$PWD/.build/AppIcon.icns"
