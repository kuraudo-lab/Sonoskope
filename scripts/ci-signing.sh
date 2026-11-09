#!/bin/bash
# Only ephemeral GitHub-hosted release runners use this script. No key export.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && -n "${RUNNER_TEMP:-}" ]] || { echo 'This helper requires a GitHub Actions runner.' >&2; exit 1; }
signing_directory="$RUNNER_TEMP/sonoskope-release-signing"
keychain="$signing_directory/signing.keychain-db"
if [[ "${1:-}" == cleanup ]]; then
  if [[ -f "$keychain" ]]; then security delete-keychain "$keychain"; fi
  rm -rf "$signing_directory"
  exit
fi
[[ "${1:-}" == setup ]] || { echo 'Use setup or cleanup.' >&2; exit 1; }
# Check everything before importing any private material.
python3 - <<'PY'
import os
names=['SONOSKOPE_CERTIFICATES_P12','SONOSKOPE_CERTIFICATES_PASSWORD',
       'SONOSKOPE_APPLICATION_IDENTITY','SONOSKOPE_INSTALLER_IDENTITY',
       'SONOSKOPE_NOTARY_KEY','SONOSKOPE_NOTARY_KEY_ID','SONOSKOPE_NOTARY_ISSUER_ID']
missing=[n for n in names if not os.environ.get(n)]
if missing: raise SystemExit('Missing release configuration: '+', '.join(missing))
for n in ['SONOSKOPE_APPLICATION_IDENTITY','SONOSKOPE_INSTALLER_IDENTITY']:
    if '\n' in os.environ[n] or '\r' in os.environ[n]: raise SystemExit('Invalid identity name')
PY
umask 077
mkdir "$signing_directory"
python3 - "$signing_directory" <<'PY'
import base64,os,sys
from pathlib import Path
p=Path(sys.argv[1])
(p/'certificates.p12').write_bytes(base64.b64decode(os.environ['SONOSKOPE_CERTIFICATES_P12'],validate=True))
(p/'notary.p8').write_text(os.environ['SONOSKOPE_NOTARY_KEY'])
PY
keychain_password="$(openssl rand -hex 24)"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 7200 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$signing_directory/certificates.p12" -k "$keychain" -P "$SONOSKOPE_CERTIFICATES_PASSWORD" -T /usr/bin/codesign -T /usr/bin/productsign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
xcrun notarytool store-credentials SonoskopeRelease --key "$signing_directory/notary.p8" \
  --key-id "$SONOSKOPE_NOTARY_KEY_ID" --issuer "$SONOSKOPE_NOTARY_ISSUER_ID" --keychain "$keychain"
# Private input files are no longer needed; keys remain only in the temporary keychain.
rm "$signing_directory/certificates.p12" "$signing_directory/notary.p8"
{
  printf 'SONOSKOPE_SIGNING_KEYCHAIN=%s\n' "$keychain"
  printf 'SONOSKOPE_NOTARY_KEYCHAIN=%s\n' "$keychain"
  printf 'SONOSKOPE_NOTARY_PROFILE=SonoskopeRelease\n'
} >> "$GITHUB_ENV"
