#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

LINUX_SRC="${LINUX_SRC:-${1:-}}"
OUT_DIR="${OUT_DIR:-$PROJECT_ROOT/build/linux-riscv64}"
DEFCONFIG="${DEFCONFIG:-defconfig}"
FRAGMENT="${FRAGMENT:-$PROJECT_ROOT/configs/linux-riscv64-nfsroot.fragment}"
CROSS_COMPILE="${CROSS_COMPILE:-}"
LINUX_LLVM="${LLVM:-}"
HOSTCC="${HOSTCC:-}"
HOSTCXX="${HOSTCXX:-}"
JOBS="${JOBS:-$(nproc)}"
INSTALL_MOD_PATH="${INSTALL_MOD_PATH:-}"
BUILD_TARGETS="${BUILD_TARGETS:-Image}"
LINUX_PATCH_DIR="${LINUX_PATCH_DIR:-}"

[[ -n "$LINUX_SRC" ]] || die "usage: $0 /path/to/linux"
LINUX_SRC="$(abs_path "$LINUX_SRC")"
OUT_DIR="$(abs_path "$OUT_DIR")"
FRAGMENT="$(abs_path "$FRAGMENT")"

if [[ ! -d "$LINUX_SRC" && "${FETCH_LINUX_SOURCE:-1}" == "1" && "$LINUX_SRC" == "$PROJECT_ROOT"/build/kernel-source/linux-* ]]; then
  KERNEL_VERSION="${LINUX_SRC##*/linux-}" DEST_DIR="$(dirname "$LINUX_SRC")" "$SCRIPT_DIR/fetch-linux-source.sh"
fi

[[ -d "$LINUX_SRC" ]] || die "Linux source directory not found: $LINUX_SRC"
[[ -x "$LINUX_SRC/scripts/kconfig/merge_config.sh" ]] || die "missing merge_config.sh in Linux source"
[[ -f "$FRAGMENT" ]] || die "kernel fragment not found: $FRAGMENT"

need_cmd make build-essential
need_cmd patch patch

apply_linux_patches() {
  local patch_dirs=()
  local patch_dir patch_file

  if [[ -n "$LINUX_PATCH_DIR" ]]; then
    patch_dirs+=("$(abs_path "$LINUX_PATCH_DIR")")
  else
    patch_dirs+=("$PROJECT_ROOT/patches/${LINUX_SRC##*/}" "$PROJECT_ROOT/patches/linux")
  fi

  for patch_dir in "${patch_dirs[@]}"; do
    [[ -d "$patch_dir" ]] || continue
    shopt -s nullglob
    for patch_file in "$patch_dir"/*.patch; do
      if patch -d "$LINUX_SRC" -p1 --forward --dry-run <"$patch_file" >/dev/null; then
        info "Applying Linux patch: ${patch_file#$PROJECT_ROOT/}"
        patch -d "$LINUX_SRC" -p1 --forward <"$patch_file"
      elif patch -d "$LINUX_SRC" -p1 --reverse --dry-run <"$patch_file" >/dev/null; then
        info "Linux patch already applied: ${patch_file#$PROJECT_ROOT/}"
      else
        die "Linux patch does not apply cleanly: $patch_file"
      fi
    done
    shopt -u nullglob
  done
}

apply_linux_patches

have_llvm_kernel_tools() {
  have_cmd clang &&
    have_cmd clang++ &&
    have_cmd ld.lld &&
    have_cmd llvm-ar &&
    have_cmd llvm-nm &&
    have_cmd llvm-objcopy &&
    have_cmd llvm-objdump &&
    have_cmd llvm-readelf &&
    have_cmd llvm-strip
}

select_host_compilers() {
  if [[ -z "$HOSTCC" ]]; then
    if [[ -x /usr/bin/clang ]]; then
      HOSTCC=/usr/bin/clang
    elif have_cmd gcc; then
      HOSTCC=gcc
    else
      die "missing host C compiler for Linux build"
    fi
  fi
  if [[ -z "$HOSTCXX" ]]; then
    if [[ -x /usr/bin/clang++ ]]; then
      HOSTCXX=/usr/bin/clang++
    elif have_cmd g++; then
      HOSTCXX=g++
    else
      die "missing host C++ compiler for Linux build"
    fi
  fi
}

if [[ -z "$CROSS_COMPILE" && -z "$LINUX_LLVM" ]]; then
  if have_llvm_kernel_tools; then
    LINUX_LLVM=1
  elif have_cmd riscv64-linux-gnu-gcc; then
    CROSS_COMPILE="riscv64-linux-gnu-"
  elif have_cmd riscv64-unknown-linux-gnu-gcc; then
    CROSS_COMPILE="riscv64-unknown-linux-gnu-"
  else
    die "missing riscv64 Linux compiler (tried clang/LLVM, riscv64-linux-gnu-gcc, and riscv64-unknown-linux-gnu-gcc)"
  fi
fi
if [[ -n "$LINUX_LLVM" ]]; then
  have_llvm_kernel_tools || die "LLVM=$LINUX_LLVM requires clang, clang++, ld.lld, and llvm binutils"
  select_host_compilers
else
  need_cmd "${CROSS_COMPILE}gcc" gcc-riscv64-linux-gnu
fi

mkdir -p "$OUT_DIR"

make_args=(ARCH=riscv)
if [[ -n "$LINUX_LLVM" ]]; then
  make_args+=(LLVM="$LINUX_LLVM")
fi
if [[ -n "$CROSS_COMPILE" ]]; then
  make_args+=(CROSS_COMPILE="$CROSS_COMPILE")
fi
if [[ -n "$HOSTCC" ]]; then
  make_args+=(HOSTCC="$HOSTCC")
fi
if [[ -n "$HOSTCXX" ]]; then
  make_args+=(HOSTCXX="$HOSTCXX")
fi

make -C "$LINUX_SRC" O="$OUT_DIR" "${make_args[@]}" "$DEFCONFIG"
"$LINUX_SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT_DIR" "$OUT_DIR/.config" "$FRAGMENT"
make -C "$LINUX_SRC" O="$OUT_DIR" "${make_args[@]}" olddefconfig
read -r -a build_targets <<<"$BUILD_TARGETS"
make -C "$LINUX_SRC" O="$OUT_DIR" "${make_args[@]}" -j"$JOBS" "${build_targets[@]}"

if [[ -n "$INSTALL_MOD_PATH" ]]; then
  make -C "$LINUX_SRC" O="$OUT_DIR" "${make_args[@]}" \
    INSTALL_MOD_PATH="$INSTALL_MOD_PATH" modules_install
fi

info "Kernel image: $OUT_DIR/arch/riscv/boot/Image"
