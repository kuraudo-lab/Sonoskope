# Sonoskope

English | [简体中文](README_zh.md)

A native macOS menu-bar app for investigating interrupted meeting audio.

Sonoskope asks two questions: **is my local input healthy?** and **where might the sound I hear be breaking up?** It correlates system-visible audio, device, Bluetooth, and network evidence without Zoom or Teams APIs.

## Download

[GitHub Releases](https://github.com/kuraudo-lab/Sonoskope/releases) provides Apple Silicon (`arm64`) and Intel (`x86_64`) downloads with SHA-256 checksums:

- **DMG (recommended):** open the disk image, drag Sonoskope onto Applications, then eject the image and launch the app from Applications.
- **PKG:** open the installer to install or update `/Applications/Sonoskope.app`. It may request administrator authorization. It installs only the app, without scripts or background services.
- **ZIP:** portable archive for users who prefer manual placement.

Quit any running copy before updating. Versions starting with 0.1.5 include the new icon in the app bundle, status window and menu bar. These builds are **ad-hoc signed, unnotarized developer previews**; the PKG container is unsigned. Changing the package format does not remove Gatekeeper checks. Local source builds remain available below.

## Language

Starting with v0.1.2, the interface follows the macOS preferred-language order and supports English and Chinese. The first supported preference is used; if none is supported, it falls back to English. Chinese regional/script variants share the Simplified Chinese translation. Restart Sonoskope after changing system or app language.

Menus, settings, charts, notifications, permission descriptions, and diagnostics are localized. Incident history stores message keys and parameters and can be displayed in either language. Known v0.1.0 messages migrate on read; device/app names, system errors, and unknown historical text retain their original wording. The original v0.1.0 download remains unchanged.

## Run locally

Requires macOS 14.2+, Xcode 15.3+ / Swift 5.10+. Developed and checked on Apple Silicon; see [validation](docs/validation.md) for the actual tested environment.

```sh
swift test
bash scripts/build-app.sh
open dist/Sonoskope.app
```

Open `Package.swift` in Xcode for editing. The build script assembles an actual `.app` bundle with permission descriptions, bundled translations, and local ad-hoc signing. `swift run` is not the supported permission-testing launch path. This is a developer build, not a notarized distribution. To use your signing identity, set `SONOSKOPE_SIGN_IDENTITY` when building; rebuilding an ad-hoc signed binary can invalidate prior privacy grants.

Left-click the menu-bar waveform to open status; right-click for settings and quit. Closing a window leaves monitoring running.

For repeated local development builds, use a valid Apple signing certificate to avoid a new ad-hoc identity on each rebuild. `SONOSKOPE_SIGN_IDENTITY` takes precedence; alternatively, store the certificate name or fingerprint in the ignored `.local/signing-identity` file. This does not change CI signing or make a development certificate suitable for public distribution.

## What works

- Real Core Audio device/default-route/format snapshots and audio process activity, sampled every two seconds. Disconnect incidents are scoped to recently used/default devices and audio activity.
- Optional connected Bluetooth RSSI readings, with unsupported values explicitly unavailable. No guessed Bluetooth packet-loss or codec metrics.
- Network path monitoring and optional TCP connection probes to `www.apple.com:443` only while measured input or output levels are active, every five seconds after completion. Probes stop during near silence (≤ −65 dBFS), missing/stale PCM (over 3 seconds), or disabled capture; passive network path monitoring continues. Connection time includes DNS/setup; it is **not** media RTT, jitter, or packet-loss telemetry. No audio is transmitted.
- Opt-in Core Audio Process Tap output analysis: all app output (excluding Sonoskope), or one selected process. Private, unmuted aggregate capture; no custom driver and no audio rerouting.
- Opt-in automatic microphone levels: capture follows input devices actively used by other apps and stops after they release the input. Sonoskope excludes its own activity, remembers the opt-in, and suspends capture during pause, sleep, and demos. The bounded 10-second manual test remains available when automatic monitoring is off. No raw recordings are saved.
- Input curves label the apps using the microphone, including concurrent users; historical selection preserves the original labels. These are shared-device usage labels, not separate app volumes.
- Explicit current input/default output device names. Built-in Mac microphones and speakers, USB devices and headsets use the same monitoring paths.
- Conservative near-full-scale and short-gap heuristics with repeated-evidence gating. These are candidates, not a validated speech-quality model.
- Native last-60-second sound-level and TCP probe charts, with missing readings left blank and failures marked separately. Levels are not quality scores.
- Two native windows (status/settings), silent native notifications, incident evidence, recovery tracking, bounded local history and JSON export.
- Seven isolated demo scenarios that pause live collectors and never send notifications or persist demo history.

## Automatic microphone levels

In Settings, enable **Automatically monitor microphone levels** and grant microphone permission. While another app uses an input device, the status window shows live dBFS and a purple input trace. With two-second polling and a two-second idle grace, capture normally stops about 2–4 seconds after the other app releases input.

This follows system input IO, not speech or a meeting's mute button. A muted meeting may keep its input stream active. The observed device can differ from the system default. When several devices are active, Sonoskope keeps its current active device or chooses the active system default; otherwise it waits rather than guessing. Unknown usage stops capture. Opening the microphone may affect Bluetooth mode.

## Permissions and defaults

Device/path monitoring starts automatically. Lightweight network probes default on and can be disabled. Output audio capture, Bluetooth signal access, notifications and microphone capture are opt-in. The system may prompt when enabling each capability. Allow audio capture in System Settings if required, then retry. Silent or absent callback data must not be interpreted as proof of a healthy audio path.

Login startup is optional via ServiceManagement. For a durable login item, install the app in a stable location first. Notifications obey macOS notification permissions and Focus; status remains available from the menu bar.

## Diagnostic limits

- A local microphone stream is not the meeting app's processed/encoded outgoing stream.
- Process output PCM is not the headset's acoustic output or proof of what the other participant heard.
- Natural pauses, noise suppression and content can resemble gaps. Silence alone never creates an incident.
- Network probes test a different connection/path. Correlation does not establish causation or separate uplink/downlink loss.
- RSSI is optional, does not measure Bluetooth retransmissions, and is not mapped to directional audio quality.
- The device collector polls; it can miss very brief disconnect/reconnect cycles.
- Microphone monitoring and tests can affect Bluetooth mode. Actual headset behavior still requires device testing.
- A selected process that exits must be selected again. Browser tabs/helper processes may not map cleanly to a meeting.

## Data

Only diagnostic events/metrics are retained, never raw audio. Up to 100 incidents are stored in `~/Library/Application Support/Sonoskope/incidents.json`, with session-only / 24-hour / 7-day options. In-memory event history is bounded. Exports may include device and application identifiers and timestamps; review before sharing. Simulation does not touch live history.

## Verification

```sh
swift test
bash scripts/build-app.sh
./dist/Sonoskope.app/Contents/MacOS/Sonoskope --smoke-test
bash scripts/render-check.sh
open -n dist/Sonoskope.app --args --demo correlated
```

The smoke mode uses real device/process/path/probe APIs, leaves microphone and output capture disabled, and does not write live incident history. Simulation uses the same diagnostic engine but does not validate physical Bluetooth or actual end-to-end speech quality.

- [Product contract](docs/product.md)
- [Test plan and fault injection](docs/test-plan.md)
- [Validation record and remaining acceptance checks](docs/validation.md)
- [Architecture](docs/architecture.md)

## Release workflow

Push an annotated semantic version tag after updating the bundle version and English release notes. GitHub Actions tests/builds both architectures and publishes a prerelease only after both architectures pass package and checksum verification. See [release automation](docs/releasing.md).

## Source layout

- `Sources/SonoskopeCore`: deterministic diagnosis, PCM metrics, network summaries, scenario fixtures, localization resources.
- `Sources/Sonoskope`: native UI, collectors, permission flows, lifecycle, notifications, persistence.
- `Tests/SonoskopeCoreTests`: regression tests for evidence boundaries, automatic input policy, localization, and history migration.
- `Tests/SonoskopeTests`: application lifecycle tests with an injected microphone; they do not open real input devices.

No external package dependencies. No meeting-platform integrations or private APIs.
