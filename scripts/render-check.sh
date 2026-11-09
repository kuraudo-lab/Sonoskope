#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
bash scripts/build-icon.sh
bin_path="$(swift build --show-bin-path)"
check_app="$PWD/.local/RenderCheck.app"
mkdir -p "$check_app/Contents/MacOS" "$PWD/.local/render-check"
python3 - "$bin_path" "$check_app" <<'PYTHON'
from pathlib import Path
import plistlib, subprocess, sys, shutil
binary_directory=Path(sys.argv[1]); app=Path(sys.argv[2])
source=[str(p) for p in Path('Sources/Sonoskope').glob('*.swift') if p.name!='AppMain.swift']
modules=binary_directory/'Modules'
if not modules.exists(): modules=binary_directory
library=binary_directory/'libSonoskopeCore.a'
objects=[str(library)] if library.exists() else [str(p) for p in (binary_directory/'SonoskopeCore.build').glob('*.o')]
if not objects: raise SystemExit('Core library missing; build the package first')
subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','5','-target',subprocess.check_output(['lipo','-archs',str(binary_directory/'Sonoskope')],universal_newlines=True).strip()+'-apple-macos14.2','-I',str(modules),*source,'Tools/RenderCheck.swift',*objects,'-o',str(app/'Contents/MacOS/RenderCheck')],check=True)
with open('App/Info.plist','rb') as f: info=plistlib.load(f)
info.update(CFBundleIdentifier='lab.kuraudo.Sonoskope.RenderCheck',CFBundleExecutable='RenderCheck',CFBundleName='Sonoskope Render Check')
with open(app/'Contents/Info.plist','wb') as f: plistlib.dump(info,f)
resources=app/'Contents/Resources'
resources.mkdir(exist_ok=True)
shutil.copy2(".build/AppIcon.icns",str(resources/"AppIcon.icns"))
for bundle in list(binary_directory.glob('*.bundle'))+list(Path('App').glob('*.lproj')):
    target=resources/bundle.name
    if target.exists(): shutil.rmtree(str(target))
    shutil.copytree(str(bundle),str(target))
PYTHON
codesign --force --sign - "$check_app"
for language in en zh-Hans; do
  "$check_app/Contents/MacOS/RenderCheck" "$PWD/.local/render-check/$language" -AppleLanguages "($language)"
done
