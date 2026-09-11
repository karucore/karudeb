#!/usr/bin/env bash
# Build the karu64 RV64IMAC soft-float Linux + BusyBox initramfs image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

PATH="${HOME:-}/rv/riscv/bin:$PATH:/usr/local/sbin:/usr/sbin:/sbin"
export PATH

BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build/karu64-rv64imac-image}"
SRC_DIR="${SRC_DIR:-$BUILD_DIR/src}"
OUT_DIR="${OUT_DIR:-$BUILD_DIR}"
JOBS="${JOBS:-$(nproc)}"

KERNEL_VERSION="${KERNEL_VERSION:-7.2.4}"
KERNEL_SERIES="${KERNEL_SERIES:-v7.x}"
KERNEL_BASE_URL="${KERNEL_BASE_URL:-https://cdn.kernel.org/pub/linux/kernel/$KERNEL_SERIES}"
KERNEL_FRAGMENT="${KERNEL_FRAGMENT:-$PROJECT_ROOT/configs/linux-riscv64-karu64-rv64imac.fragment}"
KERNEL_BUILD="${KERNEL_BUILD:-$BUILD_DIR/linux-build}"
KERNEL_CROSS_COMPILE="${KERNEL_CROSS_COMPILE:-riscv64-unknown-linux-musl-}"

BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.37.0}"
BUSYBOX_FRAGMENT="${BUSYBOX_FRAGMENT:-$PROJECT_ROOT/configs/busybox-karu64-rv64imac.fragment}"
BUSYBOX_BUILD="${BUSYBOX_BUILD:-$BUILD_DIR/busybox-build}"
BUSYBOX_CROSS_COMPILE="${BUSYBOX_CROSS_COMPILE:-riscv64-unknown-linux-musl-}"

OPENSBI_REF="${OPENSBI_REF:-v1.8.1}"
OPENSBI_OUT_DIR="${OPENSBI_OUT_DIR:-$PROJECT_ROOT/build/karu64/opensbi}"
OPENSBI_BUILD="${OPENSBI_BUILD:-$OPENSBI_OUT_DIR/build}"
OPENSBI_LLVM="${OPENSBI_LLVM:-1}"
OPENSBI_CROSS_COMPILE="${OPENSBI_CROSS_COMPILE:-riscv64-unknown-elf-}"
OPENSBI_RISCV_ISA="${OPENSBI_RISCV_ISA:-rv64imac_zicsr_zifencei}"
OPENSBI_RISCV_ABI="${OPENSBI_RISCV_ABI:-lp64}"
FW_JUMP_FDT_OFFSET="${FW_JUMP_FDT_OFFSET:-0x1c00000}"

DTB_VARIANT="${DTB_VARIANT:-ddr}"
RAM_BASE="${RAM_BASE:-0x80000000}"
case "$DTB_VARIANT" in
	sim|linux_tb) DEFAULT_RAM_SIZE=0x02000000 ;;
	ddr|hardware) DEFAULT_RAM_SIZE=0x10000000 ;;
	*) DEFAULT_RAM_SIZE=0x10000000 ;;
esac
RAM_SIZE="${RAM_SIZE:-$DEFAULT_RAM_SIZE}"
FW_OFF="${FW_OFF:-0x0}"
KERNEL_OFF="${KERNEL_OFF:-0x200000}"
INITRD_OFF="${INITRD_OFF:-0x1000000}"
DTB_OFF="${DTB_OFF:-0x1b00000}"
FDT_OFF="${FDT_OFF:-$FW_JUMP_FDT_OFFSET}"

KERNEL_IMAGE="$KERNEL_BUILD/arch/riscv/boot/Image"
BUSYBOX_BIN="$OUT_DIR/busybox"
INITRD_GZ="$OUT_DIR/initramfs.cpio.gz"
FW_BIN="$OPENSBI_OUT_DIR/fw_jump.bin"
FW_ELF="$OPENSBI_OUT_DIR/fw_jump.elf"
BOARD_DTB="$OUT_DIR/board.dtb"
FLAT_IMG="$OUT_DIR/flat.img"
FLAT_GZ="$OUT_DIR/flat.img.gz"

hx() { printf '0x%08x' "$1"; }
sz() { stat -c%s "$1"; }

select_linux_src() {
	if [[ -n "${LINUX_SRC:-}" ]]; then
		LINUX_SRC="$(abs_path "$LINUX_SRC")"
	else
		LINUX_SRC="$PROJECT_ROOT/build/kernel-source/linux-$KERNEL_VERSION"
	fi
}

select_opensbi_src() {
	if [[ -n "${OPENSBI_SRC:-}" ]]; then
		OPENSBI_SRC="$(abs_path "$OPENSBI_SRC")"
	else
		OPENSBI_SRC="$PROJECT_ROOT/build/karu64/src/opensbi"
	fi
}

select_busybox_src() {
	if [[ -n "${BUSYBOX_SRC:-}" ]]; then
		BUSYBOX_SRC="$(abs_path "$BUSYBOX_SRC")"
	else
		BUSYBOX_SRC="$SRC_DIR/busybox-$BUSYBOX_VERSION"
	fi
}

check_tools() {
	need_cmd make build-essential
	need_cmd gcc build-essential
	need_cmd perl perl
	need_cmd gzip gzip
	need_cmd cpio cpio
	need_cmd dtc device-tree-compiler
	need_cmd fdtput device-tree-compiler
	need_cmd bc bc
	need_cmd bison bison
	need_cmd flex flex
	need_cmd "${KERNEL_CROSS_COMPILE}gcc" "riscv64 soft-float Linux toolchain"
	need_cmd "${BUSYBOX_CROSS_COMPILE}gcc" "riscv64 soft-float Linux toolchain"
	need_cmd "${BUSYBOX_CROSS_COMPILE}strip" "riscv64 soft-float Linux toolchain"
	if [[ "$OPENSBI_LLVM" == 1 ]]; then
		need_cmd clang clang
		need_cmd ld.lld lld
	else
		need_cmd "${OPENSBI_CROSS_COMPILE}gcc" "riscv64 bare-metal toolchain"
	fi
	if [[ ! -d "$LINUX_SRC" ]]; then
		need_cmd curl curl
		need_cmd sha256sum coreutils
		need_cmd tar tar
		need_cmd xz xz-utils
	fi
	if [[ ! -d "$OPENSBI_SRC" ]]; then
		need_cmd git git
	fi
	if [[ ! -d "$BUSYBOX_SRC" ]]; then
		need_cmd curl curl
		need_cmd tar tar
		need_cmd bzip2 bzip2
	fi
}

fetch_linux_src() {
	select_linux_src
	if [[ -d "$LINUX_SRC" ]]; then
		info "Linux source: $LINUX_SRC"
		return
	fi
	KERNEL_VERSION="$KERNEL_VERSION" KERNEL_SERIES="$KERNEL_SERIES" \
		KERNEL_BASE_URL="$KERNEL_BASE_URL" DEST_DIR="$(dirname "$LINUX_SRC")" \
		"$SCRIPT_DIR/fetch-linux-source.sh"
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

fetch_busybox_src() {
	select_busybox_src
	if [[ -d "$BUSYBOX_SRC" ]]; then
		info "BusyBox source: $BUSYBOX_SRC"
		return
	fi
	mkdir -p "$SRC_DIR"
	local tarball="busybox-$BUSYBOX_VERSION.tar.bz2"
	local tarpath="$SRC_DIR/$tarball"
	info "Fetching https://busybox.net/downloads/$tarball"
	curl -fL -o "$tarpath.tmp" "https://busybox.net/downloads/$tarball"
	mv "$tarpath.tmp" "$tarpath"
	tar -C "$SRC_DIR" -xf "$tarpath"
	[[ -d "$BUSYBOX_SRC" ]] || die "expected BusyBox source missing after extract: $BUSYBOX_SRC"
}

build_opensbi() {
	OPENSBI_OUT_DIR="$OPENSBI_OUT_DIR" \
	OPENSBI_BUILD="$OPENSBI_BUILD" \
	OPENSBI_SRC="$OPENSBI_SRC" \
	OPENSBI_REF="$OPENSBI_REF" \
	OPENSBI_LLVM="$OPENSBI_LLVM" \
	OPENSBI_CROSS_COMPILE="$OPENSBI_CROSS_COMPILE" \
	OPENSBI_RISCV_ISA="$OPENSBI_RISCV_ISA" \
	OPENSBI_RISCV_ABI="$OPENSBI_RISCV_ABI" \
	FW_JUMP_FDT_OFFSET="$FW_JUMP_FDT_OFFSET" \
	JOBS="$JOBS" \
		"$SCRIPT_DIR/build-karu64-opensbi.sh" build
}

build_kernel() {
	fetch_linux_src
	[[ -x "$LINUX_SRC/scripts/kconfig/merge_config.sh" ]] || die "missing merge_config.sh in $LINUX_SRC"
	[[ -f "$KERNEL_FRAGMENT" ]] || die "missing kernel fragment: $KERNEL_FRAGMENT"
	mkdir -p "$KERNEL_BUILD"
	make -C "$LINUX_SRC" O="$KERNEL_BUILD" ARCH=riscv CROSS_COMPILE="$KERNEL_CROSS_COMPILE" allnoconfig
	"$LINUX_SRC/scripts/kconfig/merge_config.sh" -m -O "$KERNEL_BUILD" \
		"$KERNEL_BUILD/.config" "$KERNEL_FRAGMENT"
	make -C "$LINUX_SRC" O="$KERNEL_BUILD" ARCH=riscv CROSS_COMPILE="$KERNEL_CROSS_COMPILE" olddefconfig
	if [[ "${KARU_ALLOW_FPU:-0}" != 1 ]] && grep -q '^CONFIG_FPU=y' "$KERNEL_BUILD/.config"; then
		die "kernel config has CONFIG_FPU=y; expected rv64imac soft-float (set KARU_ALLOW_FPU=1 for a vector build)"
	fi
	make -C "$LINUX_SRC" O="$KERNEL_BUILD" ARCH=riscv CROSS_COMPILE="$KERNEL_CROSS_COMPILE" -j"$JOBS" Image
	info "Kernel Image: $KERNEL_IMAGE"
}

set_config_line() {
	local cfg="$1" line="$2" sym
	case "$line" in
		CONFIG_*=*) sym="${line%%=*}" ;;
		"# CONFIG_"*" is not set") sym="${line#"# "}"; sym="${sym%" is not set"}" ;;
		*) return 0 ;;
	esac
	perl -0pi -e "s/^${sym}=.*\\n//mg; s/^# ${sym} is not set\\n//mg" "$cfg"
	printf '%s\n' "$line" >> "$cfg"
}

build_busybox() {
	fetch_busybox_src
	[[ -f "$BUSYBOX_FRAGMENT" ]] || die "missing BusyBox fragment: $BUSYBOX_FRAGMENT"
	rm -rf "$BUSYBOX_BUILD"
	mkdir -p "$BUSYBOX_BUILD" "$OUT_DIR"
	make -C "$BUSYBOX_SRC" O="$BUSYBOX_BUILD" ARCH=riscv \
		CROSS_COMPILE="$BUSYBOX_CROSS_COMPILE" HOSTCC=gcc allnoconfig >/dev/null
	while IFS= read -r line; do
		set_config_line "$BUSYBOX_BUILD/.config" "$line"
	done < "$BUSYBOX_FRAGMENT"
	set +o pipefail
	yes "" | make -C "$BUSYBOX_SRC" O="$BUSYBOX_BUILD" ARCH=riscv \
		CROSS_COMPILE="$BUSYBOX_CROSS_COMPILE" HOSTCC=gcc oldconfig >/dev/null
	local oldconfig_status=$?
	set -o pipefail
	if [[ "$oldconfig_status" -ne 0 && "$oldconfig_status" -ne 141 ]]; then
		exit "$oldconfig_status"
	fi
	make -C "$BUSYBOX_SRC" O="$BUSYBOX_BUILD" ARCH=riscv \
		CROSS_COMPILE="$BUSYBOX_CROSS_COMPILE" HOSTCC=gcc -j"$JOBS" busybox
	cp "$BUSYBOX_BUILD/busybox" "$BUSYBOX_BIN"
	"${BUSYBOX_CROSS_COMPILE}strip" "$BUSYBOX_BIN"
	info "BusyBox: $BUSYBOX_BIN"
}

build_initramfs() {
	fetch_linux_src
	[[ -x "$BUSYBOX_BIN" ]] || build_busybox
	mkdir -p "$OUT_DIR"
	local root="$BUILD_DIR/initramfs-root"
	local list="$BUILD_DIR/initramfs.list"
	local gic="$BUILD_DIR/gen_init_cpio"
	local init_src="$PROJECT_ROOT/initramfs/karu64-rv64imac"
	rm -rf "$root"
	mkdir -p "$root/usr/bin" "$root/usr/sbin" "$root/usr/share/udhcpc" \
		"$root/opt/tests" "$root/etc" "$root/proc" "$root/sys" "$root/tmp" "$root/run" "$root/root"
	cp "$BUSYBOX_BIN" "$root/usr/bin/busybox"
	chmod 0755 "$root/usr/bin/busybox"
	ln -sf busybox "$root/usr/bin/sh"
	cp "$init_src/udhcpc.script" "$root/usr/share/udhcpc/default.script"
	chmod 0755 "$root/usr/share/udhcpc/default.script"
	cp "$init_src/init" "$BUILD_DIR/init"
	chmod 0755 "$BUILD_DIR/init"
	"${BUSYBOX_CROSS_COMPILE}gcc" -march=rv64imac -mabi=lp64 -Os -static \
		-nostdlib -ffreestanding "$init_src/hello.c" -o "$root/opt/tests/hello-static"
	[[ -x "$gic" ]] || gcc -O2 -o "$gic" "$LINUX_SRC/usr/gen_init_cpio.c"
	{
		echo "dir /proc 0755 0 0"
		echo "dir /sys 0755 0 0"
		echo "dir /tmp 1777 0 0"
		echo "dir /run 0755 0 0"
		echo "dir /root 0700 0 0"
		echo "dir /dev 0755 0 0"
		echo "nod /dev/console 0600 0 0 c 5 1"
		echo "nod /dev/null 0666 0 0 c 1 3"
		echo "nod /dev/tty 0666 0 0 c 5 0"
		echo "nod /dev/ttyS0 0600 0 0 c 4 64"
		echo "slink /bin  usr/bin  0777 0 0"
		echo "slink /sbin usr/sbin 0777 0 0"
		echo "slink /lib  usr/lib  0777 0 0"
		echo "file /init $BUILD_DIR/init 0755 0 0"
		cd "$root"
		find . -mindepth 1 \( -type d -o -type l -o -type f \) -print | sort | while read -r p; do
			local rel mode
			rel="${p#.}"
			mode="$(stat -c '%a' "$p")"
			if [[ -d "$p" ]]; then
				echo "dir $rel 0$mode 0 0"
			elif [[ -L "$p" ]]; then
				echo "slink $rel $(readlink "$p") 0$mode 0 0"
			else
				echo "file $rel $root$rel 0$mode 0 0"
			fi
		done
	} > "$list"
	"$gic" "$list" | gzip -9 > "$INITRD_GZ"
	info "Initramfs: $INITRD_GZ ($(du -h "$INITRD_GZ" | cut -f1))"
}

dtb_source() {
	case "$DTB_VARIANT" in
		sim|linux_tb) printf '%s\n' "$PROJECT_ROOT/configs/karu64-rv64imac-sim.dts" ;;
		ddr|hardware) printf '%s\n' "$PROJECT_ROOT/configs/karu64-rv64imac-ddr.dts" ;;
		vec|vector) printf '%s\n' "$PROJECT_ROOT/configs/karu64-vec-ddr.dts" ;;
		*) die "DTB_VARIANT must be sim, ddr, or vec" ;;
	esac
}

build_dtb() {
	[[ -f "$INITRD_GZ" ]] || build_initramfs
	mkdir -p "$OUT_DIR"
	local dts initrd_size initrd_start initrd_end
	dts="$(dtb_source)"
	initrd_size="$(sz "$INITRD_GZ")"
	initrd_start=$((RAM_BASE + INITRD_OFF))
	initrd_end=$((initrd_start + initrd_size))
	dtc -I dts -O dtb -o "$BOARD_DTB" "$dts"
	fdtput -cp "$BOARD_DTB" /chosen 2>/dev/null || true
	fdtput -t u "$BOARD_DTB" /chosen linux,initrd-start "$initrd_start"
	fdtput -t u "$BOARD_DTB" /chosen linux,initrd-end "$initrd_end"
	info "DTB: $BOARD_DTB ($DTB_VARIANT, initrd $(hx "$initrd_start")..$(hx "$initrd_end"))"
}

check_layout() {
	local label="$1" off="$2" size="$3" next_label="$4" next_off="$5"
	local off_dec=$((off))
	local next_dec=$((next_off))
	local end=$((off_dec + size))
	[[ "$end" -le "$next_dec" ]] || \
		die "$label [$(hx $((RAM_BASE + off_dec)))..$(hx $((RAM_BASE + end)))] overlaps $next_label at $(hx $((RAM_BASE + next_dec)))"
}

build_bundle() {
	[[ -f "$FW_BIN" ]] || build_opensbi
	[[ -f "$KERNEL_IMAGE" ]] || build_kernel
	[[ -f "$INITRD_GZ" ]] || build_initramfs
	build_dtb
	local fw_sz kernel_sz initrd_sz dtb_sz img_end gz_sz payload
	fw_sz="$(sz "$FW_BIN")"
	kernel_sz="$(sz "$KERNEL_IMAGE")"
	initrd_sz="$(sz "$INITRD_GZ")"
	dtb_sz="$(sz "$BOARD_DTB")"
	check_layout "OpenSBI" "$FW_OFF" "$fw_sz" "kernel" "$KERNEL_OFF"
	check_layout "kernel" "$KERNEL_OFF" "$kernel_sz" "initrd" "$INITRD_OFF"
	check_layout "initrd" "$INITRD_OFF" "$initrd_sz" "board-DTB" "$DTB_OFF"
	check_layout "board-DTB" "$DTB_OFF" "$dtb_sz" "FDT-target" "$FDT_OFF"
	[[ $((FDT_OFF + dtb_sz)) -le $((RAM_SIZE)) ]] || die "relocated FDT exceeds RAM top"
	img_end=$((DTB_OFF + dtb_sz))
	for e in $((FW_OFF + fw_sz)) $((KERNEL_OFF + kernel_sz)) $((INITRD_OFF + initrd_sz)); do
		[[ "$e" -gt "$img_end" ]] && img_end="$e"
	done
	[[ "$img_end" -le $((RAM_SIZE)) ]] || die "flat image end exceeds RAM top"
	truncate -s "$img_end" "$FLAT_IMG"
	dd if="$FW_BIN"       of="$FLAT_IMG" bs=1M oflag=seek_bytes seek=$((FW_OFF))     conv=notrunc status=none
	dd if="$KERNEL_IMAGE" of="$FLAT_IMG" bs=1M oflag=seek_bytes seek=$((KERNEL_OFF)) conv=notrunc status=none
	dd if="$INITRD_GZ"    of="$FLAT_IMG" bs=1M oflag=seek_bytes seek=$((INITRD_OFF)) conv=notrunc status=none
	dd if="$BOARD_DTB"    of="$FLAT_IMG" bs=1M oflag=seek_bytes seek=$((DTB_OFF))    conv=notrunc status=none
	gzip -9 -n -k -f "$FLAT_IMG"
	gz_sz="$(sz "$FLAT_GZ")"
	payload=$((fw_sz + kernel_sz + initrd_sz + dtb_sz))
	cat > "$OUT_DIR/layout.env" <<EOF
RAM_BASE=$((RAM_BASE))
RAM_SIZE=$((RAM_SIZE))
FW_OFF=$((FW_OFF))
KERNEL_OFF=$((KERNEL_OFF))
INITRD_OFF=$((INITRD_OFF))
INITRD_SIZE=$initrd_sz
INITRD_START=$((RAM_BASE + INITRD_OFF))
INITRD_END=$((RAM_BASE + INITRD_OFF + initrd_sz))
DTB_OFF=$((DTB_OFF))
DTB_ADDR=$((RAM_BASE + DTB_OFF))
FDT_OFF=$((FDT_OFF))
IMG_END=$img_end
EOF
	cp "$KERNEL_IMAGE" "$OUT_DIR/Image"
	info ""
	info "karu64 flat boot bundle -> $FLAT_GZ"
	printf '  %-14s %-12s %-12s %10s\n' component load-addr offset size
	printf '  %-14s %-12s %-12s %10d\n' OpenSBI "$(hx $((RAM_BASE + FW_OFF)))" "$(hx "$FW_OFF")" "$fw_sz"
	printf '  %-14s %-12s %-12s %10d\n' kernel  "$(hx $((RAM_BASE + KERNEL_OFF)))" "$(hx "$KERNEL_OFF")" "$kernel_sz"
	printf '  %-14s %-12s %-12s %10d\n' initrd  "$(hx $((RAM_BASE + INITRD_OFF)))" "$(hx "$INITRD_OFF")" "$initrd_sz"
	printf '  %-14s %-12s %-12s %10d\n' board.dtb "$(hx $((RAM_BASE + DTB_OFF)))" "$(hx "$DTB_OFF")" "$dtb_sz"
	awk -v p="$payload" -v f="$img_end" -v g="$gz_sz" 'BEGIN {
		printf "  raw payload: %9d bytes (%.2f MiB)\n", p, p / 1048576;
		printf "  flat.img   : %9d bytes (%.2f MiB)\n", f, f / 1048576;
		printf "  flat.img.gz: %9d bytes (%.2f MiB)\n", g, g / 1048576;
	}'
}

stage_tftp() {
	[[ -f "$KERNEL_IMAGE" ]] || build_kernel
	[[ -f "$INITRD_GZ" ]] || build_initramfs
	build_dtb
	local tftp_dir="${TFTP_DIR:-$PROJECT_ROOT/build/karu64-rv64imac-tftp}"
	local kernel_addr="${KERNEL_ADDR:-0x80200000}"
	local initrd_addr="${INITRD_ADDR:-}"
	local dtb_addr="${DTB_ADDR:-}"
	local initrd_size
	case "$DTB_VARIANT" in
		sim|linux_tb)
			initrd_addr="${initrd_addr:-0x81200000}"
			dtb_addr="${dtb_addr:-0x81b00000}"
			;;
		ddr|hardware)
			initrd_addr="${initrd_addr:-0x83000000}"
			dtb_addr="${dtb_addr:-0x84000000}"
			;;
	esac
	initrd_size="$(sz "$INITRD_GZ")"
	mkdir -p "$tftp_dir"
	cp "$KERNEL_IMAGE" "$tftp_dir/Image"
	cp "$INITRD_GZ" "$tftp_dir/initramfs.cpio.gz"
	cp "$BOARD_DTB" "$tftp_dir/board.dtb"
	fdtput -t u "$tftp_dir/board.dtb" /chosen linux,initrd-start "$((initrd_addr))"
	fdtput -t u "$tftp_dir/board.dtb" /chosen linux,initrd-end "$((initrd_addr + initrd_size))"
	cat > "$tftp_dir/uboot-initramfs.cmd" <<EOF
setenv serverip \${serverip}
tftpboot $kernel_addr Image
tftpboot $initrd_addr initramfs.cpio.gz
tftpboot $dtb_addr board.dtb
setenv bootargs console=ttyS0,115200 earlycon
booti $kernel_addr $initrd_addr:$initrd_size $dtb_addr
EOF
	{
		printf 'tftpboot %s Image; ' "$kernel_addr"
		printf 'tftpboot %s initramfs.cpio.gz; ' "$initrd_addr"
		printf 'tftpboot %s board.dtb; ' "$dtb_addr"
		printf 'setenv bootargs console=ttyS0,115200 earlycon; '
		printf 'booti %s %s:%s %s\n' "$kernel_addr" "$initrd_addr" "$initrd_size" "$dtb_addr"
	} > "$tftp_dir/uboot-initramfs-one-line.txt"
	info "TFTP staged in $tftp_dir"
	info "U-Boot one-line command:"
	sed -n '1p' "$tftp_dir/uboot-initramfs-one-line.txt"
}

usage() {
	cat <<EOF
usage: $0 [check|opensbi|kernel|busybox|initramfs|dtb|bundle|stage-tftp|all|clean]

Defaults:
  BUILD_DIR=$BUILD_DIR
  KERNEL_VERSION=$KERNEL_VERSION
  DTB_VARIANT=$DTB_VARIANT
  OPENSBI_OUT_DIR=$OPENSBI_OUT_DIR
  KERNEL_CROSS_COMPILE=$KERNEL_CROSS_COMPILE
  BUSYBOX_CROSS_COMPILE=$BUSYBOX_CROSS_COMPILE
EOF
}

main() {
	select_linux_src
	select_opensbi_src
	select_busybox_src
	local action="${1:-all}"
	case "$action" in
		check) check_tools ;;
		opensbi) check_tools; build_opensbi ;;
		kernel) check_tools; build_kernel ;;
		busybox) check_tools; build_busybox ;;
		initramfs) check_tools; build_initramfs ;;
		dtb) check_tools; build_dtb ;;
		bundle|all) check_tools; build_bundle ;;
		stage-tftp) check_tools; stage_tftp ;;
		clean) rm -rf "$BUILD_DIR" "${TFTP_DIR:-$PROJECT_ROOT/build/karu64-rv64imac-tftp}" ;;
		-h|--help|help) usage ;;
		*) usage; exit 2 ;;
	esac
}

main "$@"
