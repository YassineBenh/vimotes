#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/dist/ViMotes.app"
CONTENTS_DIR="$APP_DIR/Contents"
CONFIGURATION="${VIMOTES_BUILD_CONFIGURATION:-release}"
RELEASE_BUILD="${VIMOTES_RELEASE_BUILD:-0}"

cd "$ROOT_DIR"
if [[ "$RELEASE_BUILD" == "1" ]]; then
  swift build -c "$CONFIGURATION" -Xswiftc -g
else
  swift build -c "$CONFIGURATION"
fi

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$CONTENTS_DIR/Frameworks"
cp "$ROOT_DIR/.build/$CONFIGURATION/ViMotes" "$CONTENTS_DIR/MacOS/ViMotes"
cp "$ROOT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/App/Resources/ViMotes.icns" \
  "$CONTENTS_DIR/Resources/ViMotes.icns"
cp "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/LICENSE" \
  "$CONTENTS_DIR/Resources/Sparkle-LICENSE.txt"
ditto "$ROOT_DIR/.build/$CONFIGURATION/Sparkle.framework" \
  "$CONTENTS_DIR/Frameworks/Sparkle.framework"
if ! otool -l "$CONTENTS_DIR/MacOS/ViMotes" \
  | grep -Fq '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' \
    "$CONTENTS_DIR/MacOS/ViMotes"
fi

if [[ "$RELEASE_BUILD" == "1" ]]; then
  : "${VIMOTES_SPARKLE_PUBLIC_KEY:?VIMOTES_SPARKLE_PUBLIC_KEY is required}"
  /usr/libexec/PlistBuddy -c \
    "Set :SUPublicEDKey $VIMOTES_SPARKLE_PUBLIC_KEY" \
    "$CONTENTS_DIR/Info.plist"
fi

SIGNING_IDENTITY="${VIMOTES_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  if [[ "$RELEASE_BUILD" == "1" ]]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning \
      | sed -nE 's/^[[:space:]]*[0-9]+\) [A-F0-9]+ "(Developer ID Application:.*)"$/\1/p' \
      | head -n 1)
  else
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning \
      | sed -nE 's/^[[:space:]]*[0-9]+\) [A-F0-9]+ "(Apple Development:.*)"$/\1/p' \
      | head -n 1)
  fi
fi

if [[ "$SIGNING_IDENTITY" == "Apple Development:"* \
  || "$SIGNING_IDENTITY" == "Developer ID Application:"* ]]; then
  if ! security find-certificate -c "$SIGNING_IDENTITY" -p \
    | openssl x509 -checkend 0 -noout >/dev/null 2>&1; then
    if [[ "$RELEASE_BUILD" == "1" ]]; then
      echo "error: the selected Developer ID Application certificate is expired" >&2
      exit 1
    fi
    echo "warning: the available Apple Development certificate is expired; using an unstable ad hoc signature" >&2
    SIGNING_IDENTITY=""
  fi
fi

if [[ "$RELEASE_BUILD" == "1" && -z "$SIGNING_IDENTITY" ]]; then
  echo "error: no Developer ID Application identity found" >&2
  exit 1
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "warning: no valid Apple Development identity found; using an unstable ad hoc signature" >&2
  SIGNING_IDENTITY="-"
fi

SPARKLE_FRAMEWORK="$CONTENTS_DIR/Frameworks/Sparkle.framework"
if [[ "$RELEASE_BUILD" == "1" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    --preserve-metadata=entitlements \
    "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    "$SPARKLE_FRAMEWORK"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    "$APP_DIR"
  codesign --verify --strict --verbose=2 "$APP_DIR"
else
  codesign --force --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
  codesign --force --sign "$SIGNING_IDENTITY" --preserve-metadata=entitlements \
    "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
  codesign --force --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
  codesign --force --sign "$SIGNING_IDENTITY" "$SPARKLE_FRAMEWORK"
  codesign --force --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi
echo "$APP_DIR"
