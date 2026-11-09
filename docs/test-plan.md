# Test plan

## Ground truth

Maintain an independent timestamped fault log: source, direction, start/end, parameters, random seed, observed result. The detector must never read the injector's labels. Use known speech and silence fixtures for algorithm tests. Use a second endpoint to record received test speech for uplink checks. For headset acoustic output, use an external fixed microphone/coupler or explicitly mark the result as subjective; digital loopback alone does not establish acoustic quality.

## Three levels

1. Automated deterministic tests: PCM fixtures, event streams, alert rules, retention, unknown states.
2. Real local integration: device selection/disappearance, permission denial, collector startup/cleanup, sleep/wake, UI and native notifications.
3. Physical two-endpoint calls: fault injection into uplink/downlink separately; Bluetooth range/occlusion; microphone A/B; actual acoustic verification.

## Matrix

| Scenario | Injection | Expected result |
|---|---|---|
| Silence/natural pause | Silence, pauses >1 second, mute/unmute | No failure solely from silence |
| Short digital gap | 20/80/200/1000 ms omissions in known speech | Measure recall by duration; candidate only, not guaranteed classification |
| Repetition/clipping | Repeated chunks and saturated samples | Clipping candidates; repeat classifier remains deferred |
| Low input/noise | Lower signal amplitude; add noise; physical mic A/B | Show local input metrics; do not blame transport without evidence |
| Idle headset removal | Disconnect while no other app has audio I/O | Record device change, no active-call failure alert |
| Active hard disconnect | Disconnect/reconnect while playing or calling | One incident, bounded notifications, recovery on same device UID |
| Bluetooth soft degradation | Repeat fixed audio at increasing distances/occlusion | Compare valid RSSI, snapshots and acoustic result; allow unknown |
| Bluetooth mode change | Headset output-only → headset input/output → built-in mic | Format changes are evidence, not automatic failure |
| Up/down network impairment | Separate directions at controlled gateway | Probe and local PCM correlation; no unwarranted directional attribution |
| Probe-only impairment | Impair only probe target | No claim of broken call audio |
| Remote audio defect | Inject gap at remote source on otherwise healthy network | Local PCM may be suspicious; cannot identify remote root cause |
| Collector failure | Missing callback, timestamp jump, permission denial | Monitoring incomplete, never falsely healthy/confirmed headset damage |
| Sleep/wake | Sleep during capture, resume | Stop/recreate collectors and baselines; no synthetic reconnect storm |
| Notifications | Disabled/Focus/closed app window/recovered incident | No Focus bypass; manual status works; click selects original issue |
| Demo isolation | Cycle every scenario while live monitoring was enabled | No persisted fake incidents or real notifications; collectors stopped |
| Observer effect | Compare app off/passive/tap/mic-test modes | Quantify CPU and audio effects, especially Bluetooth mode changes |

## Network fault injection

Use a dedicated Linux router/bridge with `tc netem`, ensuring the actual endpoint traffic crosses it. Apply directions separately, not just both ways at once. Suggested test grids (not alert thresholds): added delay 50/150/400 ms; jitter 0/30/100 ms; random loss 0/1/3/10%; burst outage 200/1000/3000 ms. Store seed, exact rules and traffic classification; restore rules after each run. macOS Network Link Conditioner is an optional alternative where compatible, not an app dependency.

Reference: https://man7.org/linux/man-pages/man8/tc-netem.8.html

## Acceptance measurements

Report candidate recall and false positives per hour separately. Also report wrong-cause attribution, detection latency, duplicate notifications per incident, recovery behavior, CPU/energy and observer effect. A green unit test run is not a speech-quality accuracy claim. Exact thresholds require physical and real-call evidence before release claims.

## Hardware coverage

Start with built-in input/output, a USB headset, a Bluetooth headset and AirPods when available; include both headset microphone and built-in microphone configurations. Run oldest supported and current macOS separately. Current environment coverage is recorded in validation.md, not assumed.
