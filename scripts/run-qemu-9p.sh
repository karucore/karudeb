#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ROOTFS_DIR="${ROOTFS_DIR:-$PROJECT_ROOT/build/rootfs-9p}"
KERNEL="${KERNEL:-${1:-$PROJECT_ROOT/build/linux-riscv64/arch/riscv/boot/Image}}"
INITRD="${INITRD:-}"
DTB="${DTB:-}"

NINEP_TAG="${NINEP_TAG:-rootfs}"
NINEP_ID="${NINEP_ID:-rootfs9p}"
NINEP_SECURITY_MODEL="${NINEP_SECURITY_MODEL:-mapped-xattr}"
NINEP_CACHE="${NINEP_CACHE:-none}"
NINEP_MSIZE="${NINEP_MSIZE:-512000}"
NINEP_ACCESS="${NINEP_ACCESS:-any}"
NINEP_MULTIDEVS="${NINEP_MULTIDEVS:-remap}"
NINEP_WRITEOUT="${NINEP_WRITEOUT:-}"

NET_MODE="${NET_MODE:-user}"
TAP_IF="${TAP_IF:-tap-karudeb}"
HOST_CIDR="${HOST_CIDR:-192.168.76.1/24}"

MEMORY="${MEMORY:-4G}"
SMP="${SMP:-2}"
QEMU_MACHINE="${QEMU_MACHINE:-virt}"
QEMU_CPU="${QEMU_CPU:-rv64,v=true,vlen=256,elen=64}"
QEMU_BIOS="${QEMU_BIOS:-default}"
QEMU_NET_DEVICE="${QEMU_NET_DEVICE:-virtio-net-device}"
QEMU_USER_HOSTFWD="${QEMU_USER_HOSTFWD:-hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:5901-:5901}"
QEMU_EXTRA_ARGS="${QEMU_EXTRA_ARGS:-}"
APPEND_EXTRA="${APPEND_EXTRA:-}"

ROOTFS_DIR="$(abs_path "$ROOTFS_DIR")"
KERNEL="$(abs_path "$KERNEL")"

if [[ ! -d "$ROOTFS_DIR" && "$ROOTFS_DIR" == "$PROJECT_ROOT/build/rootfs-9p" ]]; then
  "$SCRIPT_DIR/install-9p-root.sh"
fi

[[ -d "$ROOTFS_DIR" ]] || die "rootfs directory not found: $ROOTFS_DIR"
[[ -f "$KERNEL" ]] || die "kernel image not found: $KERNEL"
need_cmd qemu-system-riscv64 qemu-system-riscv

if [[ ! -r "$ROOTFS_DIR/etc/shadow" ]]; then
  die "$ROOTFS_DIR/etc/shadow is not readable by this user; use install-9p-root.sh to create a user-owned 9p rootfs"
fi

fsdev="local,id=$NINEP_ID,path=$ROOTFS_DIR,security_model=$NINEP_SECURITY_MODEL,multidevs=$NINEP_MULTIDEVS"
if [[ -n "$NINEP_WRITEOUT" ]]; then
  fsdev="$fsdev,writeout=$NINEP_WRITEOUT"
fi

netdev_args=()
net_append=""
case "$NET_MODE" in
  none)
    ;;
  user)
    user_netdev="user,id=net0"
    if [[ -n "$QEMU_USER_HOSTFWD" ]]; then
      user_netdev="$user_netdev,$QEMU_USER_HOSTFWD"
    fi
    netdev_args=(-netdev "$user_netdev" -device "$QEMU_NET_DEVICE,netdev=net0")
    net_append="ip=dhcp"
    ;;
  tap)
    TAP_IF="$TAP_IF" HOST_CIDR="$HOST_CIDR" "$SCRIPT_DIR/setup-tap.sh" up
    netdev_args=(-netdev "tap,id=net0,ifname=$TAP_IF,script=no,downscript=no" -device "$QEMU_NET_DEVICE,netdev=net0")
    net_append="${IP_PARAM:+ip=$IP_PARAM}"
    ;;
  *)
    die "NET_MODE must be none, user, or tap"
    ;;
esac

rootflags="trans=virtio,version=9p2000.L,cache=$NINEP_CACHE,msize=$NINEP_MSIZE,access=$NINEP_ACCESS"
append="${APPEND:-console=ttyS0,115200 earlycon=sbi root=$NINEP_TAG rootfstype=9p rootflags=$rootflags rw $net_append $APPEND_EXTRA}"

args=(
  -machine "$QEMU_MACHINE"
  -cpu "$QEMU_CPU"
  -m "$MEMORY"
  -smp "$SMP"
  -nographic
  -bios "$QEMU_BIOS"
  -kernel "$KERNEL"
  -append "$append"
  -fsdev "$fsdev"
  -device "virtio-9p-device,fsdev=$NINEP_ID,mount_tag=$NINEP_TAG"
  "${netdev_args[@]}"
)

if [[ -n "$INITRD" ]]; then
  args+=(-initrd "$INITRD")
fi

if [[ -n "$DTB" ]]; then
  args+=(-dtb "$DTB")
fi

if [[ -n "$QEMU_EXTRA_ARGS" ]]; then
  # Intentionally shell-split for command-line style overrides.
  # shellcheck disable=SC2206
  extra_args=($QEMU_EXTRA_ARGS)
  args+=("${extra_args[@]}")
fi

info "Kernel: $KERNEL"
info "9p rootfs: $ROOTFS_DIR"
info "Append: $append"
exec qemu-system-riscv64 "${args[@]}"
