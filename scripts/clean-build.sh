#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

TARGET="${TARGET:-$PROJECT_ROOT/build}"
TARGET="$(abs_path "$TARGET")"

[[ "$TARGET" == "$PROJECT_ROOT/build" ]] || die "refusing to remove non-build target: $TARGET"

if [[ ! -e "$TARGET" ]]; then
  info "Nothing to remove: $TARGET"
  exit 0
fi

if rm -rf "$TARGET" 2>/dev/null; then
  info "Removed $TARGET"
  exit 0
fi

if have_cmd unshare && unshare --map-auto --setuid 0 --setgid 0 test -e "$TARGET" >/dev/null 2>&1; then
  unshare --map-auto --setuid 0 --setgid 0 rm -rf "$TARGET"
  info "Removed $TARGET"
  exit 0
fi

as_root rm -rf "$TARGET"
info "Removed $TARGET"
