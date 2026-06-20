#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

DTB_VARIANT="${DTB_VARIANT:-ddr}"
OUT_DIR="${OUT_DIR:-$PROJECT_ROOT/build/karu64}"

case "$DTB_VARIANT" in
  rv64imac|imac|rv64imac-ddr|imac-ddr)
    DTB_VARIANT="rv64imac-ddr"
    DTS="${DTS:-$PROJECT_ROOT/configs/karu64-rv64imac-ddr.dts}"
    ;;
  rv64imac-sim|imac-sim)
    DTB_VARIANT="rv64imac-sim"
    DTS="${DTS:-$PROJECT_ROOT/configs/karu64-rv64imac-sim.dts}"
    ;;
  zvk|zvk-ddr|vector-crypto|vector-crypto-ddr)
    DTB_VARIANT="zvk-ddr"
    DTS="${DTS:-$PROJECT_ROOT/configs/karu64-zvk-nfsroot-ddr.dts}"
    ;;
  rv64gc|gc|rv64gc-ddr)
    DTB_VARIANT="rv64gc-ddr"
    DTS="${DTS:-$PROJECT_ROOT/configs/karu64-rv64gc-nfsroot-ddr.dts}"
    ;;
  ddr|hardware)
    DTB_VARIANT="ddr"
    DTS="${DTS:-$PROJECT_ROOT/configs/karu64-nfsroot-ddr.dts}"
    ;;
  sim|linux_tb)
    DTB_VARIANT="sim"
    DTS="${DTS:-$PROJECT_ROOT/configs/karu64-nfsroot-sim.dts}"
    ;;
  *)
    die "DTB_VARIANT must be 'rv64imac-ddr', 'zvk-ddr', 'rv64gc-ddr', 'ddr', or 'sim'"
    ;;
esac

DTS="$(abs_path "$DTS")"
OUT_DIR="$(abs_path "$OUT_DIR")"
OUT="${OUT:-$OUT_DIR/karu64-$DTB_VARIANT.dtb}"
OUT="$(abs_path "$OUT")"

[[ -f "$DTS" ]] || die "DTS not found: $DTS"
need_cmd dtc device-tree-compiler
mkdir -p "$(dirname "$OUT")"

dtc -I dts -O dtb -o "$OUT" "$DTS"

info "DTB variant: $DTB_VARIANT"
info "DTS: $DTS"
info "DTB: $OUT"
