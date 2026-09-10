#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ROOTFS_DIR="${ROOTFS_DIR:-$PROJECT_ROOT/build/rootfs}"
KERNEL="${KERNEL:-${1:-$PROJECT_ROOT/build/linux-riscv64/arch/riscv/boot/Image}}"
INITRD="${INITRD:-}"
DTB="${DTB:-}"

NET_MODE="${NET_MODE:-tap}"
TAP_IF="${TAP_IF:-tap-karudeb}"
HOST_CIDR="${HOST_CIDR:-192.168.76.1/24}"
NFS_SERVER="${NFS_SERVER:-192.168.76.1}"
GUEST_IP="${GUEST_IP:-192.168.76.2}"
GATEWAY_IP="${GATEWAY_IP:-$NFS_SERVER}"
NETMASK="${NETMASK:-255.255.255.0}"
KARUDEB_HOSTNAME="${KARUDEB_HOSTNAME:-karudeb}"
NFS_OPTS="${NFS_OPTS:-vers=3,tcp,nolock}"

MEMORY="${MEMORY:-4G}"
SMP="${SMP:-2}"
QEMU_MACHINE="${QEMU_MACHINE:-virt}"
QEMU_CPU="${QEMU_CPU:-rv64,v=true,vlen=256,elen=64}"
QEMU_SYSTEM="${QEMU_SYSTEM:-qemu-system-riscv64}"
QEMU_BIOS="${QEMU_BIOS:-default}"
QEMU_NET_DEVICE="${QEMU_NET_DEVICE:-virtio-net-device}"
QEMU_EXTRA_ARGS="${QEMU_EXTRA_ARGS:-}"
APPEND_EXTRA="${APPEND_EXTRA:-}"

ROOTFS_DIR="$(abs_path "$ROOTFS_DIR")"
KERNEL="$(abs_path "$KERNEL")"

[[ -d "$ROOTFS_DIR" ]] || die "rootfs directory not found: $ROOTFS_DIR"
[[ -f "$KERNEL" ]] || die "kernel image not found: $KERNEL"
need_cmd "$QEMU_SYSTEM" qemu-system-riscv

rootfs_uid="$(stat -c %u "$ROOTFS_DIR")"
if [[ "$rootfs_uid" != "0" && "${ALLOW_SHIFTED_NFS:-0}" != "1" ]]; then
  die "rootfs is host-owned by uid $rootfs_uid, not root. Install the packaged rootfs into a root-owned NFS export directory first"
fi

netdev_args=()
ip_param="${IP_PARAM:-$GUEST_IP:$NFS_SERVER:$GATEWAY_IP:$NETMASK:$KARUDEB_HOSTNAME:eth0:off}"

case "$NET_MODE" in
  tap)
    TAP_IF="$TAP_IF" HOST_CIDR="$HOST_CIDR" "$SCRIPT_DIR/setup-tap.sh" up
    netdev_args=(-netdev "tap,id=net0,ifname=$TAP_IF,script=no,downscript=no")
    ;;
  user)
    netdev_args=(-netdev "user,id=net0,hostfwd=tcp::2222-:22")
    ip_param="${IP_PARAM:-dhcp}"
    if [[ "${NFS_SERVER_SET:-0}" != "1" && "$NFS_SERVER" == "192.168.76.1" ]]; then
      NFS_SERVER="10.0.2.2"
    fi
    ;;
  *)
    die "NET_MODE must be tap or user"
    ;;
esac

nfsroot="${NFSROOT:-$NFS_SERVER:$ROOTFS_DIR,$NFS_OPTS}"
append="${APPEND:-console=ttyS0,115200 earlycon=sbi root=/dev/nfs rw ip=$ip_param nfsroot=$nfsroot $APPEND_EXTRA}"

args=(
  -machine "$QEMU_MACHINE"
  -cpu "$QEMU_CPU"
  -m "$MEMORY"
  -smp "$SMP"
  -nographic
  -bios "$QEMU_BIOS"
  -kernel "$KERNEL"
  -append "$append"
  "${netdev_args[@]}"
  -device "$QEMU_NET_DEVICE,netdev=net0"
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
info "Rootfs: $ROOTFS_DIR"
info "Append: $append"
exec "$QEMU_SYSTEM" "${args[@]}"
