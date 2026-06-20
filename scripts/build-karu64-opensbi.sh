#!/usr/bin/env bash
# Build the generic karu64 OpenSBI fw_jump firmware.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build/karu64/opensbi}"
SRC_DIR="${SRC_DIR:-$PROJECT_ROOT/build/karu64/src}"
OPENSBI_OUT_DIR="${OPENSBI_OUT_DIR:-${OUT_DIR:-$BUILD_DIR}}"
JOBS="${JOBS:-$(nproc)}"

OPENSBI_REF="${OPENSBI_REF:-v1.8.1}"
OPENSBI_BUILD="${OPENSBI_BUILD:-$BUILD_DIR/build}"
OPENSBI_LLVM="${OPENSBI_LLVM:-1}"
OPENSBI_CROSS_COMPILE="${OPENSBI_CROSS_COMPILE:-riscv64-unknown-elf-}"
OPENSBI_RISCV_ISA="${OPENSBI_RISCV_ISA:-rv64imac_zicsr_zifencei}"
OPENSBI_RISCV_ABI="${OPENSBI_RISCV_ABI:-lp64}"
FW_JUMP_FDT_OFFSET="${FW_JUMP_FDT_OFFSET:-0x1c00000}"

FW_BIN="$OPENSBI_OUT_DIR/fw_jump.bin"
FW_ELF="$OPENSBI_OUT_DIR/fw_jump.elf"

select_opensbi_src() {
	if [[ -n "${OPENSBI_SRC:-}" ]]; then
		OPENSBI_SRC="$(abs_path "$OPENSBI_SRC")"
	else
		OPENSBI_SRC="$SRC_DIR/opensbi"
	fi
}

check_tools() {
	need_cmd make build-essential
	need_cmd gcc build-essential
	if [[ "$OPENSBI_LLVM" == 1 ]]; then
		need_cmd clang clang
		need_cmd ld.lld lld
	else
		need_cmd "${OPENSBI_CROSS_COMPILE}gcc" "riscv64 bare-metal toolchain"
	fi
	if [[ ! -d "$OPENSBI_SRC" ]]; then
		need_cmd git git
	fi
}

fetch_opensbi_src() {
	select_opensbi_src
	if [[ -d "$OPENSBI_SRC" ]]; then
		info "OpenSBI source: $OPENSBI_SRC"
		return
	fi
	mkdir -p "$SRC_DIR"
	info "Cloning OpenSBI $OPENSBI_REF into $OPENSBI_SRC"
	git clone --depth 1 --branch "$OPENSBI_REF" \
		https://github.com/riscv-software-src/opensbi.git "$OPENSBI_SRC"
}

build_opensbi() {
	fetch_opensbi_src
	mkdir -p "$OPENSBI_OUT_DIR" "$OPENSBI_BUILD"
	local args=(
		-C "$OPENSBI_SRC"
		O="$OPENSBI_BUILD"
		PLATFORM=generic
		PLATFORM_RISCV_XLEN=64
		PLATFORM_RISCV_ISA="$OPENSBI_RISCV_ISA"
		PLATFORM_RISCV_ABI="$OPENSBI_RISCV_ABI"
		FW_JUMP_FDT_OFFSET="$FW_JUMP_FDT_OFFSET"
		platform-cflags-y=-Wno-error
	)
	if [[ "$OPENSBI_LLVM" == 1 ]]; then
		args+=(LLVM=1)
	else
		args+=(CROSS_COMPILE="$OPENSBI_CROSS_COMPILE")
	fi
	make "${args[@]}" -j"$JOBS"
	cp "$OPENSBI_BUILD/platform/generic/firmware/fw_jump.bin" "$FW_BIN"
	cp "$OPENSBI_BUILD/platform/generic/firmware/fw_jump.elf" "$FW_ELF"
	info "OpenSBI fw_jump: $FW_BIN"
}

usage() {
	cat <<EOF
usage: $0 [check|build|clean]

Defaults:
  OPENSBI_OUT_DIR=$OPENSBI_OUT_DIR
  OPENSBI_REF=$OPENSBI_REF
  OPENSBI_RISCV_ISA=$OPENSBI_RISCV_ISA
  OPENSBI_RISCV_ABI=$OPENSBI_RISCV_ABI
EOF
}

main() {
	select_opensbi_src
	local action="${1:-build}"
	case "$action" in
		check) check_tools ;;
		build|opensbi) check_tools; build_opensbi ;;
		clean) rm -rf "$BUILD_DIR" ;;
		-h|--help|help) usage ;;
		*) usage; exit 2 ;;
	esac
}

main "$@"
