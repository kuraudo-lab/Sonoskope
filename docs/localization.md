# Localization

Sonoskope supports English (`en`) and Chinese (`zh-Hans`). `AppLanguage.resolve` uses the first supported entry in `Locale.preferredLanguages`; all `zh` regional/script variants use Simplified Chinese, and an entirely unsupported list falls back to English. Restart after changing the system/app language. Date labels use the selected interface language.

## Resources and usage

- Shared strings live in `Sources/SonoskopeCore/Resources/{en,zh-Hans}.lproj/Localizable.strings`. The original Chinese source strings serve as stable message keys.
- UI code uses `L10n.tr("…")`. Interpolated strings collect values separately from the translation template, preserving device/app names without treating their contents as format specifiers.
- Diagnostic fields use `LocalizedText`, resolving to `.localized` only at display time. Store keys and arguments, not the result of `L10n.tr`.
- OS/third-party error descriptions use `LocalizedText(verbatim:)`; Sonoskope does not translate arbitrary external text.
- `App/{en,zh-Hans,zh-Hant}.lproj/InfoPlist.strings` supplies native permission descriptions. The two Chinese directories intentionally share the same translation. English is the bundle development language.
- Build and rendering scripts copy the SwiftPM resource bundle and the native InfoPlist localizations into the signed app.
- Bluetooth device detection uses the transport type, not its translated display label.

## History compatibility

`LocalizedText` decodes the plain strings from v0.1.0. Known static text and interpolated templates are recovered; unknown strings are preserved verbatim. New history/export fields contain `{key, arguments, verbatim}` objects. This structured format requires v0.1.1 or later; the v0.1.0 app cannot read new history files.

## Installed resource lookup

`L10n` explicitly opens the resource bundle in the app's `Contents/Resources` directory. SwiftPM's generated `Bundle.module` accessor differs across Xcode/SwiftPM toolchains and is used only as a development/test fallback. The withdrawn v0.1.1 cloud build exposed this difference during download validation.

`bash scripts/check-app-localizations.sh` relocates the signed app to a temporary directory, launches its noninteractive `--localization-check` mode for four language preferences, and asserts the resolved resource path is inside that app. Both CI and release packaging run this check before artifacts are uploaded.

## Verification

`swift test` covers language order/fallback, catalog and format-specifier parity, interpolation preservation, legacy history decoding, history round trips, and English demo diagnostics. `bash scripts/render-check.sh` renders the actual views separately with `-AppleLanguages '(en)'` and `-AppleLanguages '(zh-Hans)'`, without changing system preferences.

The bundled `--smoke-test` reports the selected language, status title, and resolved microphone permission description without starting microphone or output capture. For example:

```sh
./dist/Sonoskope.app/Contents/MacOS/Sonoskope --smoke-test -AppleLanguages '(ja-JP)'
```

The example must select English. Explicit language arguments are per-process test overrides, not persisted preferences. Permission description checks do not prove that an actual system permission dialog was displayed.
