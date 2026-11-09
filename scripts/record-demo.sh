#!/bin/bash
# Record only the isolated presentation window; never records microphone/system audio.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null || { echo 'Install FFmpeg to encode the demo.' >&2; exit 1; }
command -v ffprobe >/dev/null || { echo 'FFprobe is required to verify the demo.' >&2; exit 1; }
swift build
bash scripts/build-icon.sh
bin_path="$(swift build --show-bin-path)"
mkdir -p .local/demo
run_dir="$(mktemp -d "$PWD/.local/demo/take.XXXXXX")"
python3 - "$bin_path" "$run_dir" <<'PY'
from pathlib import Path
import plistlib, shutil, subprocess, sys
binary=Path(sys.argv[1]); app=Path(sys.argv[2])/'SonoskopeDemo.app'
(app/'Contents/MacOS').mkdir(parents=True)
resources=app/'Contents/Resources'; resources.mkdir()
framework=next(Path('.build/artifacts/sonoskope/Sparkle').rglob('macos-arm64_x86_64/Sparkle.framework'))
modules=binary/'Modules'
if not modules.exists(): modules=binary
library=binary/'libSonoskopeCore.a'
objects=[str(library)] if library.exists() else [str(p) for p in (binary/'SonoskopeCore.build').glob('*.o')]
if not objects: raise SystemExit('Missing built core objects')
sources=[str(p) for p in Path('Sources/Sonoskope').glob('*.swift') if p.name!='AppMain.swift']
arch=subprocess.check_output(['lipo','-archs',str(binary/'Sonoskope')],text=True).strip()
subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','5','-target',arch+'-apple-macos14.2','-I',str(modules),'-F',str(framework.parent),'-framework','Sparkle','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',*sources,'Tools/DemoPresentation.swift',*objects,'-o',str(app/'Contents/MacOS/SonoskopeDemo')],check=True)
with open('App/Info.plist','rb') as f: info=plistlib.load(f)
info.update(CFBundleIdentifier='lab.kuraudo.Sonoskope.Demo',CFBundleExecutable='SonoskopeDemo',CFBundleName='Sonoskope Demo')
with (app/'Contents/Info.plist').open('wb') as f: plistlib.dump(info,f)
shutil.copy2('.build/AppIcon.icns',resources/'AppIcon.icns')
for bundle in list(binary.glob('*.bundle'))+list(Path('App').glob('*.lproj')):
    shutil.copytree(bundle,resources/bundle.name)
subprocess.run(['bash','scripts/embed-sparkle.sh',str(app),str(framework)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
PY
"$run_dir/SonoskopeDemo.app/Contents/MacOS/SonoskopeDemo" "$run_dir" -AppleLanguages '(en)' >"$run_dir/app.log" 2>&1 &
app_pid=$!
capture_pid=''
cleanup() {
  [[ -z "$capture_pid" ]] || kill "$capture_pid" 2>/dev/null || true
  kill "$app_pid" 2>/dev/null || true
}
trap cleanup EXIT
for ((i=0;i<100;i++)); do
  [[ -s "$run_dir/window-id" ]] && break
  kill -0 "$app_pid" 2>/dev/null || { cat "$run_dir/app.log" >&2; exit 1; }
  sleep 0.1
done
[[ -s "$run_dir/window-id" ]] || { echo 'Presentation window failed to open.' >&2; exit 1; }
window_id="$(cat "$run_dir/window-id")"
# Window-scoped recording avoids other apps. Omitting -g/-G/-A keeps it silent.
/usr/sbin/screencapture -x -o -v -l "$window_id" -V 34 "$run_dir/capture.mov" >"$run_dir/capture.log" 2>&1 &
capture_pid=$!
touch "$run_dir/recording-started"
wait "$capture_pid" || { cat "$run_dir/capture.log" >&2; echo 'Screen Recording permission may be required for the launching terminal/app.' >&2; exit 1; }
capture_pid=''
[[ -s "$run_dir/capture.mov" ]] || { cat "$run_dir/capture.log" >&2; echo 'No recording produced. Check macOS Screen Recording permission.' >&2; exit 1; }
ffmpeg -hide_banner -loglevel error -y -i "$run_dir/capture.mov" -t 8 -an \
  -vf 'setpts=(PTS-STARTPTS)*8/34,scale=trunc(iw/2)*2:trunc(ih/2)*2' -r 30 -c:v libx264 -crf 20 -pix_fmt yuv420p -movflags +faststart "$run_dir/sonoskope-demo-en.mp4"
ffprobe -v error -show_entries format=duration:stream=codec_name,width,height,codec_type -of json "$run_dir/sonoskope-demo-en.mp4" >"$run_dir/verification.json"
python3 - "$run_dir/verification.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f: result=json.load(f)
streams=result['streams']
assert len(streams)==1 and streams[0]['codec_type']=='video', 'Expected silent video only'
assert streams[0]['codec_name']=='h264', 'Expected H.264'
assert 7.9 <= float(result['format']['duration']) <= 8.1, 'Unexpected recording duration'
assert streams[0]['width'] >= 1000 and streams[0]['height'] >= 800, 'Unexpected capture size'
print(json.dumps(result, indent=2))
PY
mkdir -p dist/demo
cp "$run_dir/sonoskope-demo-en.mp4" dist/demo/sonoskope-demo-en.mp4
ffmpeg -hide_banner -loglevel error -y -ss 3 -i dist/demo/sonoskope-demo-en.mp4 -frames:v 1 dist/demo/poster.png
ffmpeg -hide_banner -loglevel error -y -i dist/demo/sonoskope-demo-en.mp4 \
  -filter_complex '[0:v]fps=2,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer' \
  -loop 0 dist/demo/sonoskope-demo.gif
printf 'Demo: %s/dist/demo/sonoskope-demo-en.mp4\nTake: %s\n' "$PWD" "$run_dir"
