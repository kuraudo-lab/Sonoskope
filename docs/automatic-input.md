# Automatic microphone levels

Automatic monitoring is off by default. Enabling it remembers the preference and requests microphone permission. On later launches, authorized monitoring can resume when another app uses input; missing permission is shown without silently prompting in the background. Turning the setting off stops capture immediately.

## Decision contract

- Read per-process `kAudioProcessPropertyIsRunningInput` and the input-scope `kAudioProcessPropertyDevices`. Poll every two seconds; do not infer input usage from device-global running status, which would include Sonoskope's capture.
- Exclude Sonoskope's own PID and other instances with the same bundle ID. Own capture must never start or sustain automatic monitoring.
- Use a sole known active input even when it differs from the system default. For multiple active inputs, retain the current active target or prefer the active default. Otherwise show ambiguity and do not capture.
- Treat failed process/property reads as unknown. No fallback to capturing an unproven default microphone.
- When external input stops, retain capture for a two-second grace. With polling, expected physical stop latency is about 2–4 seconds. A device disappearance, unknown usage, permission loss, explicit disable, pause, sleep or demo stops immediately upon observation.
- Resume after pause, sleep or demo only from fresh external input evidence. A manual test is available when automatic mode is off and ends after ten seconds.
- Speech pauses do not stop capture. A meeting's mute button may leave input IO active. This is not meeting mute-state telemetry.
- Never save/upload raw PCM. Live metrics describe local capture, not the processed uplink or remote listening experience.

## Device display and application labels

The status window names the input being captured (or the system default input when idle) and system default output, with transport labels. Apps may override the system default output; the label does not assert all playback uses that route. No Bluetooth-only filter is applied: built-in and USB input devices are eligible too. Output levels come from the selected digital process tap regardless of whether playback uses built-in speakers or headphones.

Every input metric carries a snapshot of the external apps using that particular device. Display names are preferred, with bundle ID/PID fallbacks; Sonoskope and apps using different devices are excluded. Concurrent apps share a single microphone trace. Labels are usage associations, never per-app uplink PCM. Two-second polling limits temporal precision. App changes split chart segments and add transition markers; selecting history displays the labels captured then rather than today's app list. This metadata stays in the bounded in-memory chart history.

## Regression and acceptance checks

Core tests cover external vs. own input, idle grace/cancellation, non-default selection, concurrent devices, missing data, disconnect/format changes, permission and suspension. Application tests cover asynchronous authorization cancellation, late callback rejection, retries, manual/automatic exclusion, pause/resume, sleep/wake, demos and shutdown using an injected microphone.

Hardware acceptance requires:

1. Enable automatic monitoring and authorize microphone access. An idle system must remain on standby without Sonoskope opening input.
2. Start microphone input in Teams/Zoom test settings or another audio app. Confirm live levels and the displayed device match the actual input, including a non-default device.
3. Release the input. Confirm Sonoskope closes capture after the grace period, despite having used the mic itself. A meeting that merely mutes but keeps input IO active is not expected to stop monitoring.
4. Repeat with the built-in microphone/speakers as well as headphones. Check device names, concurrent application labels and historical chart selection.
5. Repeat with simultaneous input apps, permission denial, sleep/wake, unplug/reconnect, and Bluetooth mode changes. Check that failures are shown as unavailable, not healthy audio.

Automated tests and offscreen render fixtures do not substitute for these physical checks.

## Sources

- [Core Audio input activity property](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertyisrunninginput)
- [AVAudioEngine input node](https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode)
- [Apple TN2091: device input with the HAL output audio unit](https://developer.apple.com/library/archive/technotes/tn2091/_index.html)

The installed Core Audio SDK header defines the process device property's input/output scope behavior. The collector preserves unavailable reads rather than guessing on systems that cannot supply an association.

## Engine notifications and hardware check

Binding input can queue an `AVAudioEngineConfigurationChange` notification that arrives after `start()` succeeds. A notification alone is not proof that capture is invalid. The collector keeps capture only when the engine is still running, the selected device remains alive and bound, and its format is unchanged. An unreadable or changed state stops capture; the existing automatic policy/backoff handles a subsequent restart.

For an explicit physical check, run the packaged app with `--microphone-check`. This requests microphone permission, captures the default input for at most ten seconds and exits after reporting the metric count and completion status. It does not save PCM or modify monitoring preferences. Do not add this command to unattended CI. `--smoke-test` remains passive.
