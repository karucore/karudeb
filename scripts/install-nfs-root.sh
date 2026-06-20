#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ROOTFS_TAR="${ROOTFS_TAR:-$PROJECT_ROOT/build/karudeb-riscv64-rootfs.tar.zst}"
DEST="${DEST:-/srv/nfs/karudeb}"

ROOTFS_TAR="$(abs_path "$ROOTFS_TAR")"
DEST="$(realpath -m "$DEST")"

[[ -f "$ROOTFS_TAR" ]] || die "rootfs archive not found: $ROOTFS_TAR"
[[ "$DEST" != "/" ]] || die "refusing to install into /"

if [[ -e "$DEST" ]]; then
  if [[ "${FORCE:-0}" != "1" ]]; then
    die "$DEST already exists; set FORCE=1 to replace it"
  fi
  as_root rm -rf "$DEST"
fi

as_root install -d -m 0755 "$DEST"

case "$ROOTFS_TAR" in
  *.tar.zst|*.tzst)
    need_cmd zstdcat zstd
    zstdcat "$ROOTFS_TAR" | as_root tar --numeric-owner --xattrs --acls -C "$DEST" -xf -
    ;;
  *.tar.gz|*.tgz)
    gzip -dc "$ROOTFS_TAR" | as_root tar --numeric-owner --xattrs --acls -C "$DEST" -xf -
    ;;
  *.tar)
    as_root tar --numeric-owner --xattrs --acls -C "$DEST" -xf "$ROOTFS_TAR"
    ;;
  *)
    die "unsupported archive extension: $ROOTFS_TAR"
    ;;
esac

rootfs_uid="$(stat -c %u "$DEST")"
[[ "$rootfs_uid" == "0" ]] || die "installed rootfs is still not root-owned on the host"

info "Installed NFS rootfs: $DEST"
info "Export it with: ROOTFS_DIR='$DEST' $SCRIPT_DIR/export-nfs-root.sh"

