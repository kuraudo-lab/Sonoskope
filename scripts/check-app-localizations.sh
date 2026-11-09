#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="${1:-dist/Sonoskope.app}"
verification_directory="$(mktemp -d "${TMPDIR:-/tmp}/sonoskope-localization.XXXXXX")"
trap 'rm -rf "$verification_directory"' EXIT
ditto "$app_path" "$verification_directory/Sonoskope.app"
codesign --verify --strict "$verification_directory/Sonoskope.app"
python3 - "$verification_directory/Sonoskope.app" <<'PYTHON'
from pathlib import Path
import json, subprocess, sys
app=Path(sys.argv[1]).resolve()
binary=app/'Contents/MacOS/Sonoskope'
for preference, expected in [('en-US','en'),('zh-Hans-CN','zh-Hans'),('zh-Hant-TW','zh-Hans'),('ja-JP','en')]:
    result=subprocess.run([str(binary),'--localization-check','-AppleLanguages','('+preference+')'],
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,universal_newlines=True,timeout=15)
    if result.returncode:
        raise SystemExit(result.stderr or 'App localization check failed')
    payload=json.loads(result.stdout)
    assert payload['language']==expected,payload
    assert payload['soundLevel']==('Sound level' if expected=='en' else '声音电平'),payload
    assert payload['microphonePermission'].startswith('Analyze local' if expected=='en' else '仅在你主动测试'),payload
    # Build-tree fallback would conceal missing resources in a shipped app.
    assert app in Path(payload['resourceBundle']).resolve().parents,payload
    print(preference+' -> '+expected+': relocated app resources and permission descriptions OK')
PYTHON
