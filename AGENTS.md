# Sonoskope

Native macOS menu-bar audio diagnostics. SwiftPM; macOS 14.2+.

- Public system APIs only; no Zoom/Teams APIs and no private Bluetooth APIs.
- Distinguish observed events, suspected causes, unmeasured states, and collector failures.
- Never claim remote audio quality or actual headset acoustic output from local PCM.
- No microphone capture until the user explicitly starts a bounded test.
- Keep simulation isolated from live collectors, notifications, and persisted live incidents.
- Never save raw audio. Store bounded metrics and diagnostic events only.
- Run `swift test`, `bash scripts/build-app.sh`, and `git diff --check` before publishing.
- Native runtime permission and physical-device checks are separate from automated tests; report unverified checks honestly.
