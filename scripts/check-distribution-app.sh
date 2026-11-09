#!/bin/bash
set -euo pipefail
app="${1:?Provide the signed app}"
codesign --verify --deep --strict "$app"
details="$(codesign --display --verbose=4 "$app" 2>&1)"
[[ "$details" == *'Authority=Developer ID Application: '* ]] || { echo 'Not a Developer ID Application signature.' >&2; exit 1; }
[[ "$details" == *'runtime'* && "$details" == *'Timestamp='* ]] || { echo 'Missing hardened runtime or secure timestamp.' >&2; exit 1; }
codesign --display --entitlements :- "$app" 2>/dev/null | python3 -c '
import plistlib,sys
p=plistlib.loads(sys.stdin.buffer.read())
assert p.get("com.apple.security.device.audio-input") is True, "Missing audio input entitlement"
assert not p.get("com.apple.security.get-task-allow"), "Debug entitlement in distribution"
'
