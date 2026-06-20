#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ACTION="${1:-up}"
TAP_IF="${TAP_IF:-tap-karudeb}"
TAP_USER="${TAP_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"
HOST_CIDR="${HOST_CIDR:-192.168.76.1/24}"

need_cmd ip iproute2

case "$ACTION" in
  up)
    if ! ip link show "$TAP_IF" >/dev/null 2>&1; then
      as_root ip tuntap add dev "$TAP_IF" mode tap user "$TAP_USER"
    fi
    if ! ip -brief addr show dev "$TAP_IF" | grep -q "$HOST_CIDR"; then
      as_root ip addr flush dev "$TAP_IF"
      as_root ip addr add "$HOST_CIDR" dev "$TAP_IF"
    fi
    as_root ip link set "$TAP_IF" up
    info "$TAP_IF up as $HOST_CIDR for user $TAP_USER"
    ;;
  down)
    if ip link show "$TAP_IF" >/dev/null 2>&1; then
      as_root ip link delete "$TAP_IF"
    fi
    info "$TAP_IF removed"
    ;;
  status)
    ip addr show "$TAP_IF"
    ;;
  *)
    die "usage: $0 [up|down|status]"
    ;;
esac

