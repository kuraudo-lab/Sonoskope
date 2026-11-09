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
