#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ROOTFS_TAR="${ROOTFS_TAR:-$PROJECT_ROOT/build/karudeb-riscv64-rootfs.tar.zst}"
DEST="${DEST:-$PROJECT_ROOT/build/rootfs-9p}"
SEED_9P_XATTRS="${SEED_9P_XATTRS:-1}"
HOST_9P_GROUP_WRITABLE="${HOST_9P_GROUP_WRITABLE:-1}"

ROOTFS_TAR="$(abs_path "$ROOTFS_TAR")"
DEST="$(realpath -m "$DEST")"

[[ -f "$ROOTFS_TAR" ]] || die "rootfs archive not found: $ROOTFS_TAR; run package-rootfs.sh first"
[[ "$DEST" == "$PROJECT_ROOT"/build/* || "${ALLOW_9P_DEST_OUTSIDE_BUILD:-0}" == "1" ]] || \
  die "refusing to install 9p root outside build/: $DEST"
[[ "$DEST" != "/" ]] || die "refusing to install into /"
[[ "$SEED_9P_XATTRS" == "0" || "$SEED_9P_XATTRS" == "1" ]] || die "SEED_9P_XATTRS must be 0 or 1"
[[ "$HOST_9P_GROUP_WRITABLE" == "0" || "$HOST_9P_GROUP_WRITABLE" == "1" ]] || die "HOST_9P_GROUP_WRITABLE must be 0 or 1"

if [[ -e "$DEST" ]]; then
  if [[ "${FORCE:-0}" != "1" ]]; then
    die "$DEST already exists; set FORCE=1 to replace it"
  fi
  rm -rf "$DEST"
fi

install -d -m 0755 "$DEST"

case "$ROOTFS_TAR" in
  *.tar.zst|*.tzst)
    need_cmd zstdcat zstd
    zstdcat "$ROOTFS_TAR" | tar --no-same-owner --numeric-owner --xattrs --acls \
      --exclude='./dev/*' --exclude='dev/*' -C "$DEST" -xf -
    ;;
  *.tar.gz|*.tgz)
    gzip -dc "$ROOTFS_TAR" | tar --no-same-owner --numeric-owner --xattrs --acls \
      --exclude='./dev/*' --exclude='dev/*' -C "$DEST" -xf -
    ;;
  *.tar)
    tar --no-same-owner --numeric-owner --xattrs --acls \
      --exclude='./dev/*' --exclude='dev/*' -C "$DEST" -xf "$ROOTFS_TAR"
    ;;
  *)
    die "unsupported archive extension: $ROOTFS_TAR"
    ;;
esac

install -d -m 0755 "$DEST/dev" "$DEST/dev/pts"
install -d -m 1777 "$DEST/dev/shm"

if [[ "$SEED_9P_XATTRS" == "1" ]]; then
  need_cmd python3 python3
  case "$ROOTFS_TAR" in
    *.tar.zst|*.tzst)
      zstdcat "$ROOTFS_TAR" | python3 "$SCRIPT_DIR/seed-9p-xattrs.py" "$DEST"
      ;;
    *.tar.gz|*.tgz)
      gzip -dc "$ROOTFS_TAR" | python3 "$SCRIPT_DIR/seed-9p-xattrs.py" "$DEST"
      ;;
    *.tar)
      python3 "$SCRIPT_DIR/seed-9p-xattrs.py" "$DEST" <"$ROOTFS_TAR"
      ;;
  esac
fi

cat >"$DEST/etc/fstab" <<'EOF'
rootfs    /      9p       trans=virtio,version=9p2000.L,cache=none,msize=512000,access=any    0  0
proc      /proc  proc     defaults                                                            0  0
sysfs     /sys   sysfs    defaults                                                            0  0
devtmpfs  /dev   devtmpfs mode=0755                                                           0  0
tmpfs     /run   tmpfs    nosuid,nodev,mode=0755,size=64M                                      0  0
tmpfs     /tmp   tmpfs    nosuid,nodev,size=512M                                               0  0
EOF

cat >"$DEST/etc/resolv.conf" <<'EOF'
nameserver 10.0.2.3
EOF

if [[ "$SEED_9P_XATTRS" == "1" ]]; then
  python3 - "$DEST/etc/fstab" "$DEST/etc/resolv.conf" <<'PY'
import os
import stat
import struct
import sys

for path, mode in ((sys.argv[1], 0o644), (sys.argv[2], 0o666)):
    for name, value in (
        ("uid", 0),
        ("gid", 0),
        ("mode", stat.S_IFREG | mode),
    ):
        os.setxattr(
            path,
            f"user.virtfs.{name}",
            struct.pack("<I", value),
            follow_symlinks=False,
        )
PY
fi

if [[ "$HOST_9P_GROUP_WRITABLE" == "1" ]]; then
  chmod -R g+rwX "$DEST"
fi

info "Installed user-owned QEMU 9p rootfs: $DEST"
info "Boot it with: ROOTFS_DIR='$DEST' $SCRIPT_DIR/run-qemu-9p.sh"
