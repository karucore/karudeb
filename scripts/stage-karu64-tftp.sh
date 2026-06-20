#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

DTB_VARIANT="${DTB_VARIANT:-ddr}"
KERNEL="${KERNEL:-}"
DTB="${DTB:-}"
OUT_DIR="${OUT_DIR:-}"
TFTP_ROOT="${TFTP_ROOT:-}"

TFTP_SERVER="${TFTP_SERVER:-192.168.1.20}"
NFS_SERVER="${NFS_SERVER:-$TFTP_SERVER}"
GUEST_IP="${GUEST_IP:-192.168.1.10}"
GATEWAY_IP="${GATEWAY_IP:-$NFS_SERVER}"
NETMASK="${NETMASK:-255.255.255.0}"
KARUDEB_HOSTNAME="${KARUDEB_HOSTNAME:-karudeb}"
NFSROOT="${NFSROOT:-/srv/nfs/karudeb}"
NFS_OPTS="${NFS_OPTS:-vers=3,tcp,nolock}"

KERNEL_ADDR="${KERNEL_ADDR:-0x80200000}"
case "$DTB_VARIANT" in
  zvk|zvk-ddr|vector-crypto|vector-crypto-ddr)
    DTB_VARIANT="zvk-ddr"
    DTB_ADDR="${DTB_ADDR:-0x84000000}"
    ;;
  rv64gc|gc|rv64gc-ddr)
    DTB_VARIANT="rv64gc-ddr"
    DTB_ADDR="${DTB_ADDR:-0x84000000}"
    ;;
  ddr|hardware)
    DTB_VARIANT="ddr"
    DTB_ADDR="${DTB_ADDR:-0x84000000}"
    ;;
  sim|linux_tb)
    DTB_VARIANT="sim"
    DTB_ADDR="${DTB_ADDR:-0x81300000}"
    ;;
  *)
    die "DTB_VARIANT must be 'zvk-ddr', 'rv64gc-ddr', 'ddr', or 'sim'"
    ;;
esac

if [[ -z "$KERNEL" ]]; then
  case "$DTB_VARIANT" in
    rv64gc-ddr)
      KERNEL="$PROJECT_ROOT/build/linux-riscv64-karu64-rv64gc/arch/riscv/boot/Image"
      ;;
    zvk-ddr)
      KERNEL="$PROJECT_ROOT/build/linux-riscv64-karu64-zvk/arch/riscv/boot/Image"
      ;;
    *)
      KERNEL="$PROJECT_ROOT/build/linux-riscv64-karu64/arch/riscv/boot/Image"
      ;;
  esac
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$PROJECT_ROOT/build/karu64/tftp/$DTB_VARIANT"
fi

DEFAULT_BOOTARGS="console=ttyS0,115200 earlycon root=/dev/nfs rw ip=$GUEST_IP:$NFS_SERVER:$GATEWAY_IP:$NETMASK:$KARUDEB_HOSTNAME:eth0:off nfsroot=$NFS_SERVER:$NFSROOT,$NFS_OPTS"
BOOTARGS="${BOOTARGS:-$DEFAULT_BOOTARGS}"
if [[ -n "${APPEND_EXTRA:-}" ]]; then
  BOOTARGS="$BOOTARGS $APPEND_EXTRA"
fi

KERNEL="$(abs_path "$KERNEL")"
OUT_DIR="$(abs_path "$OUT_DIR")"
[[ -f "$KERNEL" ]] || die "kernel Image not found: $KERNEL"

if [[ -z "$DTB" ]]; then
  DTB="$PROJECT_ROOT/build/karu64/karu64-$DTB_VARIANT.dtb"
  if [[ ! -f "$DTB" ]]; then
    DTB_VARIANT="$DTB_VARIANT" "$SCRIPT_DIR/build-karu64-dtb.sh"
  fi
fi
DTB="$(abs_path "$DTB")"
[[ -f "$DTB" ]] || die "DTB not found: $DTB"

mkdir -p "$OUT_DIR"
cp "$KERNEL" "$OUT_DIR/Image"
cp "$DTB" "$OUT_DIR/board.dtb"
cp "$DTB" "$OUT_DIR/karu64-$DTB_VARIANT.dtb"

cat >"$OUT_DIR/uboot-netboot.cmd" <<EOF
setenv serverip $TFTP_SERVER
setenv ipaddr $GUEST_IP
tftpboot $KERNEL_ADDR Image
tftpboot $DTB_ADDR board.dtb
setenv bootargs $BOOTARGS
booti $KERNEL_ADDR - $DTB_ADDR
EOF
if have_cmd mkimage; then
  mkimage -A riscv -O linux -T script -C none -n "karu64 netboot" \
    -d "$OUT_DIR/uboot-netboot.cmd" "$OUT_DIR/boot.scr" >/dev/null
fi

{
  printf 'setenv serverip %s; ' "$TFTP_SERVER"
  printf 'setenv ipaddr %s; ' "$GUEST_IP"
  printf 'tftpboot %s Image; ' "$KERNEL_ADDR"
  printf 'tftpboot %s board.dtb; ' "$DTB_ADDR"
  printf 'setenv bootargs %s; ' "$BOOTARGS"
  printf 'booti %s - %s\n' "$KERNEL_ADDR" "$DTB_ADDR"
} >"$OUT_DIR/uboot-netboot-one-line.txt"

cat >"$OUT_DIR/layout.env" <<EOF
DTB_VARIANT=$DTB_VARIANT
KERNEL_ADDR=$KERNEL_ADDR
DTB_ADDR=$DTB_ADDR
TFTP_SERVER=$TFTP_SERVER
TFTP_ROOT=$TFTP_ROOT
GUEST_IP=$GUEST_IP
NFS_SERVER=$NFS_SERVER
NFSROOT=$NFSROOT
NFS_OPTS=$NFS_OPTS
BOOTARGS=$BOOTARGS
EOF

if [[ -n "$TFTP_ROOT" ]]; then
  TFTP_ROOT="$(abs_path "$TFTP_ROOT")"
  mkdir -p "$TFTP_ROOT"
  cp "$OUT_DIR/Image" "$TFTP_ROOT/Image"
  cp "$OUT_DIR/board.dtb" "$TFTP_ROOT/board.dtb"
  cp "$OUT_DIR/karu64-$DTB_VARIANT.dtb" "$TFTP_ROOT/karu64-$DTB_VARIANT.dtb"
  cp "$OUT_DIR/uboot-netboot.cmd" "$TFTP_ROOT/uboot-netboot.cmd"
  cp "$OUT_DIR/uboot-netboot-one-line.txt" "$TFTP_ROOT/uboot-netboot-one-line.txt"
  cp "$OUT_DIR/layout.env" "$TFTP_ROOT/layout.env"
  if [[ -f "$OUT_DIR/boot.scr" ]]; then
    cp "$OUT_DIR/boot.scr" "$TFTP_ROOT/boot.scr"
  fi
fi

info "Staged karu64 TFTP files in $OUT_DIR"
info "  Image"
info "  board.dtb ($DTB_VARIANT)"
info "  uboot-netboot.cmd"
info "  uboot-netboot-one-line.txt"
if [[ -f "$OUT_DIR/boot.scr" ]]; then
  info "  boot.scr"
fi
if [[ -n "$TFTP_ROOT" ]]; then
  info "Copied active TFTP files to $TFTP_ROOT"
fi
info ""
info "U-Boot one-line command:"
sed -n '1p' "$OUT_DIR/uboot-netboot-one-line.txt"
info ""
info "For karu64 simulation, use DTB_VARIANT=sim and a TAP-backed NFS setup;"
info "the default in-process TFTP responder does not provide NFS."
