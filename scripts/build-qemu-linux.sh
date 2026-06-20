#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

KERNEL_VERSION="${KERNEL_VERSION:-7.1.1}"
LINUX_SRC="${LINUX_SRC:-${1:-$PROJECT_ROOT/build/kernel-source/linux-$KERNEL_VERSION}}"
OUT_DIR="${OUT_DIR:-$PROJECT_ROOT/build/linux-riscv64}"
DEFCONFIG="${DEFCONFIG:-defconfig}"
FRAGMENT="${FRAGMENT:-$PROJECT_ROOT/configs/linux-riscv64-nfsroot.fragment}"
BUILD_TARGETS="${BUILD_TARGETS:-Image}"

export KERNEL_VERSION OUT_DIR DEFCONFIG FRAGMENT BUILD_TARGETS
exec "$SCRIPT_DIR/build-linux.sh" "$LINUX_SRC"
