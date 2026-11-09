# Software updates

Sonoskope 0.2.0 checks for updates at launch and then at most once every 24 hours while running. The setting **Automatically check for and download updates** is on by default and can be disabled. Manual checking is available from Settings and the menu-bar menu. Checks contact GitHub; no diagnostic events or audio are uploaded, and Sparkle system profiling is disabled.

An available archive downloads in the background and is verified before **Update ready** appears. **Install and Relaunch** is the only action that starts installation. Closing a window or quitting normally does not install. During demo/diagnostic modes, updates are suspended or not started. Live collectors stop before a user-approved replacement/relaunch; a manual microphone test never automatically restarts.

Versions before 0.2.0 have no updater. Install 0.2.0 manually once; subsequent versions can use the in-app flow. Install into Applications before updating, rather than running from the mounted DMG. This remains a preview release channel while physical-device acceptance grows.

## Installation contract

- Sparkle 2.10.1 is pinned by the official binary archive's SHA-256 checksum. Packaging embeds the framework, signs its nested installer/XPC helpers inside-out, and includes its license.
- Sparkle automatic checking/downloading are disabled. Our daily schedule uses `checkForUpdateInformation`, which cannot arm an installer. The separate downloader verifies the exact length and Ed25519 signature with CryptoKit against the bundled public key. One verified archive is retained in the application cache; raw audio is never stored there.
- Consent is bound to the exact version, URL, signature and length. A changed candidate discovered during installation is rejected. Sparkle also applies its normal version and supported-system checks.
- Only after consent, a temporary listener bound to `127.0.0.1` serves the archive at a random URL to Sparkle. It accepts only the matching GET path, limits request bytes/connections, and stops when installation finishes or fails. No listener exists during background checks/downloads. Sparkle independently verifies EdDSA and Developer ID signatures before installation. This bridge avoids redownloading the archive without arming Sparkle's install-on-quit behavior early.
- Download URLs require HTTPS; local HTTP is accepted only by the dedicated disposable integration-test bundle. The production feed uses a separate, fixed URL for each architecture. Payloads are signed, notarized ZIPs on immutable GitHub release URLs.
- Signing uses the Keychain account `lab.kuraudo.Sonoskope`; `SUPublicEDKey` contains only the public key. Keep a secure recovery backup of the signing key via normal Keychain practices. Never commit or send the private key in chat.

## Verification

`swift test` covers corruption, wrong-key/size rejection, exact consent and the real cache-download transport. To run installation end-to-end on the signing Mac:

```sh
export SONOSKOPE_APPLICATION_IDENTITY='Developer ID Application: Your Name (TEAMID)'
bash scripts/check-updater.sh
```

This compiles the production updater into disposable old/new apps under `.local/update-integration`, using a separate bundle identifier and no collectors. It checks bad-signature rejection, ordinary quit without installation, cached installation with the original archive unavailable, relaunch and the up-to-date state. Its private HTTP feed exception cannot activate in the distributed app. Results are recorded in [validation](validation.md); clean-machine installation and physical-device behavior require separate checks.

Upstream behavior: [Sparkle documentation](https://sparkle-project.org/documentation/), [SPUUserDriver contract](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SPUUserDriver.h). In particular, invoking the standard downloaded-update installation flow before user consent would permit install-on-quit, which is why predownload is separate.
