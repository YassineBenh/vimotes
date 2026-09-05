#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
VERSION="${1:-}"
INFO_PLIST="$ROOT_DIR/App/Info.plist"
NOTARY_PROFILE="${VIMOTES_NOTARY_PROFILE:-vimotes-notary}"
SPARKLE_ACCOUNT="${VIMOTES_SPARKLE_KEY_ACCOUNT:-ed25519}"
SPARKLE_TOOLS="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "usage: $0 <major.minor.patch>" >&2
  exit 64
fi

cd "$ROOT_DIR"
if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "error: releases must be prepared from main" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: the repository must be clean" >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "error: tag v$VERSION already exists" >&2
  exit 1
fi

: "${VIMOTES_SPARKLE_PUBLIC_KEY:?VIMOTES_SPARKLE_PUBLIC_KEY is required}"

IDENTITY="${VIMOTES_CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning \
    | sed -nE 's/^[[:space:]]*[0-9]+\) [A-F0-9]+ "(Developer ID Application:.*)"$/\1/p' \
    | head -n 1)
fi
if [[ -z "$IDENTITY" ]]; then
  echo "error: no Developer ID Application identity found" >&2
  exit 1
fi
if [[ "$IDENTITY" == "Developer ID Application:"* ]] \
  && ! security find-certificate -c "$IDENTITY" -p \
    | openssl x509 -checkend 0 -noout >/dev/null 2>&1; then
  echo "error: the selected Developer ID Application certificate is expired" >&2
  exit 1
fi

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null
if [[ ! -x "$SPARKLE_TOOLS/generate_appcast" ]]; then
  swift package resolve
fi

BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
BUILD_NUMBER=$((BUILD_NUMBER + 1))
ARTIFACT_DIR="$ROOT_DIR/release-artifacts/$VERSION"
APP_PATH="$ROOT_DIR/dist/ViMotes.app"
ZIP_PATH="$ARTIFACT_DIR/ViMotes-$VERSION.zip"
DMG_PATH="$ARTIFACT_DIR/ViMotes-$VERSION.dmg"
PAGES_DIR="$ARTIFACT_DIR/pages"
APPCAST_INPUT_DIR="$ARTIFACT_DIR/appcast-input"
DMG_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/vimotes-dmg.XXXXXX")
NOTARY_ZIP=$(mktemp "${TMPDIR:-/tmp}/vimotes-notary.XXXXXX.zip")
trap 'rm -rf "$DMG_STAGE"; rm -f "$NOTARY_ZIP"' EXIT

echo "ViMotes $VERSION (build $BUILD_NUMBER)"
echo "Identity: $IDENTITY"
echo "Notary profile: $NOTARY_PROFILE"
echo "Artifacts: $ARTIFACT_DIR"
read "REPLY?Prepare this signed and notarized release? [y/N] "
if [[ "$REPLY" != [yY] ]]; then
  exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
swift test
VIMOTES_BUILD_CONFIGURATION=release \
VIMOTES_RELEASE_BUILD=1 \
VIMOTES_CODESIGN_IDENTITY="$IDENTITY" \
"$ROOT_DIR/scripts/build-app.sh"

codesign --verify --strict --verbose=2 \
  "$APP_PATH/Contents/Frameworks/Sparkle.framework"
codesign --verify --strict --verbose=2 "$APP_PATH"
rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR" "$PAGES_DIR" "$APPCAST_INPUT_DIR"
dsymutil "$APP_PATH/Contents/MacOS/ViMotes" \
  -o "$ARTIFACT_DIR/ViMotes-$VERSION.dSYM"
ditto -c -k --keepParent "$ARTIFACT_DIR/ViMotes-$VERSION.dSYM" \
  "$ARTIFACT_DIR/ViMotes-$VERSION.dSYM.zip"

ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
ditto "$APP_PATH" "$DMG_STAGE/ViMotes.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
  -volname "ViMotes" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
codesign --sign "$IDENTITY" --timestamp "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

cp "$ZIP_PATH" "$APPCAST_INPUT_DIR/"
"$SPARKLE_TOOLS/generate_appcast" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix \
  "https://github.com/YassineBenh/vimotes/releases/download/v$VERSION/" \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  -o "$PAGES_DIR/appcast.xml" \
  "$APPCAST_INPUT_DIR"

(
  cd "$ARTIFACT_DIR"
  shasum -a 256 "ViMotes-$VERSION.zip" "ViMotes-$VERSION.dmg" > SHA256SUMS
)
echo "$ARTIFACT_DIR"
