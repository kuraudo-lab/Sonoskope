# Architecture

`Core Audio / IOBluetooth / Network / AVAudioEngine → observations and metrics → DiagnosticEngine → status/history/notification`

## Separation

SonoskopeCore has no hardware or UI dependencies. DiagnosticEngine consumes timestamped observations, not fault-injection labels. AudioAnalyzer handles energy, clipping and near-digital-silence transitions. A short-gap heuristic alone is not a fault; the engine requires three same-source/same-direction observations within 30 seconds. A 120-second same-key notification cooldown and active-incident merging limit repeated reminders. These are provisional engineering rules, not measured product accuracy.

Native collectors live in the executable. Core Audio device/process properties are polled every two seconds. Process taps are private and unmuted; they do not replace the default playback route. Capture aggregates are destroyed on pause, demo, sleep and shutdown. Callbacks calculate metrics and bound UI updates to roughly four per second; PCM buffers never leave the callback as stored recordings.

`MonitorModel` owns observable UI state and collector lifetime. Capture generations reject stale callbacks. NetworkMonitor owns one TCP probe at a time and cancels its continuation on stop. Native notification callbacks select an incident UUID and open the same status window.

## Automatic microphone input

`AutomaticInputPolicy` selects an input device from observed external process input IO. It excludes the observer PID and Sonoskope bundle ID, maintains a two-second idle grace, and clears its target on suspension, permission loss, unknown input usage or ambiguity. A sole active input can be non-default; for concurrent inputs the policy keeps an existing active target, then prefers the active default, otherwise waits. Device identity and sample rate are part of the target so route/format changes restart capture with a new chart segment. Input diagnostic events use device-specific source identities. Each input chart metric retains the observed application names for its device; context changes split segments without restarting capture.

`MicrophoneCapture` uses an AVAudioEngine input tap, explicitly binds its audio unit to the selected Core Audio device and verifies the binding. It never changes the system default. Manual tests have a 10-second timer; automatic sessions do not. Engine configuration changes stop capture; active automatic sessions can retry after a backoff. Missing callbacks also stop capture and back off rather than display stale levels as live.

`MonitorModel` keeps the opt-in preference separate from running capture. Permission requests happen only on explicit enable/retry or manual test, never from the background poll. Callback generations guard permission/capture cancellation, pause, sleep, demo and device changes. Lifecycle tests inject a microphone and hardware snapshots; they do not prove physical microphone behavior. See [automatic input validation](automatic-input.md).

## Network terminology

TCP connection setup to `www.apple.com:443`, including DNS/setup, is measured with a monotonic clock. The recent 12-sample window reports timeouts and spread for that connection only. No payload audio is uploaded. No claim of meeting RTT, one-way latency, packet loss or jitter is made.

## Storage

IncidentStore atomically stores up to 100 incidents, subject to retention. Raw PCM is never retained. Session-only storage deletes any prior persisted incident file. Historic unresolved observations are closed on reload rather than asserted to be currently active. UI and export retain uncertainty.

## APIs

- [Core Audio process taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
- [Core Audio process information](https://developer.apple.com/documentation/coreaudio/audiohardwareprocess)
- [IOBluetooth RSSI availability](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/rawrssi%28%29)
- [NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor)
- [Native notifications and authorization](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)

`interface-exploration.html` is the earlier conversation mockup fragment, retained for design provenance, not the shipped application.
