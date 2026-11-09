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
7. No raw audio storage/upload; microphone access requires an explicit bounded test or opt-in automatic monitoring based on external input IO.
8. Simulations are isolated from live monitoring, history, and notifications.
9. No alerts for silence alone, isolated network risk, idle device removals, or ordinary format changes.
10. Notification clicks open the matching historical issue; current state and past incidents are distinct.

## v0.1 scope

Core Audio device/process snapshots, optional output Process Tap, optional Bluetooth RSSI, network path and TCP setup-time probe, automatic microphone levels plus a 10-second manual input test, evidence-based incidents, native windows, silent notifications, local retention/export, and deterministic simulations.

## Deferred capabilities

No trained speech-quality classifier, codec/radio retransmission telemetry, packet capture, endpoint-specific media statistics, automatic repair, virtual microphone routing, or remote/acoustic ground truth. Recent sound-level and network-probe charts are included following user feedback. A global hotkey and raw-waveform visualization are deferred; the menu bar is the manual entry point.

## Interface states

Monitoring; limited monitoring; suspected audio issue; confirmed local device disappearance; observation ended/device restored; paused; simulation. “Not measured” must remain distinct from “no anomalies detected.”

The status window has Overview, Trends and Issues sections. Overview shows current state, two direction summaries, Bluetooth/network context and the latest issue with one next step. Trends contains the full 60-second charts. Issues contains historical records and evidence; reading a record is not interrupted by a new live event. Notification clicks open the matching issue, including an explicit unavailable state if it has expired. Capture scope and detailed metrics are available from the information button.

First use has three optional steps: introduction to the menu-bar app, explicit monitoring choices, and a completion summary reflecting actual readings and permission states. Presenting, skipping or closing the guide never enables capture. Existing guide completion is respected after upgrading; the guide remains available from the menu.
