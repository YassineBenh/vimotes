# Distribution

ViMotes is free and open source. Signed and notarized builds are published as GitHub
Release assets. The Sparkle appcast is hosted by GitHub Pages and points to the ZIP
attached to the corresponding GitHub Release.

Only Apple Silicon (`arm64`, M1 or later) builds are distributed. The bundle build
script explicitly selects this architecture and publication checks the archived binary.

No Apple credential or Sparkle private key is stored in the repository.

## Apple Signing and Notarization

Install a Developer ID Application certificate through Xcode's Accounts settings, then
confirm that its private key is available:

```sh
security find-identity -v -p codesigning
```

Create the notarization profile once with an app-specific password:

```sh
xcrun notarytool store-credentials vimotes-notary
```

Enter the Apple ID, team ID, and password at the interactive prompts. The password is
stored in the Keychain; do not put it in shell history or the repository.

## Sparkle Key

Generate the EdDSA key once with the Sparkle tool downloaded by SwiftPM:

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

Back up the private key in a secure off-machine location. The release scripts read it
from the Keychain account `ed25519` by default. Set `VIMOTES_SPARKLE_KEY_ACCOUNT` if
another account name was selected. The public key is safe to expose and must be
provided to the release command as `VIMOTES_SPARKLE_PUBLIC_KEY`.

## Prepare a Release

Start from a clean `main` branch. The version argument is the semantic version and
`CFBundleVersion` is incremented automatically.
An existing artifact directory is never overwritten: archive it elsewhere before
rebuilding the same version.

```sh
VIMOTES_SPARKLE_PUBLIC_KEY="YOUR_PUBLIC_KEY" ./scripts/release.sh 1.2.0
```

The script runs the tests, builds ViMotes, signs Sparkle from its nested helpers outward,
enables Hardened Runtime, verifies signatures, creates and archives dSYMs, notarizes and
staples the app and DMG, validates Gatekeeper, signs the Sparkle ZIP, generates the
appcast, and calculates SHA-256 checksums. Final files are written to
`release-artifacts/1.2.0/` and ignored by Git.

A `release-manifest.plist` records the exact Git source tree used for the build,
version, build number, architecture, Sparkle public key, and appcast checksum. The
source-tree hash includes the version bump but does not depend on the final commit
message. Changing any tracked source after preparation requires rebuilding the artifacts.

Test the DMG and app manually before publication. Confirm Accessibility onboarding,
Apple Notes input interception, relaunch behavior, and a manual update check. Commit the
`Info.plist` version bump only after these checks.

## Publish a Release

From a clean `main` containing the committed version bump:

```sh
./scripts/publish-release.sh 1.2.0
```

After one confirmation, the script verifies checksums, notarization, the source tree,
archived bundle metadata, and appcast target. It pushes the version tag and creates a
draft GitHub Release containing the DMG, Sparkle ZIP, manifest, and checksums. After
uploading assets and pushing the appcast to `gh-pages`, it marks the release published.

If publication fails, rerun the same command from the same commit with the same
artifacts. Existing tags and identical assets are reused, missing assets are uploaded,
and a differing asset or newer appcast aborts publication. Existing assets are never
overwritten. The script does not change repository visibility or enable GitHub Pages.
Do not invoke it until publication is explicitly intended, even for a private repository.

Configure GitHub Pages once to deploy the `gh-pages` branch root. The appcast will be
available at `https://yassinebenh.github.io/vimotes/appcast.xml` after the repository is
public and Pages is enabled.

Private-repository release downloads are not anonymously accessible to Sparkle. Until
the repository and appcast are publicly accessible, validate updates using a separate
local test feed and expect checks against the production URL to fail.

Keep each version's ZIP, DMG, manifest, appcast, dSYM archive, and checksums in an
off-machine backup. dSYMs and `DSYM-SHA256SUMS` stay in the maintainer backup and are
not uploaded by the publication script.

## Build Path Privacy

Release-configuration builds generate a separate `ViMotes.app.dSYM` beside the app,
then remove debugging symbols from the distributed executable with `strip -S` before
signing. The build verifies that the dSYM and executable UUIDs still match and rejects
executables containing the build root or common local home and temporary paths.
Publication repeats the executable path check on the archived app.

Keep dSYMs private: they retain source paths for crash symbolication. Debug-configuration
builds are not stripped. This cleanup does not remove the public Developer ID name or
team identifier from the signing certificate, and it does not modify existing releases.
