#!/usr/bin/env bash

set -euo pipefail

PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"
if [[ -d "${HOME:-}/rv/riscv/bin" ]]; then
  PATH="$HOME/rv/riscv/bin:$PATH"
fi
export PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

need_cmd() {
  local cmd="$1"
  local pkg="${2:-}"

  if ! have_cmd "$cmd"; then
    if [[ -n "$pkg" ]]; then
      die "missing command '$cmd' (install package: $pkg)"
    fi
    die "missing command '$cmd'"
  fi
}

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    need_cmd sudo sudo
    sudo "$@"
  fi
}

abs_path() {
  local path="$1"
  local dir
  local base

  if have_cmd realpath; then
    realpath -m "$path"
    return
  fi

  if [[ -d "$path" ]]; then
    (cd "$path" && pwd -P)
    return
  fi

  dir="$(dirname "$path")"
  base="$(basename "$path")"
  (cd "$dir" && printf '%s/%s\n' "$(pwd -P)" "$base")
}

safe_remove_rootfs() {
  local path="$1"
  local abs
  local trash

  abs="$(abs_path "$path")"
  [[ "$abs" != "/" ]] || die "refusing to remove /"
  [[ "$abs" == "$PROJECT_ROOT"/build/* || "${ALLOW_REMOVE_OUTSIDE_BUILD:-0}" == "1" ]] || \
    die "refusing to remove '$abs'; set ALLOW_REMOVE_OUTSIDE_BUILD=1 if this is intentional"

  if rm -rf "$abs" 2>/dev/null; then
    return 0
  fi

  if have_cmd unshare && unshare --map-auto --setuid 0 --setgid 0 test -e "$abs" >/dev/null 2>&1; then
    if unshare --map-auto --setuid 0 --setgid 0 rm -rf "$abs" 2>/dev/null; then
      return 0
    fi
  fi

  trash="$(dirname "$abs")/.remove-$(basename "$abs").$$"
  if mv "$abs" "$trash" 2>/dev/null; then
    if rm -rf "$trash" 2>/dev/null; then
      return 0
    fi
    if have_cmd unshare && unshare --map-auto --setuid 0 --setgid 0 test -e "$trash" >/dev/null 2>&1; then
      unshare --map-auto --setuid 0 --setgid 0 rm -rf "$trash" 2>/dev/null || true
      rmdir "$trash" 2>/dev/null || true
    fi
    if [[ ! -e "$trash" ]]; then
      return 0
    fi
    info "Warning: moved old rootfs aside but could not fully remove it: $trash"
    return 0
  fi

  as_root rm -rf "$abs"
}
