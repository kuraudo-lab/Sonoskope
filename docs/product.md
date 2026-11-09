# Product contract

Name confirmed: **Sonoskope**, following the naming style of Teleskope.

## User intent

Locate which observable segment may be responsible when outgoing or incoming meeting audio sounds bad. Keep the surface minimal: settings, a nonintrusive issue notification, and one status/problem window reachable manually or from the notification.

## Invariants

1. Public macOS system APIs only; no Zoom/Teams integration.
2. Separate direct observations, heuristic suspicions, unknowns, and collector failures.
3. Do not equate system default input with a meeting app's selected microphone.
4. Do not label local PCM as what remote participants heard or what a headset physically emitted.
5. Network probe metrics do not describe the actual conference media flow.
6. Unsupported Bluetooth RSSI is unavailable, never a healthy reading.
7. No raw audio storage/upload; microphone access requires an explicit bounded test.
8. Simulations are isolated from live monitoring, history, and notifications.
9. No alerts for silence alone, isolated network risk, idle device removals, or ordinary format changes.
10. Notification clicks open the matching historical issue; current state and past incidents are distinct.

## v0.1 scope

Core Audio device/process snapshots, optional output Process Tap, optional Bluetooth RSSI, network path and TCP setup-time probe, 10-second microphone input test, evidence-based incidents, native windows, silent notifications, local retention/export, and deterministic simulations.

## Deferred capabilities

No trained speech-quality classifier, codec/radio retransmission telemetry, packet capture, endpoint-specific media statistics, automatic repair, virtual microphone routing, or remote/acoustic ground truth. Recent sound-level and network-probe charts are included following user feedback. A global hotkey and raw-waveform visualization are deferred; the menu bar is the manual entry point.

## Interface states

Monitoring; limited monitoring; suspected audio issue; confirmed local device disappearance; observation ended/device restored; paused; simulation. “Not measured” must remain distinct from “no anomalies detected.” Default status has two direction rows, a small Bluetooth/network summary, one selected incident, evidence disclosure and one next step.
