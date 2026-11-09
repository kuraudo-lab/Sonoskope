#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/distribution-config.sh
[[ "$distribution" == developer-id ]] || { echo 'Notarization requires developer-id mode.' >&2; exit 1; }
require_distribution_credentials
archive="${1:?Provide the archive to submit}"
target="${2:?Provide the app, DMG or PKG to staple}"
mkdir -p .local/notarization
result="$(mktemp "$PWD/.local/notarization/submission.XXXXXX")"
# Preserve submission IDs and results, including failures/timeouts, for investigation.
# A timeout must be resumed with notarytool info/wait; do not resubmit blindly.
if ! xcrun notarytool submit "$archive" --keychain-profile "$SONOSKOPE_NOTARY_PROFILE" \
  ${notary_keychain[@]+"${notary_keychain[@]}"} --wait --timeout 20m --output-format json >"$result"; then
  printf 'Notarization did not complete; inspect %s before retrying.\n' "$result" >&2
  exit 1
fi
python3 - "$result" <<'PY'
import json,sys
with open(sys.argv[1]) as f: result=json.load(f)
if result.get('status')!='Accepted':
    raise SystemExit('Notarization not accepted; inspect '+sys.argv[1])
print('Apple accepted notarization submission '+result['id'])
PY
xcrun stapler staple "$target"
xcrun stapler validate "$target"
