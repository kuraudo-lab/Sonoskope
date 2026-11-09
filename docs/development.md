# Developing Sonoskope

Build, verify and package the native macOS app. For installation and everyday use, see the [README](../README.md).

## Run locally

Requires macOS 14.2+, Xcode 15.3+ / Swift 5.10+. Developed and checked on Apple Silicon; see [validation](validation.md) for the actual tested environment.

```sh
swift test
bash scripts/build-app.sh
open dist/Sonoskope.app
```

Open `Package.swift` in Xcode for editing. The build script assembles an actual `.app` bundle with permission descriptions, bundled translations, and local ad-hoc signing. `swift run` is not the supported permission-testing launch path. This is a developer build, not a notarized distribution. To use your signing identity, set `SONOSKOPE_SIGN_IDENTITY` when building; rebuilding an ad-hoc signed binary can invalidate prior privacy grants.

Left-click the menu-bar icon to open status; right-click for settings and quit. Closing a window leaves monitoring running.

For repeated local development builds, use a valid Apple signing certificate to avoid a new ad-hoc identity on each rebuild. `SONOSKOPE_SIGN_IDENTITY` takes precedence; alternatively, store the certificate name or fingerprint in the ignored `.local/signing-identity` file. This does not change CI signing or make a development certificate suitable for public distribution.

## Verification

```sh
swift test
bash scripts/build-app.sh
./dist/Sonoskope.app/Contents/MacOS/Sonoskope --smoke-test
bash scripts/render-check.sh
open -n dist/Sonoskope.app --args --demo correlated
```

The smoke mode uses real device/process/path/probe APIs, leaves microphone and output capture disabled, and does not write live incident history. Simulation uses the same diagnostic engine but does not validate physical Bluetooth or actual end-to-end speech quality.

- [Product contract](product.md)
- [Test plan and fault injection](test-plan.md)
- [Validation record and remaining acceptance checks](validation.md)
- [Architecture](architecture.md)

## Release workflow

Releases currently use local Developer ID signing and Apple notarization (`SONOSKOPE_RELEASE_SOURCE=local`). A version tag does not publish preview packages. See [release automation](releasing.md) and [software updates](updating.md).

## Source layout

- `Sources/SonoskopeCore`: deterministic diagnosis, PCM metrics, network summaries, scenario fixtures, localization resources.
- `Sources/Sonoskope`: native UI, collectors, permission flows, lifecycle, notifications, persistence.
- `Tests/SonoskopeCoreTests`: regression tests for evidence boundaries, automatic input policy, localization, and history migration.
- `Tests/SonoskopeTests`: application lifecycle tests with an injected microphone; they do not open real input devices.

Sparkle 2.10.1 is a checksum-pinned binary dependency for verified app installation. Its license is bundled as `Sparkle-LICENSE`. No meeting-platform integrations or private APIs.

## Product demo

See [Recording the product demo](demo-recording.md) for the isolated native presentation, automatic window recording, and README screenshot workflow.

## Distribution signing

See [Developer ID signing and notarization](distribution.md). Local preview builds keep their existing signing behavior. Public distribution requires explicit credentials and never falls back to a preview after failure.
