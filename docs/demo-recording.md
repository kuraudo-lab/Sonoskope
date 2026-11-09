# Recording the product demo

The demo is a silent, 34-second English screen recording of a dedicated native presentation window. It uses the shipping `StatusView` and `TelemetryCharts` with the existing simulated scenarios, alongside explanatory captions. Every scene labels its data as simulated. This is a scripted presentation of the app's views; physical-device behavior and real meeting quality require separate acceptance checks.

## Tools

| Tool | Purpose | Required |
| --- | --- | --- |
| Xcode / SwiftPM | Compile the app's views and the separate presentation executable | Yes |
| macOS `screencapture` | Record only the presentation's window ID, without microphone or system audio | Yes; bundled with macOS |
| FFmpeg and FFprobe | Encode H.264 MP4, extract a poster, and verify duration, dimensions and absence of audio | Yes |
| Codex native computer use | Inspect the presentation and the existing app's state | Optional; the recorder runs without UI clicks |

FFmpeg and FFprobe were already installed on the development machine. No paid recorder, avatar service, voice generation, or third-party media upload is needed. macOS must permit screen recording for the terminal or app that launches the script. If permission is missing, grant it through System Settings and rerun; the script does not change permissions.

## Run

From the repository root:

```sh
bash scripts/record-demo.sh
```

The script builds a separate `.local/demo/take.XXXXXX/SonoskopeDemo.app`, opens its presentation window, records 34 seconds, encodes the video, and verifies its metadata. Keep the Mac awake and unlocked while recording. It closes its own presentation process when finished; it does not terminate a running Sonoskope instance.

Outputs:

- `dist/demo/sonoskope-demo-en.mp4`: latest completed H.264 video, silent, 30 fps.
- `dist/demo/poster.png`: a frame from the timeline scene.
- `dist/demo/sonoskope-demo.gif`: a lightweight, 720-pixel preview for GitHub.
- `.local/demo/take.XXXXXX/`: original MOV, encoded MP4, app/capture logs, metadata, and the isolated executable for that take.

Both output directories are Git-ignored. Successful reruns replace the latest MP4/poster and retain individual takes. Review the video before uploading it to a public release or video host.

## Storyboard

| Approximate time | View | Message |
| --- | --- | --- |
| 0–9 s | Correlated audio/network incident | Start with local evidence and a suggested next step. |
| 9–17 s | Sound and network charts | Compare timing; correlation does not establish a cause. |
| 17–25 s | Device-disconnect incident | Distinguish an observed disconnect from its unknown cause. |
| 25–34 s | Capture-unavailable incident | Missing data does not mean healthy audio. |

The narrative and scene timing live in `Tools/DemoPresentation.swift`. The tool is compiled separately from the shipping entry point; it is not included in release packages. `MonitorModel(persist: false, runsCollectors: false)` isolates the demo from live preferences, collectors, notifications, and incident history. Its status view is display-only. The screen recorder omits all audio flags.

## README screenshots

The bilingual screenshots use actual app views rendered with the correlated scenario:

```sh
bash scripts/render-check.sh
mkdir -p assets/demo
cp .local/render-check/en/correlated.png assets/demo/status-en.png
cp .local/render-check/zh-Hans/correlated.png assets/demo/status-zh.png
cp dist/demo/sonoskope-demo.gif assets/demo/sonoskope-demo.gif
```

These PNGs are tracked so GitHub can display them without a local build. Their README captions explicitly identify simulated data.

Run the recorder first to refresh the GIF. The READMEs link to this tracked preview; the full-quality MP4 remains a local upload artifact.

## Verification

Before sharing, inspect frames from all four scenes for clipping and unrelated windows, and play the full MP4. FFprobe checks in the script require a single H.264 video stream, no audio, a 33–35-second duration, and dimensions of at least 1000 × 800. Automated metadata validation does not verify visual correctness or physical audio behavior.
