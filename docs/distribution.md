# Developer ID signing and notarization

The release scripts support two explicit modes:

- `preview` (default): local development/ad-hoc signing, unsigned installer containers, no notarization. Existing v0.1.6 downloads use this mode.
- `developer-id`: Developer ID signatures, hardened runtime, secure timestamps, microphone entitlement, Apple notarization, stapled tickets, and Gatekeeper assessments. Missing credentials or rejected/pending notarization stop the release. There is no fallback to a preview.

## Prepare this Mac

1. Sign in at [Apple Developer Account](https://developer.apple.com/account/). If Xcode reports **PLA Update available**, the Account Holder must personally review and accept the updated agreement before certificate access can resume. Check that the intended team's membership is active.
2. In Xcode Settings → Accounts → the team → Manage Certificates, create/import **Developer ID Application** and **Developer ID Installer**. Apple requires the Account Holder role to create these certificates. Apple Development and Apple Distribution are different certificate types and cannot replace them here.
3. If transferring existing certificates from another Mac, export the certificates **with their private keys** as a password-protected `.p12` from Keychain Access, then import it into this Mac. A downloaded `.cer` alone does not include the private key. Do not commit or share private keys/passwords in chat.
4. Create an app-specific password for your Apple Account and store it locally:

```sh
xcrun notarytool store-credentials "sonoskope-notary"
```

Follow the interactive prompts for Apple ID, Team ID and app-specific password. Successful validation stores the credentials in Keychain; the packaging scripts use only the profile name. The Team ID is listed in the developer account's membership details. Do not use your normal Apple Account password in build scripts.

Inspect available identity names without exporting their keys:

```sh
security find-identity -v
```

## When you are an Admin or team member

Ask the Account Holder to create the certificates in the developer website using CSRs generated on your Mac. Send only the two public certificate requests, one for Developer ID Application and one for Developer ID Installer. The holder returns the corresponding `.cer` files. Keep the matching private keys on your Mac; they are required when importing the issued certificates into Keychain. Do not create replacement keys after submitting the requests.

If the CSRs were generated with OpenSSL, importing the returned `.cer` alone is insufficient: also import the matching local private key (or create and import a password-protected `.p12` locally). Confirm that Keychain Access shows a private key under each certificate. Neither the holder's private keys nor their Apple Account password need to be shared.

## Build locally

Set the actual certificate names for your team, then package the version currently in `App/Info.plist`:

```sh
export SONOSKOPE_DISTRIBUTION=developer-id
export SONOSKOPE_APPLICATION_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export SONOSKOPE_INSTALLER_IDENTITY='Developer ID Installer: Your Name (TEAMID)'
export SONOSKOPE_NOTARY_PROFILE=sonoskope-notary
release_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' App/Info.plist)
bash scripts/package-release.sh "$release_version" "$(uname -m)"
```

If the signing keys or notary profile use a non-default keychain, set `SONOSKOPE_SIGNING_KEYCHAIN` or `SONOSKOPE_NOTARY_KEYCHAIN` to its path. Keychain must be unlocked. The script never exports signing keys.

The pipeline:

1. Builds and signs the app with hardened runtime, a secure timestamp and the audio-input entitlement. Verifies the signature, signing authority and entitlements.
2. Checks relocated-app resources and translations.
3. Submits a temporary app ZIP to Apple, requires `Accepted`, then staples and validates the app ticket and assesses the app with Gatekeeper.
4. Archives the stapled app as ZIP, puts it into a signed DMG, and creates a PKG signed with Developer ID Installer.
5. Notarizes and staples the DMG and PKG; validates their tickets/signatures and Gatekeeper assessments.
6. Checks both containers' payloads and creates checksums **after** signing and stapling.

Submission JSON is retained under `.local/notarization/`. If Apple times out, inspect the saved submission ID with `notarytool info` or `wait`, using the same keychain profile. Do not blindly resubmit an in-progress submission. Rejected submissions can be investigated with `notarytool log`.

## GitHub Actions (optional)

Local signing does not automatically make CI signing available. Configure these repository **variables** to enable public signing for tagged releases:

- `SONOSKOPE_DISTRIBUTION`: `developer-id`
- `SONOSKOPE_APPLICATION_IDENTITY`: complete certificate name
- `SONOSKOPE_INSTALLER_IDENTITY`: complete certificate name

Configure these encrypted repository **secrets** yourself if using CI:

- `SONOSKOPE_CERTIFICATES_P12`: single-line base64 of a `.p12` containing both Developer ID certificates and their private keys
- `SONOSKOPE_CERTIFICATES_PASSWORD`: export password
- `SONOSKOPE_NOTARY_KEY`: contents of an App Store Connect team API private key (`.p8`)
- `SONOSKOPE_NOTARY_KEY_ID`: its key ID
- `SONOSKOPE_NOTARY_ISSUER_ID`: its issuer ID

Each architecture gets an isolated temporary keychain on its hosted runner. CI imports the certificates, stores a notarytool profile, deletes the input key files, and cleans up the keychain even when packaging fails. Secrets are not used by pull-request checks. Without the distribution variable, release automation continues to create explicitly documented developer previews. Set it to `developer-id` before creating a tag intended for notarized distribution.

The published release remains marked as a prerelease while physical-device acceptance is incomplete. A notarized build does not establish audio-diagnostic accuracy. Do not overwrite v0.1.6 assets; use a new version/tag and describe the signing state of those actual assets accurately.

## Verification still required with real credentials

Mocked tests cover rejection, timeout, missing/wrong configuration and successful stapling control flow. They do not establish that Apple accepted the real app.

After a real accepted submission, download the published DMG on a separate Mac or clean user account and verify installation, first launch, permission denial/grant, microphone test, app-output analysis, updating an installed copy, and removal. Gatekeeper assessment on the build machine is useful evidence, but not a clean-machine acceptance test.

Sources: [Apple Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [access issues and updated agreements](https://developer.apple.com/help/account/access/resolving-access-issues).
