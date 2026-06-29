#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

missing=0

check_cmd() {
  local cmd="$1"
  local role="$2"
  local pkg="$3"

  if have_cmd "$cmd"; then
    printf 'ok      %-24s %s\n' "$cmd" "$role"
  else
    printf 'missing %-24s %s (package: %s)\n' "$cmd" "$role" "$pkg"
    missing=1
  fi
}

check_one_of() {
  local role="$1"
  shift

  local found=0
  local item
  for item in "$@"; do
    local cmd="${item%%:*}"
    if have_cmd "$cmd"; then
      printf 'ok      %-24s %s\n' "$cmd" "$role"
      found=1
      break
    fi
  done

  if [[ "$found" -eq 0 ]]; then
    printf 'missing %-24s %s (one of: ' 'tool choice' "$role"
    local first=1
    for item in "$@"; do
      local cmd="${item%%:*}"
      local pkg="${item#*:}"
      if [[ "$first" -eq 0 ]]; then
        printf ', '
      fi
      printf '%s/%s' "$cmd" "$pkg"
      first=0
    done
    printf ')\n'
    missing=1
  fi
}

check_optional_one_of() {
  local role="$1"
  shift

  local found=0
  local item
  for item in "$@"; do
    local cmd="${item%%:*}"
    if have_cmd "$cmd"; then
      printf 'ok      %-24s %s\n' "$cmd" "$role"
      found=1
      break
    fi
  done

  if [[ "$found" -eq 0 ]]; then
    printf 'missing %-24s %s (optional; one of: ' 'tool choice' "$role"
    local first=1
    for item in "$@"; do
      local cmd="${item%%:*}"
      local pkg="${item#*:}"
      if [[ "$first" -eq 0 ]]; then
        printf ', '
      fi
      printf '%s/%s' "$cmd" "$pkg"
      first=0
    done
    printf ')\n'
  fi
}

info "Project: $PROJECT_ROOT"
info ""

check_one_of "build Debian riscv64 rootfs" \
  "mmdebstrap:mmdebstrap" \
  "debootstrap:debootstrap"
check_one_of "run riscv64 package maintainer scripts on amd64 hosts" \
  "qemu-riscv64-static:qemu-user or qemu-user-static" \
  "qemu-riscv64:qemu-user"
check_cmd arch-test "validate foreign-architecture binfmt for mmdebstrap" arch-test
if have_cmd arch-test; then
  if arch-test riscv64 >/dev/null 2>&1; then
    printf 'ok      %-24s %s\n' "binfmt:riscv64" "riscv64 binaries can execute through binfmt"
  else
    printf 'missing %-24s %s (package: %s)\n' "binfmt:riscv64" "riscv64 binaries cannot execute through binfmt" "qemu-user-binfmt"
    missing=1
  fi
fi
check_cmd tar "package rootfs archive" tar
check_cmd curl "fetch Linux 7.1.2 source when needed" curl
check_cmd sha256sum "verify downloaded Linux source tarball" coreutils
check_cmd xz "extract Linux .tar.xz source archive" xz-utils
check_cmd python3 "seed QEMU 9p mapped-xattr metadata" python3
check_one_of "compress rootfs archive" \
  "zstd:zstd" \
  "gzip:gzip"
check_one_of "build riscv64 target helper binaries" \
  "riscv64-unknown-linux-gnu-clang:clang" \
  "riscv64-linux-gnu-clang:clang" \
  "clang:clang"
check_cmd ld.lld "link clang-built riscv64 target helpers" lld
check_cmd clang "build RISC-V Linux kernels with LLVM" clang
check_cmd llvm-ar "archive RISC-V Linux kernel objects with LLVM" llvm
check_cmd llvm-nm "inspect RISC-V Linux kernel symbols with LLVM" llvm
check_cmd llvm-objcopy "copy RISC-V Linux kernel images with LLVM" llvm
check_cmd llvm-objdump "inspect RISC-V Linux kernel objects with LLVM" llvm
check_cmd llvm-readelf "inspect RISC-V Linux kernel ELF files with LLVM" llvm
check_cmd llvm-strip "strip RISC-V Linux kernel objects with LLVM" llvm
check_cmd qemu-system-riscv64 "run QEMU riscv64 system emulator" qemu-system-misc
check_cmd ip "create TAP interface for QEMU NFS-root test" iproute2
check_cmd exportfs "export rootfs over NFS" nfs-kernel-server
check_cmd rpcbind "NFSv3 RPC service discovery" rpcbind
check_cmd sudo "perform root-only host setup when needed" sudo
check_cmd fakeroot "create user-owned ext4 VNC root image with target ownership" fakeroot
check_cmd mkfs.ext4 "create ext4 VNC root image" e2fsprogs
check_cmd e2fsck "check ext4 VNC root image after QEMU stop" e2fsprogs
check_cmd ss "check QEMU forwarded VNC and SSH ports" iproute2
check_cmd timeout "bound QEMU VNC socket probes" coreutils
check_optional_one_of "connect to the forwarded VNC session from this host" \
  "vncviewer:tigervnc-viewer" \
  "xtigervncviewer:tigervnc-viewer" \
  "gvncviewer:gvncviewer"
check_cmd make "optional kernel build" build-essential
check_optional_one_of "optional riscv64 kernel GCC cross compiler" \
  "riscv64-linux-gnu-gcc:gcc-riscv64-linux-gnu" \
  "riscv64-unknown-linux-gnu-gcc:external toolchain"

info ""
if [[ "$missing" -eq 0 ]]; then
  info "All checked tools are present."
else
  info "Some tools are missing. Install the listed packages, or put equivalent tools in PATH."
fi

exit "$missing"
