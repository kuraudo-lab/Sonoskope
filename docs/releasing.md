# Release automation

The `Release` workflow runs on a pushed semantic version tag (for example `v0.1.0`), or a manual dispatch selecting an existing version tag. It does not publish from `main`.

1. Update `App/Info.plist`'s short version and create English release notes in `docs/releases/<version>.md`.
2. Run tests, build, and runtime acceptance checks. Commit the result.
3. Push the commit and an annotated `v<version>` tag.
4. GitHub Actions tests and builds on `macos-15` (arm64) and `macos-15-intel` (x86_64), checks version and actual Mach-O architecture, and uploads ZIPs with SHA-256 hashes.
5. A separate job with `contents: write` verifies both assets, creates a draft prerelease, uploads the ZIPs and `SHA256SUMS`, then publishes it. Partial build failures cannot publish a release. Published assets are not overwritten by reruns.

No long-lived GitHub token or signing private key is stored in the repository. The workflow uses its short-lived GitHub token. Current packages are ad-hoc signed and **not notarized**; this limitation is prominently shown in the release notes. Developer ID signing/notarization can be added once release credentials are explicitly configured. An Apple Development identity is not a substitute for a Developer ID distribution identity.

Manual local package: `bash scripts/package-release.sh 0.1.0 arm64` (run on the corresponding architecture).

Runner labels verified against https://docs.github.com/en/actions/reference/runners/github-hosted-runners . Private-repository artifacts/releases inherit repository access.
