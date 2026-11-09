# Next experience — design checkpoint

Status: layout and three-step onboarding approved (LGTM). Native implementation is at the screenshot review checkpoint. Automatic updating remains the next implementation stage. Existing v0.1.7 notarization submissions and signed bundles remain separate.

## Confirmed by the user

- Improve first-use onboarding, implement in-app automatic updates, and simplify the main UI so essential information is visible without vertical scrolling.
- Pause at meaningful design decisions for feedback.
- Update policy: check and download in the background; install/relaunch only after an explicit click. Do not silently install on quit or force a restart.
- Approved layout: Overview / Trends / Issues, with full charts on Trends and no overview mini chart. Approved onboarding: three steps.

## Starting point before this change

- `GettingStartedView` already provides three action cards, plus skip/demo. It lacks a short sequential introduction to the menu-bar app, explicit setup progress and a completion state.
- `StatusView` stacks devices, both directions, connectivity, incident detail, two charts, history selection and diagnostic details in one ScrollView. The initial window is 520 × 740; charts are below the visible fold even in a simulated incident.
- `AppDelegate` creates separate status/settings/guide windows. Notifications select an incident before opening status; this must continue to open that exact historical record.
- There is no updater dependency, signed update feed or update UI yet. Local package signing is already available. Apple notarization for v0.1.7 remains an independent pending release task.

## Approved onboarding

1. Explain the menu-bar location, closing vs quitting, and marking an audio problem. Offer an isolated demo.
2. Choose monitoring capabilities. Passive device observation needs no audio capture. Output analysis and automatic microphone monitoring are off until explicitly enabled; request permission only at the corresponding action. Explain Bluetooth mode impact before microphone activation. Denied/unknown/error remain separate from successful authorization.
3. Show actual enabled/disabled/unavailable states, optional login startup, and enter overview. Display the selected update policy. All steps can be skipped or revisited. Completion/dismissal semantics must avoid endlessly showing the guide, without silently enabling capture.

The first-time flow is versioned so existing installations do not unexpectedly repeat permission prompts. A manual 10-second test remains an explicit, cancellable action outside required setup. Replay of onboarding reflects existing choices and never resets them.

## Approved main UI

- Aim for a default approximately 640 × 620 window, with readable native text. Confirm at real macOS scaling rather than shrinking fonts to fit. Permit resizing and accessibility overflow where necessary.
- Three sections: **Overview / Trends / Issues**. Settings stays separate, grouped by purpose.
- Overview: one current-status headline, two adjacent input/output summaries, compact device/connectivity context, one recent-issue summary and one next step. Persistent actions: mark problem, bounded mic test, pause/resume.
- Trends: the current 60-second sound-level and network charts; preserve missing-data gaps, time inspection, units and microphone app context. Optional overview mini trend is a feedback choice.
- Issues: a history list and selected evidence/details. Keep observed events, suspected causes, unmeasured states and collector failures distinct. Keep historical incidents separate from live state; notification clicks select Issues with the matching record.
- Longer scope explanations, raw metrics and export belong in relevant detail views/settings rather than repeated prose on the overview. Essential measurement limitations still remain visible near readings.
- Native review checkpoint: assess actual spacing, labels and first-use flow in both languages before updater integration.

## Automatic updating

Reference inspected: installed Keepresso 1.29.0 uses Sparkle and an EdDSA public key; its update feed points to GitHub Releases. Public implementation uses a standard Sparkle controller with a gentle update-available reminder. Reference behavior only; implement independently for Sonoskope.

- Use Sparkle 2 as the verified installation mechanism, with a thin observable service injected into AppDelegate/settings/menu UI.
- A simple `SUAutomaticallyUpdate=true` is insufficient: Sparkle's default includes automatic installation. The agreed policy requires an explicit user-driven install gate (appropriate delegate/user-driver behavior). Validate that closing/quitting while a download is ready cannot silently install it.
- Native menu/settings entry to check for updates. Quiet ready-to-install reminder instead of interrupting audio diagnosis. Show checking, downloading, ready, latest, failed and unavailable states.
- On explicit install, shut down collectors, preserve only already-authorized settings/history, then let Sparkle replace/relaunch. A manual mic test must not resume automatically. Persisted opt-in automatic monitoring continues under its existing external-input policy.
- Keep macOS 14.2+ and both CPU architectures. Publish architecture-specific feeds or equivalent verified selection so an Intel Mac can never receive an arm64-only package.
- Extend packaging for Sparkle framework/helper embedding, runpaths and nested code signing. Produce an EdDSA-signed update archive/feed only after Developer ID signing, notarization, stapling and verification. Private signing keys remain local.
- Use a deliberate stable/preview feed strategy; GitHub `releases/latest` alone is not a suitable feed for the current prerelease-only release history. Publish feed after immutable payloads are available and verified.
- Older versions with no updater require one manual installation of the first updater-enabled release.

Primary references:

- https://github.com/gyorgysh/keepresso/blob/main/Sources/Keepresso/Updater.swift
- https://sparkle-project.org/documentation/
- https://sparkle-project.org/documentation/customization/
- https://sparkle-project.org/documentation/programmatic-setup/

## Delivery checkpoints

1. Done: interactive UI/onboarding mockup approved.
2. Current: native UI and onboarding implemented; review real English/Chinese screenshots and permission states before updater integration.
3. Integrate updater and publishing support. Verify real signed old→new update, cancellation/failure and no-install-before-click on a disposable installed copy before public release.

## Acceptance

- Overview common states (passive/unmeasured, active, suspected, missing device, permission denied, paused, demo) fit at default size without vertical scrolling. Enlarged text remains readable rather than clipped. All functions remain reachable.
- First run alone never requests audio permissions. Skipping setup preserves off states. Enabled features reflect actual system authorization and collector results.
- Automatic download does not quit, replace or install before explicit user confirmation. Mismatched signatures, unavailable feeds, architecture/OS mismatches and network failures preserve the working installation.
- Test that the simulation/smoke/render paths do not start the real updater or installers, and keep live collectors isolated.
- Run `swift test`, `bash scripts/build-app.sh`, localization/render checks and `git diff --check`. Real update install/relaunch, macOS permissions and physical devices are separately recorded; mocks are not proof of those checks.

## Implementation and acceptance

The native UI checkpoint was approved. The updater now uses Sparkle 2.10.1 for installation and information-only discovery, with its automatic installation disabled. A separate verified predownload remains inert until explicit install consent; a temporary loopback-only cache bridge starts only after that click. Full details and remaining runtime limits are recorded in `updating.md` and `validation.md`. The previously prepared 0.1.7 binaries are superseded by the combined 0.2.0 release.
