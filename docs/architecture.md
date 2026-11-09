# Architecture

`Core Audio / IOBluetooth / Network / AVAudioEngine → observations and metrics → DiagnosticEngine → status/history/notification`

## Separation

SonoskopeCore has no hardware or UI dependencies. DiagnosticEngine consumes timestamped observations, not fault-injection labels. AudioAnalyzer handles energy, clipping and near-digital-silence transitions. A short-gap heuristic alone is not a fault; the engine requires three same-source/same-direction observations within 30 seconds. A 120-second same-key notification cooldown and active-incident merging limit repeated reminders. These are provisional engineering rules, not measured product accuracy.

Native collectors live in the executable. Core Audio device/process properties are polled every two seconds. Process taps are private and unmuted; they do not replace the default playback route. Capture aggregates are destroyed on pause, demo, sleep and shutdown. Callbacks calculate metrics and bound UI updates to roughly four per second; PCM buffers never leave the callback as stored recordings.

`MonitorModel` owns observable UI state and collector lifetime. Capture generations reject stale callbacks. NetworkMonitor owns one TCP probe at a time and cancels its continuation on stop. Native notification callbacks select an incident UUID and open the same status window.

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
