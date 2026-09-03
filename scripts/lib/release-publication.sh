#!/bin/zsh

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
