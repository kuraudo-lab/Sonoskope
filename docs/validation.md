# Validation record — 2026-11-09

## Observed locally

- Apple Silicon Mac; Xcode 27.0 beta / Swift 6.4 toolchain. The deployment target is macOS 14.2, not proof of execution on 14.2.
- 29 XCTest regression tests passed in a clean scratch build: audio metrics, silence/short gaps, timestamp discontinuity, source/direction isolation, correlation boundaries, incident deduplication/recovery, retention, RSSI sentinels, and missing-data chart segmentation.
- Release app built, ad-hoc signed and passed `codesign --verify --strict`.
- Bundled-app `--smoke-test` ran successfully against actual device/process/path/probe APIs. It found built-in and virtual audio devices, active audio processes and an available Wi-Fi path; the TCP test connection succeeded. Microphone and output capture were disabled during this smoke check.
- **User-confirmed runtime check:** after enabling output analysis and granting the macOS system-audio permission, the status window displayed dBFS values changing with played sound.
- Actual SwiftUI status views for seven isolated scenarios and settings rendered offscreen using `scripts/render-check.sh`. Sound/network chart layouts were visually inspected. This is view rendering, not automated desktop interaction.
- The native computer-use service failed to start twice, so automated clicking and notification-delivery verification were unavailable. No alternative desktop automation was used.

## Toolchain issue

One incremental XCTest run under the Xcode beta build engine failed to load its test bundle after a rebuild. A fresh scratch-directory build passed all tests. The test failure was not counted as a pass. Use `swift test --scratch-path .build/clean-check` if the beta incremental artifact issue recurs. CI checks the code independently on hosted macOS runners.

## Remaining acceptance checks

- Physical Bluetooth headset and AirPods signal degradation/disconnect testing; none was connected during the initial smoke check.
- Active microphone test on real hardware, observer effects and mode switching.
- Real two-endpoint Zoom/Teams calls, separate network impairment directions and headset acoustic output.
- Native notification delivery/click under allowed, denied and Focus states.
- Long-call false-positive/recall/energy measurements; heuristic thresholds are provisional.
- Execution on oldest supported macOS, login-startup persistence and signed/notarized distribution.

Download packages are developer previews, not a claim that these physical acceptance checks are complete. CI build status and published assets are available in GitHub Actions and Releases.

## v0.1.1 localization validation

- 36 tests passed, including seven new localization tests for preference order, fallback, catalog/format parity, interpolation, legacy history migration, and bilingual history rendering.
- The signed packaged app ran with `en-US`, `zh-Hans-CN`, `zh-Hant-TW`, and `ja-JP` preference overrides. Runtime status strings and bundle-resolved microphone permission descriptions matched English, Chinese, Chinese, and English respectively. No audio capture was enabled by these checks.
- Actual SwiftUI views rendered in both English and Chinese: seven isolated scenarios, charts, and settings. Status, settings, and charts were visually inspected for translation and wrapping. This was offscreen rendering, not desktop interaction.
- Both localizations and native permission resources were included in the release app and passed strict signature verification. No new physical audio or permission-dialog acceptance claims are made by this localization change.

## v0.1.2 packaging correction

Post-download checks caught a startup crash in the cloud-built v0.1.1 app: that SwiftPM accessor searched the app root and CI build directory instead of `Contents/Resources`. v0.1.1 was withdrawn to draft. Its passing local checks were not treated as proof of the downloaded app working.

The corrected lookup explicitly uses the installed resource bundle. Local regression tests still pass (36 tests). New packaging/CI checks relocate the signed app, launch it with four language preferences, verify translated text and native permission descriptions, and require the resource URL to remain inside the relocated app. Release uploads are gated on these checks for each architecture.

## v0.1.3 automatic input validation

- 63 automated tests passed: 47 core tests and 16 application lifecycle tests. The latter use an injected microphone, authorization provider and hardware snapshots and never start real audio capture.
- Covered observer exclusion, idle grace, non-default/concurrent inputs, unknown data, device/format changes, stale callbacks, permission races/revocation, retry backoff, pause, sleep/wake, demos and shutdown.
- English/Chinese automatic standby, active-input and settings views rendered using an injected microphone fixture and were visually inspected. These renderings are simulated data.
- Local release package built, signed and passed four relocated-app language/permission-description checks.
- The user initially reported no curve after authorization, then confirmed continuous input curves using Voice Memos. A passive Core Audio probe observed Voice Memos, Sound Settings and Sonoskope using the same AirPods input. No cause for the initial transient report was established.
- Physical automatic-stop timing, built-in microphone capture, Teams-specific behavior, non-default input and Bluetooth mode changes remain unverified; built-in device coverage is currently automated/fixture based.
- Application attribution is stored with each input metric, preserves historical labels, splits segments on changes, excludes Sonoskope and unrelated input devices, and falls back to process identifiers when necessary. Separate-input diagnostic sources prevent gaps from different microphones combining into one incident.

## v0.1.4 built-in microphone regression

- Reproduced the empty input chart on the real built-in MacBook Air microphone with the explicit ten-second capture path. The target was bound successfully (48 kHz, mono Float32), then a queued engine configuration notification arrived while `isRunning` was still true and the format was unchanged. Unconditional notification handling stopped capture before the first metric; the check returned zero input chart values.
- The fix checks engine state, device identity, format equality and device availability. The same physical check produced 35 valid input metrics, changing RMS values, and normal timed completion with capture stopped. This validates local built-in capture, not end-to-end meeting quality.
- 69 automated tests passed: 47 core and 22 application tests. Both the benign-notification regression and permission-status regression failed before their fixes.
- The user confirmed a separate missing-permission state after an ad-hoc rebuild. A local Apple Development signing identity now preserves identity across local rebuilds; this is not Developer ID distribution signing. No key is exported or committed. Missing permission is now prominent in the status UI.
- Temporary instrumentation recorded only state and numeric metrics and was removed from shipping code. The explicit `--microphone-check` path remains available for repeatable hardware checks and never runs during passive smoke tests or CI.
- The user then confirmed automatic capture with Voice Memos on the built-in microphone: the purple curve and application labels appeared, and monitoring returned to automatic standby after recording stopped. This is separate from the bounded developer check.

## v0.1.5 installers and shared branding

- 69 regression tests pass. The shared branded image replaces both hard-coded waveform locations; the status window was rendered and inspected with the packaged icon. The menu bar uses the same icon at 18 points, without template tinting.
- Local arm64 DMG mounts read-only with an Applications link. The PKG expands to a single Sonoskope.app payload, targets `/Applications`, disables relocation and has no installer scripts. Payload signatures, version, architecture and icon are checked, and both containers contain identical executable/icon bytes.
- Installation into the system Applications directory and clean-machine Gatekeeper acceptance are not claimed by payload inspection. Distributed app builds remain ad-hoc signed; DMG/PKG containers are unsigned and not notarized.
