# Distribution

ViMotes is free and open source. Signed and notarized builds are published as GitHub
Release assets. The Sparkle appcast is hosted by GitHub Pages and points to the ZIP
attached to the corresponding GitHub Release.

No Apple credential or Sparkle private key is stored in the repository.

## Apple Signing and Notarization

Install a Developer ID Application certificate through Xcode's Accounts settings, then
confirm that its private key is available:

```sh
security find-identity -v -p codesigning
```

Create the notarization profile once with an app-specific password:

```sh
xcrun notarytool store-credentials vimotes-notary \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

The password is stored in the Keychain and must never be added to the repository.

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

```sh
VIMOTES_SPARKLE_PUBLIC_KEY="YOUR_PUBLIC_KEY" ./scripts/release.sh 1.2.0
```

The script runs the tests, builds ViMotes, signs Sparkle from its nested helpers outward,
enables Hardened Runtime, verifies signatures, creates and archives dSYMs, notarizes and
staples the app and DMG, validates Gatekeeper, signs the Sparkle ZIP, generates the
appcast, and calculates SHA-256 checksums. Final files are written to
`release-artifacts/1.2.0/` and ignored by Git.

Test the DMG and app manually before publication. Confirm Accessibility onboarding,
Apple Notes input interception, relaunch behavior, and a manual update check. Commit the
`Info.plist` version bump only after these checks.

## Publish a Release

From a clean `main` containing the committed version bump:

```sh
./scripts/publish-release.sh 1.2.0
```

After one confirmation, the script verifies checksums and notarization, pushes the
version tag, creates a GitHub Release containing the DMG, Sparkle ZIP, and checksums, then
publishes the new appcast to the `gh-pages` branch.

Configure GitHub Pages once to deploy the `gh-pages` branch root. The appcast will be
available at `https://yassinebenh.github.io/vimotes/appcast.xml` after the repository is
public and Pages is enabled.

Keep each version's ZIP, DMG, dSYM archive, and checksums in an off-machine backup.
