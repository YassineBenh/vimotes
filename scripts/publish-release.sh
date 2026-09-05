#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
source "$ROOT_DIR/scripts/lib/release-publication.sh"
source "$ROOT_DIR/scripts/lib/binary-distribution.sh"
VERSION="${1:-}"
TAG="v$VERSION"
ARTIFACT_DIR="$ROOT_DIR/release-artifacts/$VERSION"
PAYLOAD_DIR="$ARTIFACT_DIR/pages"
ZIP_PATH="$ARTIFACT_DIR/ViMotes-$VERSION.zip"
DMG_PATH="$ARTIFACT_DIR/ViMotes-$VERSION.dmg"
CHECKSUMS_PATH="$ARTIFACT_DIR/SHA256SUMS"
MANIFEST_PATH="$ARTIFACT_DIR/release-manifest.plist"

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "usage: $0 <major.minor.patch>" >&2
  exit 64
fi

cd "$ROOT_DIR"
if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "error: releases must be published from main" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: commit the version bump and use a clean repository before publishing" >&2
  exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)" != "$VERSION" ]]; then
  echo "error: App/Info.plist does not contain version $VERSION" >&2
  exit 1
fi
for artifact_path in "$ZIP_PATH" "$DMG_PATH" "$CHECKSUMS_PATH" "$MANIFEST_PATH" \
  "$PAYLOAD_DIR/appcast.xml"; do
  if [[ ! -e "$artifact_path" ]]; then
    echo "error: missing release artifact $artifact_path" >&2
    exit 1
  fi
done
if [[ "$(shasum -a 256 "$PAYLOAD_DIR/appcast.xml" | awk '{ print $1 }')" \
  != "$(/usr/libexec/PlistBuddy -c 'Print :appcastSHA256' "$MANIFEST_PATH")" ]]; then
  echo "error: appcast checksum does not match the release manifest" >&2
  exit 1
fi
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' App/Info.plist)
if ! vimotes_verify_manifest "$MANIFEST_PATH" "$(git rev-parse 'HEAD^{tree}')" \
  "$VERSION" "$BUILD_NUMBER"; then
  echo "error: release artifacts do not match the committed source tree, version, build, or architecture" >&2
  exit 1
fi
(
  cd "$ARTIFACT_DIR"
  shasum -a 256 -c SHA256SUMS
)
xcrun stapler validate "$DMG_PATH"
VALIDATION_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vimotes-publication.XXXXXX")
PAGES_WORKTREE=""
trap 'if [[ -n "$PAGES_WORKTREE" ]]; then git worktree remove --force "$PAGES_WORKTREE" >/dev/null 2>&1 || true; fi; rm -rf "$VALIDATION_DIR"' EXIT
ditto -x -k "$ZIP_PATH" "$VALIDATION_DIR"
ARCHIVED_APP="$VALIDATION_DIR/ViMotes.app"
ARCHIVED_INFO="$ARCHIVED_APP/Contents/Info.plist"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ARCHIVED_INFO")" != "$BUILD_NUMBER" \
  || "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ARCHIVED_INFO")" != "$VERSION" \
  || "$(lipo -archs "$ARCHIVED_APP/Contents/MacOS/ViMotes")" != 'arm64' \
  || "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ARCHIVED_INFO")" != "$(/usr/libexec/PlistBuddy -c 'Print :sparklePublicKey' "$MANIFEST_PATH")" ]]; then
  echo "error: archived application metadata does not match the release manifest" >&2
  exit 1
fi
codesign --verify --deep --strict "$ARCHIVED_APP"
vimotes_verify_binary_paths "$ARCHIVED_APP/Contents/MacOS/ViMotes" "$ROOT_DIR"
xcrun stapler validate "$ARCHIVED_APP"
FEED_BUILD=$(xmllint --xpath 'string(//*[local-name()="item"]/*[local-name()="version"])' "$PAYLOAD_DIR/appcast.xml")
FEED_URL=$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@url)' "$PAYLOAD_DIR/appcast.xml")
if [[ "$FEED_BUILD" != "$BUILD_NUMBER" \
  || "$FEED_URL" != "https://github.com/YassineBenh/vimotes/releases/download/$TAG/ViMotes-$VERSION.zip" ]]; then
  echo "error: appcast does not point to the expected build and archive" >&2
  exit 1
fi
if [[ "$(gh repo view --json nameWithOwner --jq .nameWithOwner)" != 'YassineBenh/vimotes' ]]; then
  echo "error: publication is only configured for YassineBenh/vimotes" >&2
  exit 1
fi

RELEASE_COMMIT=$(git rev-parse HEAD)
EXISTING_TAG_COMMIT=""
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  EXISTING_TAG_COMMIT=$(git rev-list -n 1 "$TAG")
fi
LOCAL_TAG_ACTION=$(vimotes_tag_action "$EXISTING_TAG_COMMIT" "$RELEASE_COMMIT")
if [[ "$LOCAL_TAG_ACTION" == "conflict" ]]; then
  echo "error: local $TAG points to another commit" >&2
  exit 1
fi

REMOTE_TAG_COMMIT=$(git ls-remote origin "refs/tags/$TAG^{}" | awk 'NR == 1 { print $1 }')
if [[ -z "$REMOTE_TAG_COMMIT" ]]; then
  REMOTE_TAG_COMMIT=$(git ls-remote origin "refs/tags/$TAG" | awk 'NR == 1 { print $1 }')
fi
REMOTE_TAG_ACTION=$(vimotes_tag_action "$REMOTE_TAG_COMMIT" "$RELEASE_COMMIT")
if [[ "$REMOTE_TAG_ACTION" == "conflict" ]]; then
  echo "error: remote $TAG points to another commit" >&2
  exit 1
fi

echo "Publish ViMotes $VERSION"
echo "GitHub Release assets: $DMG_PATH, $ZIP_PATH, $CHECKSUMS_PATH"
echo "Appcast: $PAYLOAD_DIR/appcast.xml"
echo "Tag: $TAG at $(git rev-parse --short HEAD)"
read "REPLY?Publish the GitHub Release and appcast? [y/N] "
if [[ "$REPLY" != [yY] ]]; then
  exit 0
fi

case "$LOCAL_TAG_ACTION" in
  skip)
    echo "$TAG already points to this commit"
    ;;
  create)
    git tag -a "$TAG" -m "ViMotes $VERSION"
    ;;
esac
if [[ "$REMOTE_TAG_ACTION" == "skip" ]]; then
  echo "$TAG is already published"
else
  git push origin "$TAG"
fi

if ! gh release view "$TAG" >/dev/null 2>&1; then
  gh release create "$TAG" --draft --verify-tag \
    --title "ViMotes $VERSION (Apple Silicon)" --generate-notes
fi
DOWNLOADS_DIR="$VALIDATION_DIR/downloads"
mkdir -p "$DOWNLOADS_DIR"
for asset in "$DMG_PATH" "$ZIP_PATH" "$CHECKSUMS_PATH" "$MANIFEST_PATH"; do
  vimotes_ensure_release_asset "$TAG" "$asset" "$DOWNLOADS_DIR"
done

PAGES_WORKTREE="$VALIDATION_DIR/pages"
if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
  git fetch origin gh-pages:refs/remotes/origin/gh-pages
  git worktree add --detach "$PAGES_WORKTREE" origin/gh-pages
else
  git worktree add --detach "$PAGES_WORKTREE" HEAD
  git -C "$PAGES_WORKTREE" checkout --orphan gh-pages
  git -C "$PAGES_WORKTREE" rm -rf .
fi

if [[ -f "$PAGES_WORKTREE/appcast.xml" ]]; then
  CURRENT_FEED_BUILD=$(xmllint --xpath 'string(//*[local-name()="item"]/*[local-name()="version"])' "$PAGES_WORKTREE/appcast.xml")
  if [[ "$CURRENT_FEED_BUILD" != <-> ]] || (( CURRENT_FEED_BUILD > BUILD_NUMBER )); then
    echo "error: refusing to replace an invalid or newer appcast" >&2
    exit 1
  fi
fi
vimotes_sync_pages_payload "$PAYLOAD_DIR" "$PAGES_WORKTREE" >/dev/null
git -C "$PAGES_WORKTREE" add appcast.xml .nojekyll
if git -C "$PAGES_WORKTREE" diff --cached --quiet; then
  echo "GitHub Pages already contains this appcast"
else
  git -C "$PAGES_WORKTREE" commit -m "release: publish ViMotes $VERSION appcast"
  git -C "$PAGES_WORKTREE" push origin HEAD:gh-pages
fi
gh release edit "$TAG" --draft=false

echo "Published https://github.com/YassineBenh/vimotes/releases/tag/$TAG"
