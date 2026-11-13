# Monitoring reference

Details behind the user-facing overview in the [README](../README.md).

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

## Language

Starting with v0.1.2, the interface follows the macOS preferred-language order and supports English and Chinese. The first supported preference is used; if none is supported, it falls back to English. Chinese regional/script variants share the Simplified Chinese translation. Restart Sonoskope after changing system or app language.

Menus, settings, charts, notifications, permission descriptions, and diagnostics are localized. Incident history stores message keys and parameters and can be displayed in either language. Known v0.1.0 messages migrate on read; device/app names, system errors, and unknown historical text retain their original wording. The original v0.1.0 download remains unchanged.

## Pause after sustained output silence

Settings → Capture scope → Automatically pause after output silence defaults to
5 minutes, accepts 1–60 minutes, and can be disabled. The preference is retained
across launches. Only continuous, fresh output PCM metric windows with both RMS
and peak at or below −100 dBFS count; 0 dBFS is full scale, not silence. This does
not measure the system volume control or actual headset acoustic output.

When the measured silence reaches the configured duration, all monitoring pauses:
output capture, microphone capture, hardware polling and network probes stop.
The status explains why it paused. Choose Resume monitoring to restart; audio
cannot trigger automatic resumption while capture is stopped. The existing
monitoring opt-ins are retained, and this pause applies to the current run.

Sound, invalid/stale/discontinuous data, a callback gap over two seconds, a scope
change, capture restart, pause, sleep or entering demo mode resets the timer.
Missing data is never counted as silence. Demo readings do not trigger a live
pause, and the timeout setting is disabled during demos. Tests simulate the
threshold and lifecycle without recording audio; physical runtime acceptance
remains separate.

## Resident windows and optional floating monitor

Closing a main window hides it; monitoring and the menu-bar item remain alive.
After opening a main window, the Dock icon also remains available. Clicking it or
the menu-bar icon reopens status. Use Quit Sonoskope to terminate the application.

The floating monitor is off by default and has a saved toggle in Settings. It
reuses existing input/output and network metrics, without enabling collectors,
requesting permissions or adding probes. Fresh input OR output above −100 dBFS
(RMS or peak) shows a nonactivating floating panel. It hides after five minutes
without measured activity; missing/invalid readings hide it separately, without
claiming silence. Pause, sleep and demo mode hide it immediately. Closing its ×
hides it for the current run without changing the saved preference or pausing
monitoring. Settings offers Show floating monitor again. After relaunch, the saved
opt-in is restored and fresh audio activity can show the panel again.

The panel's five-minute hide timeout is independent of the configurable output
silence auto-pause. If all monitoring auto-pauses, resume manually before new
activity can show the panel again. Visible charts refresh at 1 Hz; hidden charts
are not rebuilt. AppKit close/reopen and visibility policies have regression tests;
real-device operation across Spaces/fullscreen and permission flows still need
native acceptance checks.

The floating panel is borderless and 420 × 350 points. Its own Close button hides
it for this run; Pause stops all monitoring and hides the panel (resume from
the main window). Background opacity is adjustable from 40–100%, defaults to 90%,
and is persisted separately from visibility. Text, controls and curves stay opaque.

It initially docks 18 points inside the upper-right corner of the active display's visible
frame. Frontmost-app window geometry chooses the display with the largest overlap;
if unavailable, it falls back to the pointer display. Geometry is read once on a
background executor, without screen images or Accessibility permission. Drag the
header to move the panel; refreshes and hiding/showing the retained panel preserve
its position. A late geometry result cannot override a user move.

The panel uses the normal window level by default. Settings offers a separate,
persisted Keep floating monitor on top toggle that applies immediately. It belongs
to the desktop where it first appears, without joining all Spaces or following
desktop switches. Synthetic tests cover display geometry, window configuration,
position preservation and the saved level preference. Physical dragging, Spaces
switching and compositing over third-party applications still need runtime acceptance.

Persistence verification: `bash scripts/check-floating-preferences.sh` builds an
isolated fixture app (no collectors or production incident writes), then starts
separate processes to verify enable → quit → relaunch, enable → close panel → quit
→ relaunch, and explicit disable → quit → relaunch. It uses a disposable defaults
domain and removes it afterward. Existing preferences already saved as disabled
are not automatically enabled; enable the setting once to choose that behavior.
