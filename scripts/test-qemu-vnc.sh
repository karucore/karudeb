#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

COMMAND="${1:-start}"

ROOTFS_DIR="${ROOTFS_DIR:-$PROJECT_ROOT/build/rootfs-jwm-vnc}"
ROOTFS_TAR="${ROOTFS_TAR:-$PROJECT_ROOT/build/karudeb-riscv64-jwm-vnc-rootfs.tar.zst}"
ROOTFS_IMAGE="${ROOTFS_IMAGE:-$PROJECT_ROOT/build/rootfs-jwm-vnc.ext4}"
EXT4_SRC="${EXT4_SRC:-$PROJECT_ROOT/build/rootfs-jwm-vnc-ext4-src}"
IMAGE_SIZE="${IMAGE_SIZE:-3072M}"
KARUDEB_SSH_AUTHORIZED_KEYS="${KARUDEB_SSH_AUTHORIZED_KEYS:-$PROJECT_ROOT/configs/ssh/karudeb_lab_ed25519.pub}"

KERNEL="${KERNEL:-$PROJECT_ROOT/build/linux-riscv64/arch/riscv/boot/Image}"
BUILD_KERNEL_IF_MISSING="${BUILD_KERNEL_IF_MISSING:-1}"
QEMU_PID_FILE="${QEMU_PID_FILE:-$PROJECT_ROOT/build/qemu-vnc.pid}"
QEMU_LOG_FILE="${QEMU_LOG_FILE:-$PROJECT_ROOT/build/qemu-vnc.log}"
QEMU_ERR_FILE="${QEMU_ERR_FILE:-$PROJECT_ROOT/build/qemu-vnc.err}"

VNC_HOST="${VNC_HOST:-127.0.0.1}"
VNC_HOST_PORT="${VNC_HOST_PORT:-5901}"
SSH_HOST_PORT="${SSH_HOST_PORT:-2222}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"

MEMORY="${MEMORY:-2G}"
SMP="${SMP:-1}"
QEMU_MACHINE="${QEMU_MACHINE:-virt}"
QEMU_CPU="${QEMU_CPU:-rv64,v=true,vlen=256,elen=64}"
QEMU_BIOS="${QEMU_BIOS:-default}"
QEMU_NET_DEVICE="${QEMU_NET_DEVICE:-virtio-net-device}"
QEMU_EXTRA_ARGS="${QEMU_EXTRA_ARGS:-}"
APPEND_EXTRA="${APPEND_EXTRA:-}"
E2FSCK_ON_STOP="${E2FSCK_ON_STOP:-1}"

ROOTFS_DIR="$(abs_path "$ROOTFS_DIR")"
ROOTFS_TAR="$(abs_path "$ROOTFS_TAR")"
ROOTFS_IMAGE="$(abs_path "$ROOTFS_IMAGE")"
EXT4_SRC="$(abs_path "$EXT4_SRC")"
KARUDEB_SSH_AUTHORIZED_KEYS="$(abs_path "$KARUDEB_SSH_AUTHORIZED_KEYS")"
KERNEL="$(abs_path "$KERNEL")"
QEMU_PID_FILE="$(abs_path "$QEMU_PID_FILE")"
QEMU_LOG_FILE="$(abs_path "$QEMU_LOG_FILE")"
QEMU_ERR_FILE="$(abs_path "$QEMU_ERR_FILE")"

usage() {
  cat <<'EOF'
Usage:
  scripts/test-qemu-vnc.sh [start|status|probe|stop|image]

Default command is start.

Commands:
  start   build missing generated artifacts, launch detached QEMU, wait for VNC
  status  show QEMU process and forwarded port state
  probe   connect to the forwarded VNC socket and print the RFB banner
  stop    terminate the detached QEMU process
  image   build or rebuild only the ext4 VNC root image

Common overrides:
  KERNEL=build/linux-riscv64/arch/riscv/boot/Image
  BUILD_KERNEL_IF_MISSING=1
  ROOTFS_DIR=build/rootfs-jwm-vnc
  ROOTFS_TAR=build/karudeb-riscv64-jwm-vnc-rootfs.tar.zst
  ROOTFS_IMAGE=build/rootfs-jwm-vnc.ext4
  VNC_HOST_PORT=5901
  SSH_HOST_PORT=2222
  KARUDEB_SSH_AUTHORIZED_KEYS=configs/ssh/karudeb_lab_ed25519.pub
  KARUDEB_SSH_HOST_ED25519_KEY=configs/ssh/karudeb_host_ed25519_key
  WAIT_TIMEOUT=300
  FORCE_IMAGE=1
EOF
}

require_tool() {
  local cmd="$1"
  local pkg="$2"
  local role="$3"

  if have_cmd "$cmd"; then
    return 0
  fi
  printf 'missing %-24s %s (package: %s)\n' "$cmd" "$role" "$pkg" >&2
  return 1
}

check_tools() {
  local missing=0

  for spec in "$@"; do
    local cmd="${spec%%:*}"
    local rest="${spec#*:}"
    local pkg="${rest%%:*}"
    local role="${rest#*:}"
    require_tool "$cmd" "$pkg" "$role" || missing=1
  done

  if [[ "$missing" -ne 0 ]]; then
    die "missing required host tools"
  fi
}

remove_generated_path() {
  local path="$1"
  local abs

  abs="$(abs_path "$path")"
  [[ "$abs" != "/" ]] || die "refusing to remove /"
  [[ "$abs" == "$PROJECT_ROOT"/build/* || "${ALLOW_VNC_TEST_OUTSIDE_BUILD:-0}" == "1" ]] || \
    die "refusing to remove '$abs'; set ALLOW_VNC_TEST_OUTSIDE_BUILD=1 if this is intentional"
  rm -rf "$abs"
}

pid_is_qemu() {
  local pid="$1"
  local cmdline

  [[ -n "$pid" ]] || return 1
  [[ -r "/proc/$pid/cmdline" ]] || return 1
  cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline")"
  [[ "$cmdline" == *qemu-system-riscv64* && "$cmdline" == *"$ROOTFS_IMAGE"* ]]
}

qemu_pid() {
  local pid

  [[ -f "$QEMU_PID_FILE" ]] || return 1
  pid="$(tr -d '[:space:]' <"$QEMU_PID_FILE")"
  pid_is_qemu "$pid" || return 1
  printf '%s\n' "$pid"
}

port_listening() {
  local port="$1"

  have_cmd ss || return 1
  ss -ltn | awk -v port=":$port" '$4 ~ port "$" {found = 1} END {exit found ? 0 : 1}'
}

probe_vnc_banner() {
  timeout 3 bash -c \
    'exec 3<>"/dev/tcp/$0/$1"; head -c 12 <&3' \
    "$VNC_HOST" "$VNC_HOST_PORT" 2>/dev/null || true
}

wait_for_vnc() {
  local end=$((SECONDS + WAIT_TIMEOUT))
  local banner
  local pid

  info "Waiting up to ${WAIT_TIMEOUT}s for VNC on ${VNC_HOST}:${VNC_HOST_PORT}"
  while (( SECONDS < end )); do
    if ! pid="$(qemu_pid 2>/dev/null)"; then
      die "QEMU exited before VNC became reachable; see $QEMU_ERR_FILE and $QEMU_LOG_FILE"
    fi
    banner="$(probe_vnc_banner)"
    if [[ "$banner" == RFB* ]]; then
      info "VNC ready: $banner"
      return 0
    fi
    sleep 2
  done

  die "timed out waiting for VNC on ${VNC_HOST}:${VNC_HOST_PORT}; see $QEMU_LOG_FILE"
}

ensure_vnc_rootfs_archive() {
  local root_ssh_authorized_keys

  if [[ -f "$ROOTFS_TAR" ]]; then
    return 0
  fi

  root_ssh_authorized_keys="${ROOT_SSH_AUTHORIZED_KEYS:-$KARUDEB_SSH_AUTHORIZED_KEYS}"

  if [[ ! -d "$ROOTFS_DIR" ]]; then
    info "Building VNC rootfs: $ROOTFS_DIR"
    KARUDEB_JWM_VNC=1 \
      KARUDEB_SSH_AUTHORIZED_KEYS="$KARUDEB_SSH_AUTHORIZED_KEYS" \
      KARUDEB_SSH_HOST_ED25519_KEY="${KARUDEB_SSH_HOST_ED25519_KEY-$PROJECT_ROOT/configs/ssh/karudeb_host_ed25519_key}" \
      ROOT_SSH_AUTHORIZED_KEYS="$root_ssh_authorized_keys" \
      ROOTFS_DIR="$ROOTFS_DIR" \
      "$SCRIPT_DIR/build-rootfs.sh"
  fi

  [[ -f "$ROOTFS_DIR/etc/default/karudeb-vnc" ]] || \
    die "$ROOTFS_DIR does not look like a VNC rootfs; rebuild it with KARUDEB_JWM_VNC=1"

  info "Packaging VNC rootfs archive: $ROOTFS_TAR"
  ROOTFS_DIR="$ROOTFS_DIR" OUT="$ROOTFS_TAR" "$SCRIPT_DIR/package-rootfs.sh"
}

extract_rootfs_archive() {
  case "$ROOTFS_TAR" in
    *.tar.zst|*.tzst)
      check_tools "zstdcat:zstd:extract zstd-compressed rootfs archive"
      zstdcat "$ROOTFS_TAR" | tar --numeric-owner --no-acls --xattrs \
        --exclude='./dev/*' --exclude='dev/*' -C "$EXT4_SRC" -xf -
      ;;
    *.tar.gz|*.tgz)
      check_tools "gzip:gzip:extract gzip-compressed rootfs archive"
      gzip -dc "$ROOTFS_TAR" | tar --numeric-owner --no-acls --xattrs \
        --exclude='./dev/*' --exclude='dev/*' -C "$EXT4_SRC" -xf -
      ;;
    *.tar)
      tar --numeric-owner --no-acls --xattrs \
        --exclude='./dev/*' --exclude='dev/*' -C "$EXT4_SRC" -xf "$ROOTFS_TAR"
      ;;
    *)
      die "unsupported rootfs archive extension: $ROOTFS_TAR"
      ;;
  esac
}

build_ext4_image_inside_fakeroot() {
  local tmp_image="$ROOTFS_IMAGE.tmp"

  check_tools \
    "tar:tar:extract rootfs archive" \
    "truncate:coreutils:create sparse ext4 image" \
    "mkfs.ext4:e2fsprogs:populate ext4 root image"

  remove_generated_path "$EXT4_SRC"
  install -d -m 0755 "$EXT4_SRC"

  extract_rootfs_archive

  [[ -f "$EXT4_SRC/etc/default/karudeb-vnc" ]] || \
    die "$ROOTFS_TAR does not contain /etc/default/karudeb-vnc; rebuild the archive with KARUDEB_JWM_VNC=1"

  install -d -m 0755 -o 0 -g 0 \
    "$EXT4_SRC/dev" \
    "$EXT4_SRC/dev/pts"
  install -d -m 1777 -o 0 -g 0 \
    "$EXT4_SRC/dev/shm" \
    "$EXT4_SRC/tmp"

  cat >"$EXT4_SRC/etc/fstab" <<'EOF'
/dev/vda  /      ext4      defaults,noatime                                                   0  0
proc      /proc  proc      defaults                                                           0  0
sysfs     /sys   sysfs     defaults                                                           0  0
devtmpfs  /dev   devtmpfs  mode=0755                                                          0  0
tmpfs     /run   tmpfs     nosuid,nodev,mode=0755,size=128M                                    0  0
tmpfs     /tmp   tmpfs     nosuid,nodev,size=512M                                              0  0
EOF

  if [[ -f "$PROJECT_ROOT/configs/rootfs-init-tmpfs-nosed.sh" ]]; then
    install -D -m 0644 "$PROJECT_ROOT/configs/rootfs-init-tmpfs-nosed.sh" \
      "$EXT4_SRC/usr/lib/init/tmpfs.sh"
  fi

  remove_generated_path "$tmp_image"
  truncate -s "$IMAGE_SIZE" "$tmp_image"
  mkfs.ext4 -q -F -L karudebvnc -d "$EXT4_SRC" "$tmp_image"
  mv -f "$tmp_image" "$ROOTFS_IMAGE"
}

build_ext4_image() {
  ensure_vnc_rootfs_archive

  if [[ -f "$ROOTFS_IMAGE" && "${FORCE_IMAGE:-0}" != "1" ]]; then
    if [[ "$ROOTFS_IMAGE" -nt "$ROOTFS_TAR" ]]; then
      info "Ext4 VNC image already exists: $ROOTFS_IMAGE"
      return 0
    fi
    info "Ext4 VNC image is older than the rootfs archive; rebuilding it"
  fi

  check_tools "fakeroot:fakeroot:preserve target ownership while creating ext4 image"
  remove_generated_path "$ROOTFS_IMAGE"

  info "Building ext4 VNC image: $ROOTFS_IMAGE"
  ROOTFS_TAR="$ROOTFS_TAR" \
    ROOTFS_IMAGE="$ROOTFS_IMAGE" \
    EXT4_SRC="$EXT4_SRC" \
    IMAGE_SIZE="$IMAGE_SIZE" \
    ALLOW_VNC_TEST_OUTSIDE_BUILD="${ALLOW_VNC_TEST_OUTSIDE_BUILD:-0}" \
    fakeroot -- "$SCRIPT_DIR/test-qemu-vnc.sh" _build-ext4-image
}

ensure_kernel() {
  if [[ -f "$KERNEL" ]]; then
    return 0
  fi

  if [[ "$BUILD_KERNEL_IF_MISSING" == "1" && "$KERNEL" == "$PROJECT_ROOT/build/linux-riscv64/arch/riscv/boot/Image" ]]; then
    info "Building missing Linux 7.1.2 QEMU kernel: $KERNEL"
    "$SCRIPT_DIR/build-qemu-linux.sh"
  fi

  [[ -f "$KERNEL" ]] || die "kernel image not found: $KERNEL"
}

start_qemu() {
  local append
  local netdev="user,id=net0"
  local pid
  local qemu_args
  local extra_args=()

  check_tools \
    "qemu-system-riscv64:qemu-system-misc:run RISC-V system QEMU" \
    "bash:bash:probe forwarded VNC socket" \
    "timeout:coreutils:bound VNC socket probes"

  ensure_kernel
  [[ -f "$ROOTFS_IMAGE" ]] || die "rootfs image not found: $ROOTFS_IMAGE"

  if pid="$(qemu_pid 2>/dev/null)"; then
    info "QEMU already running with pid $pid"
    return 0
  fi

  if port_listening "$VNC_HOST_PORT"; then
    die "host VNC port already in use: $VNC_HOST:$VNC_HOST_PORT"
  fi
  if [[ -n "$SSH_HOST_PORT" ]] && port_listening "$SSH_HOST_PORT"; then
    die "host SSH-forward port already in use: $VNC_HOST:$SSH_HOST_PORT"
  fi

  if [[ -n "$SSH_HOST_PORT" ]]; then
    netdev="$netdev,hostfwd=tcp:$VNC_HOST:$SSH_HOST_PORT-:22"
  fi
  netdev="$netdev,hostfwd=tcp:$VNC_HOST:$VNC_HOST_PORT-:5901"

  append="${APPEND:-console=ttyS0,115200 root=/dev/vda rw rootwait ip=dhcp earlycon=uart8250,mmio,0x10000000,115200 loglevel=7 $APPEND_EXTRA}"

  mkdir -p "$(dirname "$QEMU_PID_FILE")" "$(dirname "$QEMU_LOG_FILE")" "$(dirname "$QEMU_ERR_FILE")"
  rm -f "$QEMU_PID_FILE" "$QEMU_LOG_FILE" "$QEMU_ERR_FILE"

  qemu_args=(
    -machine "$QEMU_MACHINE"
    -cpu "$QEMU_CPU"
    -m "$MEMORY"
    -smp "$SMP"
    -display none
    -serial "file:$QEMU_LOG_FILE"
    -monitor none
    -bios "$QEMU_BIOS"
    -kernel "$KERNEL"
    -append "$append"
    -drive "file=$ROOTFS_IMAGE,if=none,format=raw,id=hd0"
    -device "virtio-blk-device,drive=hd0"
    -netdev "$netdev"
    -device "$QEMU_NET_DEVICE,netdev=net0"
    -daemonize
    -pidfile "$QEMU_PID_FILE"
  )

  if [[ -n "$QEMU_EXTRA_ARGS" ]]; then
    # Intentionally shell-split for command-line style overrides.
    # shellcheck disable=SC2206
    extra_args=($QEMU_EXTRA_ARGS)
    qemu_args+=("${extra_args[@]}")
  fi

  info "Starting QEMU with root image: $ROOTFS_IMAGE"
  if ! qemu-system-riscv64 "${qemu_args[@]}" 2>"$QEMU_ERR_FILE"; then
    die "QEMU failed to start; see $QEMU_ERR_FILE"
  fi

  pid="$(qemu_pid 2>/dev/null || true)"
  [[ -n "$pid" ]] || die "QEMU started but no matching pid was recorded in $QEMU_PID_FILE"
  info "QEMU pid: $pid"
  wait_for_vnc
}

stop_qemu() {
  local pid
  local end

  if ! pid="$(qemu_pid 2>/dev/null)"; then
    info "No matching QEMU process found for $QEMU_PID_FILE"
    rm -f "$QEMU_PID_FILE"
    return 0
  fi

  info "Stopping QEMU pid $pid"
  kill "$pid" 2>/dev/null || true
  end=$((SECONDS + 30))
  while (( SECONDS < end )); do
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$QEMU_PID_FILE"
      break
    fi
    sleep 1
  done

  if kill -0 "$pid" 2>/dev/null; then
    info "QEMU did not exit after SIGTERM; sending SIGKILL"
    kill -KILL "$pid" 2>/dev/null || true
    rm -f "$QEMU_PID_FILE"
  fi

  if [[ "$E2FSCK_ON_STOP" == "1" && -f "$ROOTFS_IMAGE" ]]; then
    if have_cmd e2fsck; then
      e2fsck -fy "$ROOTFS_IMAGE"
    else
      info "Skipping e2fsck: missing e2fsck (package: e2fsprogs)"
    fi
  fi
}

status_qemu() {
  local pid
  local banner

  if pid="$(qemu_pid 2>/dev/null)"; then
    info "QEMU running: pid $pid"
  else
    info "QEMU not running"
  fi

  if port_listening "$VNC_HOST_PORT"; then
    info "VNC forward listening: $VNC_HOST:$VNC_HOST_PORT"
  else
    info "VNC forward not listening: $VNC_HOST:$VNC_HOST_PORT"
  fi

  if [[ -n "$SSH_HOST_PORT" ]]; then
    if port_listening "$SSH_HOST_PORT"; then
      info "SSH forward listening: $VNC_HOST:$SSH_HOST_PORT"
    else
      info "SSH forward not listening: $VNC_HOST:$SSH_HOST_PORT"
    fi
  fi

  banner="$(probe_vnc_banner)"
  if [[ "$banner" == RFB* ]]; then
    info "VNC banner: $banner"
  else
    info "VNC banner: unavailable"
  fi
}

case "$COMMAND" in
  start)
    ensure_kernel
    build_ext4_image
    start_qemu
    info ""
    info "Connect your VNC viewer to $VNC_HOST:$VNC_HOST_PORT"
    info "Default guest VNC password: karu"
    info "Serial log: $QEMU_LOG_FILE"
    ;;
  image)
    FORCE_IMAGE="${FORCE_IMAGE:-1}" build_ext4_image
    ;;
  status)
    status_qemu
    ;;
  probe)
    probe_vnc_banner
    ;;
  stop)
    stop_qemu
    ;;
  _build-ext4-image)
    build_ext4_image_inside_fakeroot
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
