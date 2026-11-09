#!/bin/bash
# Exercise notarization failure gates with a fake Apple CLI. No credentials/network.
set -euo pipefail
cd "$(dirname "$0")/.."
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
mkdir "$workspace/bin"
cat > "$workspace/bin/xcrun" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_NOTARY_CALLS"
if [[ "$1" == notarytool ]]; then
  if [[ "$TEST_NOTARY_STATUS" == timeout ]]; then
    printf '{"id":"test-submission","status":"In Progress"}\n'
    exit 1
  fi
  printf '{"id":"test-submission","status":"%s"}\n' "$TEST_NOTARY_STATUS"
fi
MOCK
chmod +x "$workspace/bin/xcrun"
export PATH="$workspace/bin:$PATH"
export TEST_NOTARY_CALLS="$workspace/calls"
export SONOSKOPE_DISTRIBUTION=developer-id
export SONOSKOPE_APPLICATION_IDENTITY='Developer ID Application: Test Fixture (TEST)'
export SONOSKOPE_INSTALLER_IDENTITY='Developer ID Installer: Test Fixture (TEST)'
export SONOSKOPE_NOTARY_PROFILE=fixture
unset SONOSKOPE_SIGNING_KEYCHAIN SONOSKOPE_NOTARY_KEYCHAIN
: > "$TEST_NOTARY_CALLS"
if SONOSKOPE_APPLICATION_IDENTITY='Apple Development: Wrong Type' bash scripts/package-release.sh 0.1.6 arm64 >"$workspace/error" 2>&1; then
  echo 'A development identity must not pass public-release preflight.' >&2; exit 1
fi
[[ ! -s "$TEST_NOTARY_CALLS" ]]
for status in Invalid timeout; do
  : > "$TEST_NOTARY_CALLS"
  if TEST_NOTARY_STATUS="$status" bash scripts/notarize-file.sh fixture.zip fixture.app >"$workspace/error" 2>&1; then
    echo 'Rejected/pending submissions must fail.' >&2; exit 1
  fi
  ! grep -q stapler "$TEST_NOTARY_CALLS"
done
: > "$TEST_NOTARY_CALLS"
TEST_NOTARY_STATUS=Accepted bash scripts/notarize-file.sh fixture.zip fixture.app >"$workspace/result"
grep -q 'stapler staple fixture.app' "$TEST_NOTARY_CALLS"
grep -q 'stapler validate fixture.app' "$TEST_NOTARY_CALLS"
# A non-default keychain must be forwarded to notarytool, including spaces in its path.
: > "$TEST_NOTARY_CALLS"
TEST_NOTARY_STATUS=Accepted SONOSKOPE_NOTARY_KEYCHAIN='/tmp/test keychain' bash scripts/notarize-file.sh fixture.zip fixture.app >"$workspace/result"
grep -q -- '--keychain /tmp/test keychain' "$TEST_NOTARY_CALLS"
echo 'Distribution gates passed: wrong identity, rejection, timeout, accepted/stapled, custom keychain.'
