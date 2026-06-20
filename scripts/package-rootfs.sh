#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ROOTFS_DIR="${ROOTFS_DIR:-$PROJECT_ROOT/build/rootfs}"
OUT="${OUT:-$PROJECT_ROOT/build/karudeb-riscv64-rootfs.tar.zst}"

ROOTFS_DIR="$(abs_path "$ROOTFS_DIR")"
OUT="$(abs_path "$OUT")"

[[ -d "$ROOTFS_DIR" ]] || die "rootfs directory not found: $ROOTFS_DIR"
need_cmd tar tar
mkdir -p "$(dirname "$OUT")"

tar_cmd=(tar --numeric-owner --xattrs --acls -C "$ROOTFS_DIR" -cf - .)
tar_prefix=()
if [[ ! -r "$ROOTFS_DIR/etc/shadow" ]]; then
  if have_cmd unshare && unshare --map-auto --setuid 0 --setgid 0 test -r "$ROOTFS_DIR/etc/shadow" >/dev/null 2>&1; then
    tar_prefix=(unshare --map-auto --setuid 0 --setgid 0)
  else
    tar_prefix=(as_root)
  fi
fi

if have_cmd zstd; then
  "${tar_prefix[@]}" "${tar_cmd[@]}" | zstd -T0 -19 -f -o "$OUT"
elif have_cmd gzip; then
  OUT="${OUT%.zst}.gz"
  "${tar_prefix[@]}" "${tar_cmd[@]}" | gzip -9 >"$OUT"
else
  die "missing compressor: install zstd or gzip"
fi

info "Wrote $OUT"
