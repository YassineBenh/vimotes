#!/bin/zsh

vimotes_source_tree() (
  local temporary_index
  temporary_index=$(mktemp "${TMPDIR:-/tmp}/vimotes-index.XXXXXX")
  trap 'rm -f "$temporary_index" "$temporary_index.lock"' EXIT
  export GIT_INDEX_FILE="$temporary_index"
  git read-tree HEAD || return 1
  git add --update || return 1
  git write-tree
)

vimotes_write_manifest() {
  local manifest="${1:?manifest path is required}"
  local source_tree="${2:?source tree is required}"
  local version="${3:?version is required}"
  local build="${4:?build is required}"
  local public_key="${5:?Sparkle public key is required}"
  /usr/libexec/PlistBuddy \
    -c 'Clear dict' \
    -c "Add :sourceTree string $source_tree" \
    -c "Add :version string $version" \
    -c "Add :build string $build" \
    -c 'Add :architecture string arm64' \
    -c "Add :sparklePublicKey string $public_key" \
    "$manifest" >/dev/null
}

vimotes_verify_manifest() {
  local manifest="${1:?manifest path is required}"
  local source_tree="${2:?source tree is required}"
  local version="${3:?version is required}"
  local build="${4:?build is required}"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :sourceTree' "$manifest")" == "$source_tree" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :version' "$manifest")" == "$version" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :build' "$manifest")" == "$build" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :architecture' "$manifest")" == 'arm64' ]]
}

vimotes_ensure_release_asset() {
  local tag="${1:?tag is required}"
  local asset="${2:?asset path is required}"
  local downloads="${3:?download directory is required}"
  local filename="${asset:t}"
  local names
  names=$(gh release view "$tag" --json assets --jq '.assets[].name') || return 1
  if print -r -- "$names" | /usr/bin/grep -Fxq -- "$filename"; then
    gh release download "$tag" --pattern "$filename" --dir "$downloads" || return 1
    if ! cmp -s "$asset" "$downloads/$filename"; then
      echo "error: existing release asset $filename differs; refusing to overwrite it" >&2
      return 1
    fi
  else
    gh release upload "$tag" "$asset" || return 1
  fi
}

vimotes_tag_action() {
  local existing_commit="${1:-}"
  local release_commit="${2:?release commit is required}"
  if [[ -z "$existing_commit" ]]; then
    echo "create"
  elif [[ "$existing_commit" == "$release_commit" ]]; then
    echo "skip"
  else
    echo "conflict"
  fi
}

vimotes_sync_pages_payload() {
  local payload_dir="${1:?payload directory is required}"
  local pages_dir="${2:?pages directory is required}"
  local changed=0

  if ! cmp -s "$payload_dir/appcast.xml" "$pages_dir/appcast.xml"; then
    cp "$payload_dir/appcast.xml" "$pages_dir/appcast.xml"
    changed=1
  fi
  if [[ ! -e "$pages_dir/.nojekyll" ]]; then
    touch "$pages_dir/.nojekyll"
    changed=1
  fi

  if (( changed )); then
    echo "changed"
  else
    echo "unchanged"
  fi
}
