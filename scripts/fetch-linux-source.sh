#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

KERNEL_VERSION="${KERNEL_VERSION:-7.1.1}"
KERNEL_SERIES="${KERNEL_SERIES:-v7.x}"
KERNEL_BASE_URL="${KERNEL_BASE_URL:-https://cdn.kernel.org/pub/linux/kernel/$KERNEL_SERIES}"
DEST_DIR="${DEST_DIR:-$PROJECT_ROOT/build/kernel-source}"

TARBALL="linux-$KERNEL_VERSION.tar.xz"
LINUX_SRC="$DEST_DIR/linux-$KERNEL_VERSION"
TARBALL_PATH="$DEST_DIR/$TARBALL"
SHA256SUMS="$DEST_DIR/sha256sums.asc"
SHA256_FILE="$DEST_DIR/$TARBALL.sha256"

DEST_DIR="$(abs_path "$DEST_DIR")"
LINUX_SRC="$(abs_path "$LINUX_SRC")"
TARBALL_PATH="$(abs_path "$TARBALL_PATH")"
SHA256SUMS="$(abs_path "$SHA256SUMS")"
SHA256_FILE="$(abs_path "$SHA256_FILE")"

need_cmd curl curl
need_cmd sha256sum coreutils
need_cmd tar tar
need_cmd xz xz-utils

if [[ -d "$LINUX_SRC" ]]; then
  info "Kernel source already present: $LINUX_SRC"
  exit 0
fi

mkdir -p "$DEST_DIR"

if [[ ! -f "$TARBALL_PATH" ]]; then
  info "Fetching $KERNEL_BASE_URL/$TARBALL"
  curl -fL -o "$TARBALL_PATH.tmp" "$KERNEL_BASE_URL/$TARBALL"
  mv "$TARBALL_PATH.tmp" "$TARBALL_PATH"
fi

info "Fetching $KERNEL_BASE_URL/sha256sums.asc"
curl -fL -o "$SHA256SUMS.tmp" "$KERNEL_BASE_URL/sha256sums.asc"
mv "$SHA256SUMS.tmp" "$SHA256SUMS"

grep -E "[[:space:]]$TARBALL\$" "$SHA256SUMS" >"$SHA256_FILE" || \
  die "could not find checksum for $TARBALL in $SHA256SUMS"

(cd "$DEST_DIR" && sha256sum -c "$(basename "$SHA256_FILE")")

info "Extracting $TARBALL_PATH"
tar -C "$DEST_DIR" -xf "$TARBALL_PATH"
[[ -d "$LINUX_SRC" ]] || die "expected extracted source directory not found: $LINUX_SRC"
info "Kernel source ready: $LINUX_SRC"
