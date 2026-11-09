#!/bin/bash
# Real Sparkle installation using disposable apps; never launches audio collectors.
set -euo pipefail
cd "$(dirname "$0")/.."
identity="${SONOSKOPE_APPLICATION_IDENTITY:?Provide Developer ID Application identity}"
swift build
bin_path="$(swift build --show-bin-path)"
python3 scripts/check-updater.py "$bin_path" "$identity"
