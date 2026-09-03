#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
source "$ROOT_DIR/scripts/lib/release-publication.sh"
VERSION="${1:-}"
TAG="v$VERSION"
ARTIFACT_DIR="$ROOT_DIR/release-artifacts/$VERSION"
PAYLOAD_DIR="$ARTIFACT_DIR/pages"
ZIP_PATH="$ARTIFACT_DIR/ViMotes-$VERSION.zip"
DMG_PATH="$ARTIFACT_DIR/ViMotes-$VERSION.dmg"
CHECKSUMS_PATH="$ARTIFACT_DIR/SHA256SUMS"

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
for path in "$ZIP_PATH" "$DMG_PATH" "$CHECKSUMS_PATH" \
  "$PAYLOAD_DIR/appcast.xml"; do
  if [[ ! -e "$path" ]]; then
    echo "error: missing release artifact $path" >&2
    exit 1
  fi
done
(
  cd "$ARTIFACT_DIR"
  shasum -a 256 -c SHA256SUMS
)
xcrun stapler validate "$DMG_PATH"

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
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "error: GitHub Release $TAG already exists" >&2
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

gh release create "$TAG" \
  "$DMG_PATH#ViMotes $VERSION for macOS" \
  "$ZIP_PATH#ViMotes $VERSION update archive" \
  "$CHECKSUMS_PATH#SHA-256 checksums" \
  --verify-tag \
  --title "ViMotes $VERSION" \
  --generate-notes

PAGES_WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/vimotes-pages.XXXXXX")
trap 'git worktree remove --force "$PAGES_WORKTREE" >/dev/null 2>&1 || true; rm -rf "$PAGES_WORKTREE"' EXIT
if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
  git fetch origin gh-pages:refs/remotes/origin/gh-pages
  git worktree add --detach "$PAGES_WORKTREE" origin/gh-pages
else
  git worktree add --detach "$PAGES_WORKTREE" HEAD
  git -C "$PAGES_WORKTREE" checkout --orphan gh-pages
  git -C "$PAGES_WORKTREE" rm -rf .
fi

vimotes_sync_pages_payload "$PAYLOAD_DIR" "$PAGES_WORKTREE" >/dev/null
git -C "$PAGES_WORKTREE" add appcast.xml .nojekyll
if git -C "$PAGES_WORKTREE" diff --cached --quiet; then
  echo "GitHub Pages already contains this appcast"
else
  git -C "$PAGES_WORKTREE" commit -m "release: publish ViMotes $VERSION appcast"
  git -C "$PAGES_WORKTREE" push origin HEAD:gh-pages
fi

echo "Published https://github.com/YassineBenh/vimotes/releases/tag/$TAG"
