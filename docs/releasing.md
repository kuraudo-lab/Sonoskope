# Release automation

The `Release` workflow runs on a pushed semantic version tag (for example `v0.1.0`), or a manual dispatch selecting an existing version tag. It does not publish from `main`. When `SONOSKOPE_RELEASE_SOURCE=local`, tag-based release jobs are skipped; notarized packages are built and published from the signing Mac as described in [distribution setup](distribution.md).

1. Update `App/Info.plist`'s short version and create English release notes in `docs/releases/<version>.md`.
2. Run tests, build, and runtime acceptance checks. Commit the result.
3. Push the commit and an annotated `v<version>` tag.
4. GitHub Actions tests and builds on `macos-15` (arm64) and `macos-15-intel` (x86_64), checks version, actual Mach-O architecture and relocated-app localization startup, creates DMG, PKG and ZIP assets with SHA-256 hashes. Each DMG is mounted read-only and each PKG is expanded to verify matching signed payloads, architecture, version, icon, the fixed `/Applications` target and absence of relocation/install scripts.
5. A separate job with `contents: write` verifies all six assets, creates a draft prerelease, uploads the DMGs, PKGs and ZIPs and `SHA256SUMS`, then publishes it. Partial build failures cannot publish a release. Published assets are not overwritten by reruns.

No long-lived GitHub token or signing private key is stored in the repository. The workflow uses its short-lived GitHub token. The default `preview` mode uses development/ad-hoc app signing and unsigned, unnotarized containers. The explicit `developer-id` mode signs and notarizes the app and containers, staples tickets and requires Gatekeeper acceptance before generating checksums. See [Developer ID setup](distribution.md) for local credentials and GitHub Actions variables/secrets. An Apple Development identity is not a substitute for Developer ID. Keep release notes consistent with the mode actually used.

Manual local package: `bash scripts/package-release.sh 0.1.5 arm64` (run on the corresponding architecture).

Runner labels verified against https://docs.github.com/en/actions/reference/runners/github-hosted-runners . Private-repository artifacts/releases inherit repository access.

The PKG has one app payload, no pre/postinstall scripts and no launch services or daemons. Relocation is disabled so an upgrade cannot silently update a workspace checkout instead of `/Applications`. Existing app contents are replaced atomically, with version and bundle-identifier checks. Users should quit the old app before installing. DMGs include an Applications symlink and bilingual installation instructions.
