#!/bin/zsh

vimotes_verify_binary_paths() {
  local binary="${1:?binary path is required}"
  local source_root="${2:?source root is required}"
  local result
  LC_ALL=C /usr/bin/grep -aEq '/Users/|/home/|/private/tmp/|/private/var/folders/|/var/folders/|/tmp/' "$binary" && result=0 || result=$?
  if (( result != 1 )); then
    echo "error: binary contains a local path or could not be inspected" >&2
    return 1
  fi
  LC_ALL=C /usr/bin/grep -aFq -- "$source_root/" "$binary" && result=0 || result=$?
  if (( result != 1 )); then
    echo "error: binary contains the build root or could not be inspected" >&2
    return 1
  fi
}

vimotes_verify_debug_symbols() {
  setopt localoptions pipefail
  local binary="${1:?binary path is required}"
  local symbols="${2:?dSYM path is required}"
  local binary_ids symbol_ids
  binary_ids=$(xcrun dwarfdump --uuid "$binary" | awk '{ print $2, $3 }') || return 1
  symbol_ids=$(xcrun dwarfdump --uuid "$symbols" | awk '{ print $2, $3 }') || return 1
  if [[ -z "$binary_ids" || "$binary_ids" != "$symbol_ids" ]]; then
    echo "error: debug symbols do not match the distributed binary" >&2
    return 1
  fi
  if ! xcrun dwarfdump --debug-info "$symbols" | /usr/bin/grep DW_TAG_compile_unit >/dev/null; then
    echo "error: dSYM does not contain readable compilation units" >&2
    return 1
  fi
}

vimotes_prepare_distribution_binary() {
  local binary="${1:?binary path is required}"
  local symbols="${2:?dSYM path is required}"
  local source_root="${3:?source root is required}"
  if [[ -L "$symbols" ]]; then
    echo "error: dSYM output must not be a symlink" >&2
    return 1
  fi
  xcrun dsymutil "$binary" -o "$symbols" || return 1
  xcrun strip -S "$binary" || return 1
  vimotes_verify_binary_paths "$binary" "$source_root" || return 1
  vimotes_verify_debug_symbols "$binary" "$symbols"
}
