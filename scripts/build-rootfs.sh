#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ARCH="${ARCH:-riscv64}"
SUITE="${SUITE:-trixie}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
VARIANT="${VARIANT:-minbase}"
ROOTFS_DIR="${ROOTFS_DIR:-$PROJECT_ROOT/build/rootfs}"
KARUDEB_HOSTNAME="${KARUDEB_HOSTNAME:-karudeb}"
KARUDEB_LOCALE="${KARUDEB_LOCALE:-C.UTF-8}"
SERIAL_DEVICE="${SERIAL_DEVICE:-ttyS0}"
SERIAL_SPEED="${SERIAL_SPEED:-115200}"
SERIAL_TERM="${SERIAL_TERM:-vt100}"
SERIAL_AUTOLOGIN="${SERIAL_AUTOLOGIN:-1}"
ROOT_SSH_AUTHORIZED_KEYS="${ROOT_SSH_AUTHORIZED_KEYS:-}"
KARUDEB_SSH_AUTHORIZED_KEYS="${KARUDEB_SSH_AUTHORIZED_KEYS-$PROJECT_ROOT/configs/ssh/karudeb_lab_ed25519.pub}"
KARUDEB_SSH_HOST_ED25519_KEY="${KARUDEB_SSH_HOST_ED25519_KEY-$PROJECT_ROOT/configs/ssh/karudeb_host_ed25519_key}"
ROOT_PASSWORD_HASH_DEFAULT='$6$karudeb$wg24N/PgXN56c2ju.ly3V3N1msPKMvRj24qx2yED.LbervC5Z0a98CBh0l2V2BX4SfMXhUFzmUrVjV60sylnx0'
ROOT_PASSWORD_HASH="${ROOT_PASSWORD_HASH:-$ROOT_PASSWORD_HASH_DEFAULT}"
KARUDEB_USER="${KARUDEB_USER:-karu}"
KARUDEB_USER_UID="${KARUDEB_USER_UID:-1000}"
KARUDEB_USER_GID="${KARUDEB_USER_GID:-1000}"
KARUDEB_USER_PASSWORD_HASH_DEFAULT='$6$karu$WP5yVp50lS8TYvEKw8DU0SvciZFpLc1ZofGYqcAU5RLA1RjOalXURWIhWnUdmta/U29spcnO5bxirOUecnWwx/'
KARUDEB_USER_PASSWORD_HASH="${KARUDEB_USER_PASSWORD_HASH:-$KARUDEB_USER_PASSWORD_HASH_DEFAULT}"
KARUDEB_SHADOW_LAST_CHANGE="${KARUDEB_SHADOW_LAST_CHANGE:-}"
ROOTFS_BUILDER="${ROOTFS_BUILDER:-auto}"
MMDEBSTRAP_USE_SUDO="${MMDEBSTRAP_USE_SUDO:-0}"
KARUDEB_JWM_VNC="${KARUDEB_JWM_VNC:-0}"
KARUDEB_BUSYBOX_RESCUE="${KARUDEB_BUSYBOX_RESCUE:-1}"
KARUDEB_VNC_USER="${KARUDEB_VNC_USER:-karu}"
KARUDEB_VNC_UID="${KARUDEB_VNC_UID:-1000}"
KARUDEB_VNC_GID="${KARUDEB_VNC_GID:-1000}"
KARUDEB_VNC_DISPLAY="${KARUDEB_VNC_DISPLAY:-1}"
KARUDEB_VNC_GEOMETRY="${KARUDEB_VNC_GEOMETRY:-1280x800}"
KARUDEB_VNC_DEPTH="${KARUDEB_VNC_DEPTH:-16}"
KARUDEB_VNC_LOCALHOST="${KARUDEB_VNC_LOCALHOST:-no}"
KARUDEB_VNC_SECURITY_TYPES="${KARUDEB_VNC_SECURITY_TYPES:-VncAuth}"
KARUDEB_VNC_PASSWORD="${KARUDEB_VNC_PASSWORD:-karu}"
KARUDEB_VNC_EXTRA_ARGS="${KARUDEB_VNC_EXTRA_ARGS:--pixelformat rgb565 -FrameRate 10 -ImprovedHextile=0}"
KARUDEB_VNC_AUTOSTART="${KARUDEB_VNC_AUTOSTART:-0}"
KARUDEB_VNC_START_DELAY="${KARUDEB_VNC_START_DELAY:-20}"
KARUDEB_VNC_START_RETRIES="${KARUDEB_VNC_START_RETRIES:-3}"
KARUDEB_VNC_RETRY_DELAY="${KARUDEB_VNC_RETRY_DELAY:-10}"
KARUDEB_PERF_USER_ACCESS="${KARUDEB_PERF_USER_ACCESS:-2}"
KARUDEB_PERF_EVENT_PARANOID="${KARUDEB_PERF_EVENT_PARANOID:-0}"
KARUDEB_PERF_RUN="${KARUDEB_PERF_RUN:-1}"
KARUDEB_PERF_RUN_CC="${KARUDEB_PERF_RUN_CC:-}"
KARUDEB_TARGET_CC="${KARUDEB_TARGET_CC:-$KARUDEB_PERF_RUN_CC}"
KARUDEB_TARGET_SYSROOT="${KARUDEB_TARGET_SYSROOT:-}"
KARUDEB_TARGET_STATIC="${KARUDEB_TARGET_STATIC:-0}"
KARUDEB_OPENSSL_ZVK_BENCH="${KARUDEB_OPENSSL_ZVK_BENCH:-1}"
KARUDEB_OPENSSL_ZVK_KAT="${KARUDEB_OPENSSL_ZVK_KAT:-1}"
KARUDEB_ZVKNHK_OPENSSL="${KARUDEB_ZVKNHK_OPENSSL:-1}"
KARUDEB_ZVKNHK_DIR="${KARUDEB_ZVKNHK_DIR:-$PROJECT_ROOT/build/zvknhk}"

DEFAULT_PACKAGES="sysvinit-core,sysv-rc,ifupdown,iproute2,netbase,openssh-server,sudo,procps,psmisc,iputils-ping,ca-certificates,busybox-static"
VNC_PACKAGES="tigervnc-standalone-server,tigervnc-common,tigervnc-tools,jwm,xterm,xauth,x11-xserver-utils,fonts-dejavu-core"
PACKAGES="${PACKAGES:-$DEFAULT_PACKAGES}"
if [[ "$KARUDEB_JWM_VNC" == "1" ]]; then
  PACKAGES="$PACKAGES,$VNC_PACKAGES"
fi
if [[ -n "${EXTRA_PACKAGES:-}" ]]; then
  PACKAGES="$PACKAGES,$EXTRA_PACKAGES"
fi

ROOTFS_DIR="$(abs_path "$ROOTFS_DIR")"
ROOTFS_USE_SUDO=1

[[ "$KARUDEB_JWM_VNC" == "0" || "$KARUDEB_JWM_VNC" == "1" ]] || die "KARUDEB_JWM_VNC must be 0 or 1"

host_arch="$(dpkg --print-architecture 2>/dev/null || true)"
foreign_arch=0
if [[ -n "$host_arch" && "$host_arch" != "$ARCH" ]]; then
  foreign_arch=1
  if ! have_cmd "qemu-$ARCH-static" && ! have_cmd "qemu-$ARCH"; then
    die "building $ARCH on $host_arch needs qemu-$ARCH-static or qemu-$ARCH (install qemu-user or qemu-user-static)"
  fi
fi

write_rootfs_file() {
  local rel="$1"
  local mode="${2:-0644}"
  local tmp

  tmp="$(mktemp)"
  cat >"$tmp"
  rootfs_cmd install -D -m "$mode" "$tmp" "$ROOTFS_DIR/$rel"
  rm -f "$tmp"
}

rootfs_cmd() {
  if [[ "$ROOTFS_USE_SUDO" == "1" ]]; then
    as_root "$@"
  else
    "$@"
  fi
}

rootfs_chroot() {
  rootfs_cmd chroot "$ROOTFS_DIR" "$@"
}

rootfs_chown() {
  if rootfs_cmd chown "$@"; then
    return 0
  fi

  if [[ "$(id -u)" -ne 0 && "$ROOTFS_USE_SUDO" == "0" ]]; then
    info "Warning: could not set target ownership for $*; this is expected for direct user-owned configure-only trees"
    return 0
  fi

  return 1
}

install_authorized_keys() {
  local user="$1"
  local home="$2"
  local uid="$3"
  local gid="$4"
  local keys="$5"
  local ssh_dir

  [[ -n "$keys" ]] || return 0
  [[ -f "$keys" ]] || die "SSH authorized_keys source does not exist for $user: $keys"

  ssh_dir="$ROOTFS_DIR/${home#/}/.ssh"
  rootfs_cmd install -d -m 0700 "$ssh_dir"
  rootfs_cmd install -m 0600 "$keys" "$ssh_dir/authorized_keys"
  rootfs_chown -R "$uid:$gid" "$ssh_dir"
}

install_ssh_host_key() {
  local key="$KARUDEB_SSH_HOST_ED25519_KEY"
  local pub="${key}.pub"

  [[ -n "$key" ]] || return 0
  key="$(abs_path "$key")"
  pub="$(abs_path "$pub")"
  [[ -f "$key" ]] || die "SSH host key source does not exist: $key"
  [[ -f "$pub" ]] || die "SSH host public key source does not exist: $pub"

  rootfs_cmd install -d -m 0755 "$ROOTFS_DIR/etc/ssh"
  rootfs_cmd find "$ROOTFS_DIR/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*' -delete
  rootfs_cmd install -D -m 0600 "$key" "$ROOTFS_DIR/etc/ssh/ssh_host_ed25519_key"
  rootfs_cmd install -D -m 0644 "$pub" "$ROOTFS_DIR/etc/ssh/ssh_host_ed25519_key.pub"
}

refresh_rootfs_write_mode() {
  if [[ "$(id -u)" -eq 0 || -w "$ROOTFS_DIR/etc" ]]; then
    ROOTFS_USE_SUDO=0
  else
    ROOTFS_USE_SUDO=1
  fi
}

can_configure_with_unshare() {
  have_cmd unshare && \
    unshare --map-auto --setuid 0 --setgid 0 test -w "$ROOTFS_DIR/etc" >/dev/null 2>&1
}

configure_built_rootfs() {
  local staged_ssh_host_key=""
  local staged_ssh_host_pub=""
  local status=0

  refresh_rootfs_write_mode

  if [[ "$ROOTFS_USE_SUDO" == "1" && "$(id -u)" -ne 0 && "${KARUDEB_CONFIGURE_IN_USERNS:-0}" != "1" ]]; then
    if can_configure_with_unshare; then
      info "Configuring shifted rootfs inside a user namespace"
      if [[ -n "$KARUDEB_SSH_HOST_ED25519_KEY" ]]; then
        local host_key
        local host_pub

        host_key="$(abs_path "$KARUDEB_SSH_HOST_ED25519_KEY")"
        host_pub="$(abs_path "${KARUDEB_SSH_HOST_ED25519_KEY}.pub")"
        [[ -f "$host_key" ]] || die "SSH host key source does not exist: $host_key"
        [[ -f "$host_pub" ]] || die "SSH host public key source does not exist: $host_pub"

        staged_ssh_host_key="$(mktemp "${TMPDIR:-/tmp}/karudeb-hostkey.XXXXXX")"
        staged_ssh_host_pub="${staged_ssh_host_key}.pub"
        # The mapped root inside the user namespace is not the host user that
        # owns this temp file. The committed lab key is already world-readable;
        # keep the staged copy readable too, then install it in the rootfs as
        # 0600 in install_ssh_host_key().
        install -m 0644 "$host_key" "$staged_ssh_host_key"
        install -m 0644 "$host_pub" "$staged_ssh_host_pub"
        KARUDEB_SSH_HOST_ED25519_KEY="$staged_ssh_host_key"
      fi
      export ARCH SUITE ROOTFS_DIR KARUDEB_HOSTNAME KARUDEB_LOCALE SERIAL_DEVICE SERIAL_SPEED SERIAL_TERM
      export SERIAL_AUTOLOGIN ROOT_SSH_AUTHORIZED_KEYS KARUDEB_SSH_AUTHORIZED_KEYS KARUDEB_SSH_HOST_ED25519_KEY
      export ROOT_PASSWORD_HASH KARUDEB_USER KARUDEB_USER_UID KARUDEB_USER_GID KARUDEB_USER_PASSWORD_HASH
      export KARUDEB_SHADOW_LAST_CHANGE ROOTFS_CONFIGURE_ONLY=1
      export KARUDEB_BUSYBOX_RESCUE
      export KARUDEB_CONFIGURE_IN_USERNS=1
      export KARUDEB_JWM_VNC KARUDEB_VNC_USER KARUDEB_VNC_UID KARUDEB_VNC_GID
      export KARUDEB_VNC_DISPLAY KARUDEB_VNC_GEOMETRY KARUDEB_VNC_DEPTH
      export KARUDEB_VNC_LOCALHOST KARUDEB_VNC_SECURITY_TYPES KARUDEB_VNC_PASSWORD KARUDEB_VNC_EXTRA_ARGS
      export KARUDEB_VNC_AUTOSTART KARUDEB_VNC_START_DELAY KARUDEB_VNC_START_RETRIES KARUDEB_VNC_RETRY_DELAY
      export KARUDEB_PERF_USER_ACCESS KARUDEB_PERF_EVENT_PARANOID
      export KARUDEB_PERF_RUN KARUDEB_PERF_RUN_CC KARUDEB_TARGET_CC KARUDEB_TARGET_SYSROOT KARUDEB_TARGET_STATIC
      export KARUDEB_OPENSSL_ZVK_BENCH KARUDEB_OPENSSL_ZVK_KAT
      export KARUDEB_ZVKNHK_OPENSSL KARUDEB_ZVKNHK_DIR
      unshare --map-auto --setuid 0 --setgid 0 "$SCRIPT_DIR/build-rootfs.sh" || status=$?
      rm -f "$staged_ssh_host_key" "$staged_ssh_host_pub"
      return "$status"
    fi
  fi

  configure_rootfs
}

replace_root_shadow() {
  local tmp

  tmp="$(mktemp)"
  awk -F: -v OFS=: -v hash="$ROOT_PASSWORD_HASH" \
    -v last_change="$KARUDEB_SHADOW_LAST_CHANGE" \
    '$1 == "root" {$2 = hash; $3 = last_change} {print}' \
    "$ROOTFS_DIR/etc/shadow" >"$tmp"
  if [[ "$(id -u)" -eq 0 ]]; then
    install -m 0640 -o 0 -g 42 "$tmp" "$ROOTFS_DIR/etc/shadow"
  elif [[ "$ROOTFS_USE_SUDO" == "1" ]]; then
    as_root install -m 0640 -o 0 -g 42 "$tmp" "$ROOTFS_DIR/etc/shadow"
  else
    install -m 0640 "$tmp" "$ROOTFS_DIR/etc/shadow"
  fi
  rm -f "$tmp"
}

configure_inittab() {
  local tmp
  local getty_line

  if [[ "$SERIAL_AUTOLOGIN" == "1" ]]; then
    getty_line="T0:23:respawn:/sbin/getty -L --autologin root $SERIAL_DEVICE $SERIAL_SPEED $SERIAL_TERM"
  else
    getty_line="T0:23:respawn:/sbin/getty -L $SERIAL_DEVICE $SERIAL_SPEED $SERIAL_TERM"
  fi

  tmp="$(mktemp)"
  if [[ -f "$ROOTFS_DIR/etc/inittab" ]]; then
    sed '/^T0:/d;/^VN:/d' "$ROOTFS_DIR/etc/inittab" >"$tmp"
  else
    : >"$tmp"
  fi
  {
    printf '\n# Serial console for diskless bring-up.\n'
    printf '%s\n' "$getty_line"
  } >>"$tmp"
  rootfs_cmd install -D -m 0644 "$tmp" "$ROOTFS_DIR/etc/inittab"
  rm -f "$tmp"
}

configure_busybox_rescue_init() {
  [[ "$KARUDEB_BUSYBOX_RESCUE" == "1" ]] || return 0

  write_rootfs_file usr/local/sbin/karudeb-busybox-init 0755 <<'EOF'
#!/bin/sh
# Minimal PID 1 rescue shell for serial bring-up.
# Boot with: init=/usr/local/sbin/karudeb-busybox-init

PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

bb=/bin/busybox
[ -x "$bb" ] || bb=/usr/bin/busybox

if [ -x "$bb" ]; then
	mount_cmd="$bb mount"
	mkdir_cmd="$bb mkdir"
	mknod_cmd="$bb mknod"
	grep_cmd="$bb grep"
else
	mount_cmd=mount
	mkdir_cmd=mkdir
	mknod_cmd=mknod
	grep_cmd=grep
fi

$mkdir_cmd -p /proc /sys /dev /dev/pts /run /tmp
$mount_cmd -t proc proc /proc 2>/dev/null || true
$mount_cmd -t sysfs sysfs /sys 2>/dev/null || true
$mount_cmd -t devtmpfs -o mode=0755 devtmpfs /dev 2>/dev/null || true
$mount_cmd -t devpts devpts /dev/pts 2>/dev/null || true
$mount_cmd -t tmpfs -o mode=0755 tmpfs /run 2>/dev/null || true
$mount_cmd -t tmpfs -o mode=1777 tmpfs /tmp 2>/dev/null || true

[ -c /dev/console ] || $mknod_cmd -m 600 /dev/console c 5 1 2>/dev/null || true
[ -c /dev/null ] || $mknod_cmd -m 666 /dev/null c 1 3 2>/dev/null || true

exec </dev/console >/dev/console 2>&1

echo
echo "karudeb BusyBox rescue shell"
echo "sysvinit was bypassed; /proc, /sys, /dev, /run, and /tmp were mounted best-effort."
echo

if [ -x "$bb" ]; then
	if "$bb" --list 2>/dev/null | $grep_cmd -qx cttyhack &&
	   "$bb" --list 2>/dev/null | $grep_cmd -qx setsid; then
		exec "$bb" setsid "$bb" cttyhack "$bb" sh
	fi
	exec "$bb" sh
fi

echo "busybox is not installed; falling back to /bin/sh"
exec /bin/sh
EOF
}

ensure_securetty() {
  local tmp

  tmp="$(mktemp)"
  if [[ -f "$ROOTFS_DIR/etc/securetty" ]]; then
    cat "$ROOTFS_DIR/etc/securetty" >"$tmp"
  fi
  if ! grep -qx "$SERIAL_DEVICE" "$tmp"; then
    printf '%s\n' "$SERIAL_DEVICE" >>"$tmp"
  fi
  rootfs_cmd install -D -m 0644 "$tmp" "$ROOTFS_DIR/etc/securetty"
  rm -f "$tmp"
}

configure_rcs() {
  local tmp

  tmp="$(mktemp)"
  if [[ -f "$ROOTFS_DIR/etc/default/rcS" ]]; then
    sed -E '/^[[:space:]]*#?[[:space:]]*FSCKTYPES=/d' "$ROOTFS_DIR/etc/default/rcS" >"$tmp"
  fi
  {
    printf '\n# Diskless roots are checked by the server-side backing store.\n'
    printf 'FSCKTYPES=none\n'
  } >>"$tmp"
  rootfs_cmd install -D -m 0644 "$tmp" "$ROOTFS_DIR/etc/default/rcS"
  rm -f "$tmp"
}

configure_openssh() {
  local host_key_config=""

  rootfs_cmd install -d -m 0755 "$ROOTFS_DIR/etc/ssh/sshd_config.d"
  if [[ -n "$KARUDEB_SSH_HOST_ED25519_KEY" ]]; then
    install_ssh_host_key
    host_key_config="HostKey /etc/ssh/ssh_host_ed25519_key"
  fi

  write_rootfs_file etc/ssh/sshd_config.d/karudeb.conf <<EOF
# karudeb lab images use OpenSSH for normal ssh/scp/sftp access.
# Password login stays disabled; install authorized_keys for root/karu instead.
$host_key_config
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
UseDNS no
SetEnv LANG=$KARUDEB_LOCALE
EOF

  rootfs_cmd rm -f "$ROOTFS_DIR/etc/rc2.d/S99dropbear" \
                   "$ROOTFS_DIR/etc/rc3.d/S99dropbear" \
                   "$ROOTFS_DIR/etc/rc4.d/S99dropbear" \
                   "$ROOTFS_DIR/etc/rc5.d/S99dropbear" \
                   "$ROOTFS_DIR/etc/rc0.d/K01dropbear" \
                   "$ROOTFS_DIR/etc/rc1.d/K01dropbear" \
                   "$ROOTFS_DIR/etc/rc6.d/K01dropbear" \
                   "$ROOTFS_DIR/etc/rc2.d/S99ssh" \
                   "$ROOTFS_DIR/etc/rc3.d/S99ssh" \
                   "$ROOTFS_DIR/etc/rc4.d/S99ssh" \
                   "$ROOTFS_DIR/etc/rc5.d/S99ssh"

  for rc in 2 3 4 5; do
    rootfs_cmd install -d -m 0755 "$ROOTFS_DIR/etc/rc${rc}.d"
    rootfs_cmd ln -sf "../init.d/ssh" "$ROOTFS_DIR/etc/rc${rc}.d/S01ssh"
  done

  for rc in 0 1 6; do
    rootfs_cmd install -d -m 0755 "$ROOTFS_DIR/etc/rc${rc}.d"
    rootfs_cmd ln -sf "../init.d/ssh" "$ROOTFS_DIR/etc/rc${rc}.d/K01ssh"
  done
}

configure_init_tmpfs_helpers() {
  local rel src

  src="$PROJECT_ROOT/configs/rootfs-init-tmpfs-nosed.sh"
  [[ -f "$src" ]] || die "missing tmpfs helper override: $src"

  for rel in usr/lib/init/tmpfs.sh lib/init/tmpfs.sh; do
    [[ -e "$ROOTFS_DIR/$rel" || "$rel" == "usr/lib/init/tmpfs.sh" ]] || continue
    rootfs_cmd install -D -m 0644 "$src" "$ROOTFS_DIR/$rel"
  done
}

configure_benchmark_counters() {
  write_rootfs_file etc/default/karudeb-benchmark <<EOF
# RISC-V Linux value 2 is legacy direct userspace access to cycle/time/instret.
PERF_USER_ACCESS="$KARUDEB_PERF_USER_ACCESS"
# Linux perf_event_paranoid value 0 permits unprivileged per-process hardware
# perf_event_open(), which perf_run uses for raw-counter keepalive and
# whole-process user-filtered measurements.
PERF_EVENT_PARANOID="$KARUDEB_PERF_EVENT_PARANOID"
EOF

  write_rootfs_file etc/init.d/karudeb-benchmark-counters 0755 <<'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          karudeb-benchmark-counters
# Required-Start:    $local_fs
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:
# Short-Description: Enable direct RISC-V benchmark counters for userspace
### END INIT INFO

set -e

DEFAULT=/etc/default/karudeb-benchmark
[ -r "$DEFAULT" ] && . "$DEFAULT"

: "${PERF_USER_ACCESS:=2}"
: "${PERF_EVENT_PARANOID:=0}"

case "$1" in
  start|restart|force-reload)
    if [ -w /proc/sys/kernel/perf_user_access ]; then
      printf '%s\n' "$PERF_USER_ACCESS" >/proc/sys/kernel/perf_user_access || true
      echo "karudeb-benchmark-counters: kernel.perf_user_access=$(cat /proc/sys/kernel/perf_user_access)"
    else
      echo "karudeb-benchmark-counters: kernel.perf_user_access unavailable" >&2
    fi
    if [ -w /proc/sys/kernel/perf_event_paranoid ]; then
      printf '%s\n' "$PERF_EVENT_PARANOID" >/proc/sys/kernel/perf_event_paranoid || true
      echo "karudeb-benchmark-counters: kernel.perf_event_paranoid=$(cat /proc/sys/kernel/perf_event_paranoid)"
    else
      echo "karudeb-benchmark-counters: kernel.perf_event_paranoid unavailable" >&2
    fi
    ;;
  stop)
    ;;
  status)
    if [ -r /proc/sys/kernel/perf_user_access ]; then
      echo "kernel.perf_user_access=$(cat /proc/sys/kernel/perf_user_access)"
    else
      echo "kernel.perf_user_access unavailable"
      exit 3
    fi
    if [ -r /proc/sys/kernel/perf_event_paranoid ]; then
      echo "kernel.perf_event_paranoid=$(cat /proc/sys/kernel/perf_event_paranoid)"
    else
      echo "kernel.perf_event_paranoid unavailable"
      exit 3
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|force-reload|status}" >&2
    exit 2
    ;;
esac

exit 0
EOF

  enable_sysv_service karudeb-benchmark-counters
}

select_target_cc() {
  if [[ -n "$KARUDEB_TARGET_CC" ]]; then
    printf '%s\n' "$KARUDEB_TARGET_CC"
  elif have_cmd riscv64-unknown-linux-gnu-clang; then
    printf '%s\n' riscv64-unknown-linux-gnu-clang
  elif have_cmd riscv64-linux-gnu-clang; then
    printf '%s\n' riscv64-linux-gnu-clang
  elif have_cmd clang; then
    printf '%s\n' clang
  elif have_cmd riscv64-linux-gnu-gcc; then
    printf '%s\n' riscv64-linux-gnu-gcc
  else
    return 1
  fi
}

target_sysroot() {
  if [[ -n "$KARUDEB_TARGET_SYSROOT" ]]; then
    abs_path "$KARUDEB_TARGET_SYSROOT"
  elif [[ -f "$ROOTFS_DIR/usr/lib/riscv64-linux-gnu/crt1.o" || -f "$ROOTFS_DIR/usr/lib/crt1.o" ]]; then
    printf '%s\n' "$ROOTFS_DIR"
  fi
}

target_cc_args() {
  local -n out="$1"
  local cc="$2"
  local base
  local sysroot

  out=("$cc")
  base="$(basename "$cc")"
  case "$base" in
    clang|clang-*|riscv64-*-clang)
      out+=(--target=riscv64-linux-gnu)
      if have_cmd ld.lld; then
        out+=(-fuse-ld=lld)
      fi
      ;;
  esac

  sysroot="$(target_sysroot)"
  if [[ -n "$sysroot" ]]; then
    out+=("--sysroot=$sysroot")
  fi
}

target_compile() {
  local cc="$1"
  shift

  local -a cc_args
  target_cc_args cc_args "$cc"
  "${cc_args[@]}" "$@"
}

configure_perf_run() {
  local cc out src
  local -a static_args

  [[ "$KARUDEB_PERF_RUN" == "1" ]] || return 0
  if [[ "$ARCH" != "riscv64" ]]; then
    info "Skipping perf_run: only riscv64 rootfs is supported"
    return 0
  fi

  src="$PROJECT_ROOT/tools/perf_run.c"
  [[ -f "$src" ]] || die "missing perf_run source: $src"
  cc="$(select_target_cc)" || \
    die "missing riscv64 Linux target compiler for perf_run; install clang/lld or set KARUDEB_PERF_RUN=0"

  out="$(mktemp)"
  static_args=()
  if [[ "$KARUDEB_TARGET_STATIC" == "1" ]]; then
    static_args=(-static)
  fi
  if ! target_compile "$cc" -Wall -Wextra -O2 "${static_args[@]}" -march=rv64gc_zicsr -mabi=lp64d "$src" -o "$out"; then
    target_compile "$cc" -Wall -Wextra -O2 "${static_args[@]}" -march=rv64gc -mabi=lp64d "$src" -o "$out"
  fi
  rootfs_cmd install -D -m 0755 "$out" "$ROOTFS_DIR/usr/local/bin/perf_run"
  rm -f "$out"
}

configure_openssl_zvk_bench() {
  local src

  [[ "$KARUDEB_OPENSSL_ZVK_BENCH" == "1" ]] || return 0
  if [[ "$ARCH" != "riscv64" ]]; then
    info "Skipping openssl_zvk_bench: only riscv64 rootfs is supported"
    return 0
  fi

  src="$PROJECT_ROOT/tools/openssl_zvk_bench.sh"
  [[ -f "$src" ]] || die "missing OpenSSL Zvk benchmark script: $src"
  rootfs_cmd install -D -m 0755 "$src" "$ROOTFS_DIR/usr/local/bin/openssl_zvk_bench"
}

configure_openssl_zvk_kat() {
  local cc out src sysroot
  local -a include_args

  [[ "$KARUDEB_OPENSSL_ZVK_KAT" == "1" ]] || return 0
  [[ "$KARUDEB_OPENSSL_ZVK_BENCH" == "1" ]] || return 0
  if [[ "$ARCH" != "riscv64" ]]; then
    info "Skipping openssl_zvk_kat: only riscv64 rootfs is supported"
    return 0
  fi

  src="$PROJECT_ROOT/tools/openssl_zvk_kat.c"
  [[ -f "$src" ]] || die "missing OpenSSL Zvk KAT helper source: $src"
  cc="$(select_target_cc)" || \
    die "missing riscv64 Linux target compiler for openssl_zvk_kat; install clang/lld or set KARUDEB_OPENSSL_ZVK_KAT=0"
  [[ -f "$ROOTFS_DIR/usr/lib/riscv64-linux-gnu/libcrypto.so.3" ]] || \
    die "missing target libcrypto for openssl_zvk_kat: $ROOTFS_DIR/usr/lib/riscv64-linux-gnu/libcrypto.so.3"
  [[ -d "$ROOTFS_DIR/usr/include/openssl" ]] || \
    die "missing target OpenSSL headers for openssl_zvk_kat: add libssl-dev to the rootfs packages or set KARUDEB_OPENSSL_ZVK_KAT=0"

  include_args=()
  sysroot="$(target_sysroot)"
  if [[ -n "$sysroot" && -d "$sysroot/usr/include/riscv64-linux-gnu" ]]; then
    include_args+=("-I$sysroot/usr/include/riscv64-linux-gnu")
  fi

  out="$(mktemp)"
  target_compile "$cc" -Wall -Wextra -Wno-deprecated-declarations -O2 "${include_args[@]}" \
    "$src" -L"$ROOTFS_DIR/usr/lib/riscv64-linux-gnu" -lcrypto -Wl,--allow-shlib-undefined \
    -Wl,-rpath-link,"$ROOTFS_DIR/usr/lib/riscv64-linux-gnu" \
    -o "$out"
  rootfs_cmd install -D -m 0755 "$out" "$ROOTFS_DIR/usr/local/bin/openssl_zvk_kat"
  rm -f "$out"
}

# The Zvknhk (vkeccak.vi) OpenSSL benchmark binaries are cross-built from the
# ../riscv-pqc reference tree by scripts/build-zvknhk-openssl.sh and staged
# under build/zvknhk. They are static, so the rootfs needs no development
# packages for them. The patched openssl lives under its own prefix and does
# not replace the Debian openssl used by openssl_zvk_bench.
configure_zvknhk_openssl() {
  local src

  [[ "$KARUDEB_ZVKNHK_OPENSSL" == "1" ]] || return 0
  if [[ "$ARCH" != "riscv64" ]]; then
    info "Skipping Zvknhk OpenSSL: only riscv64 rootfs is supported"
    return 0
  fi

  [[ -x "$KARUDEB_ZVKNHK_DIR/bin/openssl" && -x "$KARUDEB_ZVKNHK_DIR/bin/pqcbench" ]] || \
    die "missing Zvknhk OpenSSL binaries under $KARUDEB_ZVKNHK_DIR/bin; run 'make zvknhk-openssl' (needs ../riscv-pqc) or set KARUDEB_ZVKNHK_OPENSSL=0"
  src="$PROJECT_ROOT/tools/zvknhk_bench.sh"
  [[ -f "$src" ]] || die "missing Zvknhk benchmark script: $src"

  rootfs_cmd install -D -m 0755 "$KARUDEB_ZVKNHK_DIR/bin/openssl" \
    "$ROOTFS_DIR/usr/local/openssl-zvknhk/bin/openssl"
  rootfs_cmd install -D -m 0755 "$KARUDEB_ZVKNHK_DIR/bin/pqcbench" "$ROOTFS_DIR/usr/local/bin/pqcbench"
  rootfs_cmd install -D -m 0755 "$src" "$ROOTFS_DIR/usr/local/bin/zvknhk_bench"
  rootfs_cmd ln -sf ../openssl-zvknhk/bin/openssl "$ROOTFS_DIR/usr/local/bin/openssl-zvknhk"
  if [[ -f "$KARUDEB_ZVKNHK_DIR/VERSION" ]]; then
    rootfs_cmd install -D -m 0644 "$KARUDEB_ZVKNHK_DIR/VERSION" \
      "$ROOTFS_DIR/usr/local/openssl-zvknhk/VERSION"
  fi
}

ensure_local_user() {
  local user="$1"
  local uid="$2"
  local gid="$3"
  local gecos="$4"
  local home="$5"
  local shell="$6"
  local tmp

  if ! awk -F: -v user="$user" '$1 == user {found = 1} END {exit found ? 0 : 1}' "$ROOTFS_DIR/etc/group"; then
    tmp="$(mktemp)"
    cat "$ROOTFS_DIR/etc/group" >"$tmp"
    printf '%s:x:%s:\n' "$user" "$gid" >>"$tmp"
    rootfs_cmd install -D -m 0644 "$tmp" "$ROOTFS_DIR/etc/group"
    rm -f "$tmp"
  fi

  if ! awk -F: -v user="$user" '$1 == user {found = 1} END {exit found ? 0 : 1}' "$ROOTFS_DIR/etc/passwd"; then
    tmp="$(mktemp)"
    cat "$ROOTFS_DIR/etc/passwd" >"$tmp"
    printf '%s:x:%s:%s:%s:%s:%s\n' "$user" "$uid" "$gid" "$gecos" "$home" "$shell" >>"$tmp"
    rootfs_cmd install -D -m 0644 "$tmp" "$ROOTFS_DIR/etc/passwd"
    rm -f "$tmp"
  fi

  if ! awk -F: -v user="$user" '$1 == user {found = 1} END {exit found ? 0 : 1}' "$ROOTFS_DIR/etc/shadow"; then
    tmp="$(mktemp)"
    cat "$ROOTFS_DIR/etc/shadow" >"$tmp"
    printf '%s:*::0:99999:7:::\n' "$user" >>"$tmp"
    rootfs_cmd install -D -m 0640 "$tmp" "$ROOTFS_DIR/etc/shadow"
    rm -f "$tmp"
  fi
  # Boards without RTC boot with an epoch-ish clock. Disable password aging for
  # local lab accounts to avoid "changed in the future" and forced-change flows.
  tmp="$(mktemp)"
  awk -F: -v OFS=: -v user="$user" -v last_change="$KARUDEB_SHADOW_LAST_CHANGE" \
    '$1 == user {$3 = last_change} {print}' \
    "$ROOTFS_DIR/etc/shadow" >"$tmp"
  rootfs_cmd install -D -m 0640 "$tmp" "$ROOTFS_DIR/etc/shadow"
  rm -f "$tmp"

  if [[ -f "$ROOTFS_DIR/etc/gshadow" ]] && \
    ! awk -F: -v user="$user" '$1 == user {found = 1} END {exit found ? 0 : 1}' "$ROOTFS_DIR/etc/gshadow"; then
    tmp="$(mktemp)"
    cat "$ROOTFS_DIR/etc/gshadow" >"$tmp"
    printf '%s:!::\n' "$user" >>"$tmp"
    rootfs_cmd install -D -m 0640 "$tmp" "$ROOTFS_DIR/etc/gshadow"
    rm -f "$tmp"
  fi

  rootfs_cmd install -d -m 0755 "$ROOTFS_DIR/$home"
  rootfs_chown "$uid:$gid" "$ROOTFS_DIR/$home"
}

set_local_user_password() {
  local user="$1"
  local hash="$2"
  local tmp

  tmp="$(mktemp)"
  awk -F: -v OFS=: -v user="$user" -v hash="$hash" \
    -v last_change="$KARUDEB_SHADOW_LAST_CHANGE" \
    '$1 == user {$2 = hash; $3 = last_change} {print}' \
    "$ROOTFS_DIR/etc/shadow" >"$tmp"
  rootfs_cmd install -D -m 0640 "$tmp" "$ROOTFS_DIR/etc/shadow"
  rm -f "$tmp"
}

configure_karudeb_user() {
  local keys="$1"

  ensure_local_user "$KARUDEB_USER" "$KARUDEB_USER_UID" "$KARUDEB_USER_GID" \
    "Karu User" "/home/$KARUDEB_USER" "/bin/bash"
  set_local_user_password "$KARUDEB_USER" "$KARUDEB_USER_PASSWORD_HASH"
  install_authorized_keys "$KARUDEB_USER" "/home/$KARUDEB_USER" \
    "$KARUDEB_USER_UID" "$KARUDEB_USER_GID" "$keys"

  write_rootfs_file "etc/sudoers.d/karudeb-$KARUDEB_USER" 0440 <<EOF
$KARUDEB_USER ALL=(ALL:ALL) ALL
EOF
}

enable_sysv_service() {
  local service="$1"
  local rc

  for rc in 0 1 2 3 4 5 6; do
    rootfs_cmd install -d -m 0755 "$ROOTFS_DIR/etc/rc${rc}.d"
    rootfs_cmd rm -f "$ROOTFS_DIR/etc/rc${rc}.d/"[SK][0-9][0-9]"$service"
  done

  if [[ -x "$ROOTFS_DIR/usr/sbin/update-rc.d" ]] && \
     rootfs_chroot /usr/sbin/update-rc.d "$service" defaults >/dev/null; then
    return
  fi

  for rc in 2 3 4 5; do
    rootfs_cmd ln -sf "../init.d/$service" "$ROOTFS_DIR/etc/rc${rc}.d/S99$service"
  done

  for rc in 0 1 6; do
    rootfs_cmd ln -sf "../init.d/$service" "$ROOTFS_DIR/etc/rc${rc}.d/K01$service"
  done
}

disable_sysv_service() {
  local service="$1"
  local rc

  for rc in 0 1 2 3 4 5 6; do
    rootfs_cmd install -d -m 0755 "$ROOTFS_DIR/etc/rc${rc}.d"
    rootfs_cmd rm -f "$ROOTFS_DIR/etc/rc${rc}.d/"[SK][0-9][0-9]"$service"
  done
}

configure_jwm_vnc() {
  local home="/home/$KARUDEB_VNC_USER"
  local home_rel="${home#/}"

  ensure_local_user "$KARUDEB_VNC_USER" "$KARUDEB_VNC_UID" "$KARUDEB_VNC_GID" \
    "Karudeb VNC" "$home" "/bin/bash"

  rootfs_cmd rm -rf "$ROOTFS_DIR/$home_rel/.vnc"
  rootfs_cmd install -d -m 0700 "$ROOTFS_DIR/$home_rel/.config"
  rootfs_cmd install -d -m 0700 "$ROOTFS_DIR/$home_rel/.config/tigervnc"
  rootfs_chown "$KARUDEB_VNC_UID:$KARUDEB_VNC_GID" "$ROOTFS_DIR/$home_rel/.config"
  rootfs_chown "$KARUDEB_VNC_UID:$KARUDEB_VNC_GID" "$ROOTFS_DIR/$home_rel/.config/tigervnc"

  write_rootfs_file "$home_rel/.config/tigervnc/xstartup" 0755 <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
[ -r "$HOME/.Xresources" ] && xrdb "$HOME/.Xresources"
command -v xsetroot >/dev/null 2>&1 && xsetroot -solid '#202020'
jwm >/tmp/jwm.log 2>&1 &
exec xterm -fa Monospace -fs 10 -geometry 100x32 -title karudeb
EOF
  rootfs_chown "$KARUDEB_VNC_UID:$KARUDEB_VNC_GID" "$ROOTFS_DIR/$home_rel/.config/tigervnc/xstartup"

  write_rootfs_file etc/default/karudeb-vnc <<EOF
ENABLE=1
VNC_USER="$KARUDEB_VNC_USER"
VNC_DISPLAY="$KARUDEB_VNC_DISPLAY"
VNC_GEOMETRY="$KARUDEB_VNC_GEOMETRY"
VNC_DEPTH="$KARUDEB_VNC_DEPTH"
VNC_LOCALHOST="$KARUDEB_VNC_LOCALHOST"
VNC_SECURITY_TYPES="$KARUDEB_VNC_SECURITY_TYPES"
VNC_PASSWORD="$KARUDEB_VNC_PASSWORD"
VNC_EXTRA_ARGS="$KARUDEB_VNC_EXTRA_ARGS"
VNC_START_DELAY="$KARUDEB_VNC_START_DELAY"
VNC_START_RETRIES="$KARUDEB_VNC_START_RETRIES"
VNC_RETRY_DELAY="$KARUDEB_VNC_RETRY_DELAY"
EOF

  write_rootfs_file etc/init.d/karudeb-vnc 0755 <<'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          karudeb-vnc
# Required-Start:    $remote_fs $syslog $network
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start the karudeb TigerVNC JWM session
### END INIT INFO

set -e

DEFAULT=/etc/default/karudeb-vnc
[ -r "$DEFAULT" ] && . "$DEFAULT"

: "${ENABLE:=1}"
: "${VNC_USER:=karu}"
: "${VNC_DISPLAY:=1}"
: "${VNC_GEOMETRY:=1280x800}"
: "${VNC_DEPTH:=16}"
: "${VNC_LOCALHOST:=no}"
: "${VNC_SECURITY_TYPES:=VncAuth}"
: "${VNC_PASSWORD:=karu}"
: "${VNC_EXTRA_ARGS:=-pixelformat rgb565 -FrameRate 10 -ImprovedHextile=0}"
: "${VNC_START_DELAY:=20}"
: "${VNC_START_RETRIES:=3}"
: "${VNC_RETRY_DELAY:=10}"

case "$ENABLE" in
  1|yes|true|YES|TRUE) ;;
  *) exit 0 ;;
esac

display_num="${VNC_DISPLAY#:}"
display_arg=":$display_num"

case "$VNC_START_DELAY" in ''|*[!0-9]*) VNC_START_DELAY=0 ;; esac
case "$VNC_START_RETRIES" in ''|*[!0-9]*) VNC_START_RETRIES=1 ;; esac
case "$VNC_RETRY_DELAY" in ''|*[!0-9]*) VNC_RETRY_DELAY=0 ;; esac
[ "$VNC_START_RETRIES" -gt 0 ] || VNC_START_RETRIES=1

home_dir="$(awk -F: -v user="$VNC_USER" '$1 == user {print $6}' /etc/passwd)"
[ -n "$home_dir" ] || {
  echo "karudeb-vnc: user not found: $VNC_USER" >&2
  exit 1
}

ensure_runtime() {
  config_dir="$home_dir/.config/tigervnc"

  install -d -m 1777 /tmp/.X11-unix
  install -d -m 0700 -o "$VNC_USER" -g "$VNC_USER" "$home_dir/.config" "$config_dir"

  if [ ! -s "$config_dir/xstartup" ]; then
    cat >"$config_dir/xstartup" <<'XSTARTUP'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
[ -r "$HOME/.Xresources" ] && xrdb "$HOME/.Xresources"
command -v xsetroot >/dev/null 2>&1 && xsetroot -solid '#202020'
jwm >/tmp/jwm.log 2>&1 &
exec xterm -fa Monospace -fs 10 -geometry 100x32 -title karudeb
XSTARTUP
    chown "$VNC_USER:$VNC_USER" "$config_dir/xstartup"
    chmod 0755 "$config_dir/xstartup"
  fi

  if [ -n "$VNC_SECURITY_TYPES" ] && [ "$VNC_SECURITY_TYPES" != "None" ] && [ -n "$VNC_PASSWORD" ]; then
    if [ ! -s "$config_dir/passwd" ]; then
      if command -v tigervncpasswd >/dev/null 2>&1; then
        umask 077
        printf '%s\n' "$VNC_PASSWORD" | tigervncpasswd -f >"$config_dir/passwd"
        chown "$VNC_USER:$VNC_USER" "$config_dir/passwd"
        chmod 0600 "$config_dir/passwd"
      else
        echo "karudeb-vnc: tigervncpasswd is required for VNC authentication" >&2
        exit 1
      fi
    fi
  fi

  if command -v dbus-uuidgen >/dev/null 2>&1; then
    if [ ! -s /etc/machine-id ]; then
      rm -f /etc/machine-id
      dbus-uuidgen --ensure=/etc/machine-id || true
    fi
    install -d -m 0755 /var/lib/dbus
    if [ ! -s /var/lib/dbus/machine-id ]; then
      rm -f /var/lib/dbus/machine-id
      dbus-uuidgen --ensure=/var/lib/dbus/machine-id || true
    fi
  fi
}

vnc_start() {
  ensure_runtime
  cmd="vncserver $display_arg -geometry $VNC_GEOMETRY -depth $VNC_DEPTH -localhost $VNC_LOCALHOST -xstartup $home_dir/.config/tigervnc/xstartup"
  if [ -n "$VNC_SECURITY_TYPES" ]; then
    cmd="$cmd -SecurityTypes $VNC_SECURITY_TYPES"
  fi
  if [ -n "$VNC_EXTRA_ARGS" ]; then
    cmd="$cmd $VNC_EXTRA_ARGS"
  fi
  su - "$VNC_USER" -c "$cmd"
}

vnc_stop() {
  su - "$VNC_USER" -c "vncserver -kill $display_arg" >/dev/null 2>&1 || true
}

vnc_status() {
  su - "$VNC_USER" -c "vncserver -list" 2>/dev/null |
    awk -v display="$display_num" '$1 == display {found = 1} END {exit found ? 0 : 1}'
}

vnc_start_with_retry() {
  start_delay="${1:-$VNC_START_DELAY}"
  attempt=1

  case "$start_delay" in ''|*[!0-9]*) start_delay=0 ;; esac
  if [ "$start_delay" -gt 0 ]; then
    echo "karudeb-vnc: delaying start ${start_delay}s"
    sleep "$start_delay"
  fi

  while [ "$attempt" -le "$VNC_START_RETRIES" ]; do
    echo "Starting karudeb VNC display $display_arg (attempt $attempt/$VNC_START_RETRIES)"
    if vnc_start; then
      sleep 5
      if vnc_status; then
        echo "karudeb-vnc: display $display_arg is running"
        return 0
      fi
      echo "karudeb-vnc: vncserver returned but display $display_arg is not listed" >&2
    else
      rc=$?
      echo "karudeb-vnc: start attempt $attempt failed with status $rc" >&2
    fi

    vnc_stop
    attempt=$((attempt + 1))
    if [ "$attempt" -le "$VNC_START_RETRIES" ] && [ "$VNC_RETRY_DELAY" -gt 0 ]; then
      sleep "$VNC_RETRY_DELAY"
    fi
  done

  return 1
}

case "$1" in
  start)
    if vnc_status; then
      echo "karudeb-vnc: display $display_arg already running"
      exit 0
    fi
    vnc_start_with_retry "$VNC_START_DELAY"
    ;;
  stop)
    echo "Stopping karudeb VNC display $display_arg"
    vnc_stop
    ;;
  restart|force-reload)
    vnc_stop
    vnc_start_with_retry 0
    ;;
  status)
    if vnc_status; then
      echo "karudeb-vnc: display $display_arg is running"
      exit 0
    fi
    echo "karudeb-vnc: display $display_arg is not running"
    exit 3
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|force-reload|status}" >&2
    exit 2
    ;;
esac

exit 0
EOF

  rootfs_cmd rm -f "$ROOTFS_DIR/etc/boot.d/karudeb-vnc"

  if [[ "$KARUDEB_VNC_AUTOSTART" == "1" ]]; then
    enable_sysv_service karudeb-vnc
  else
    disable_sysv_service karudeb-vnc
  fi
}

build_with_mmdebstrap() {
  local mode_args=()
  if [[ -n "${MMDEBSTRAP_MODE:-}" ]]; then
    mode_args=(--mode="$MMDEBSTRAP_MODE")
  fi

  if [[ "$foreign_arch" == "1" ]]; then
    need_cmd arch-test arch-test
    if ! arch-test "$ARCH" >/dev/null 2>&1; then
      die "mmdebstrap foreign builds need active qemu binfmt for $ARCH (install/enable qemu-user-binfmt, or set ROOTFS_BUILDER=debootstrap)"
    fi
  fi

  local cmd=(
    mmdebstrap
    "${mode_args[@]}"
    --architectures="$ARCH"
    --variant="$VARIANT"
    --include="$PACKAGES"
    --components=main
    --aptopt='Apt::Install-Recommends "false"'
    "$SUITE" "$ROOTFS_DIR" "$MIRROR"
  )

  if [[ "$(id -u)" -eq 0 || "$MMDEBSTRAP_USE_SUDO" == "1" ]]; then
    as_root "${cmd[@]}"
  else
    "${cmd[@]}"
  fi
}

build_with_debootstrap() {
  local qemu_bin=""

  if have_cmd "qemu-$ARCH-static"; then
    qemu_bin="$(command -v "qemu-$ARCH-static")"
  elif have_cmd "qemu-$ARCH"; then
    qemu_bin="$(command -v "qemu-$ARCH")"
  else
    die "debootstrap foreign second stage needs qemu-$ARCH-static or qemu-$ARCH"
  fi

  as_root debootstrap \
    --arch="$ARCH" \
    --foreign \
    --variant="$VARIANT" \
    --include="$PACKAGES" \
    "$SUITE" "$ROOTFS_DIR" "$MIRROR"

  as_root install -D -m 0755 "$qemu_bin" "$ROOTFS_DIR/usr/bin/$(basename "$qemu_bin")"
  as_root chroot "$ROOTFS_DIR" "/usr/bin/$(basename "$qemu_bin")" /bin/sh /debootstrap/debootstrap --second-stage
}

configure_locale() {
  write_rootfs_file etc/default/locale <<EOF
LANG=$KARUDEB_LOCALE
EOF

  write_rootfs_file etc/environment <<EOF
LANG=$KARUDEB_LOCALE
EOF
}

configure_rootfs() {
  local shared_ssh_authorized_keys

  shared_ssh_authorized_keys="${KARUDEB_SSH_AUTHORIZED_KEYS:-$ROOT_SSH_AUTHORIZED_KEYS}"

  write_rootfs_file etc/hostname <<EOF
$KARUDEB_HOSTNAME
EOF

  write_rootfs_file etc/hosts <<EOF
127.0.0.1       localhost
127.0.1.1       $KARUDEB_HOSTNAME

::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

  write_rootfs_file etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback

# eth0 is configured by the kernel while mounting NFS root.
# Keep userspace from taking it down and renegotiating the root link.
allow-hotplug eth0
iface eth0 inet manual
EOF

  write_rootfs_file etc/fstab <<'EOF'
/dev/nfs  /      nfs      defaults                      0  0
proc      /proc  proc     defaults                      0  0
sysfs     /sys   sysfs    defaults                      0  0
devtmpfs  /dev   devtmpfs mode=0755                     0  0
tmpfs     /run   tmpfs    nosuid,nodev,mode=0755,size=64M 0  0
tmpfs     /tmp   tmpfs    nosuid,nodev,size=512M        0  0
EOF

  configure_busybox_rescue_init
  configure_locale
  configure_rcs
  configure_openssh
  configure_init_tmpfs_helpers
  configure_benchmark_counters
  configure_perf_run
  configure_openssl_zvk_bench
  configure_openssl_zvk_kat
  configure_zvknhk_openssl
  configure_karudeb_user "$shared_ssh_authorized_keys"

  write_rootfs_file etc/apt/apt.conf.d/99karudeb-no-recommends <<'EOF'
Apt::Install-Recommends "false";
Apt::Install-Suggests "false";
EOF

  write_rootfs_file etc/apt/apt.conf.d/99karudeb-network-root <<'EOF'
Acquire::Languages "none";

// QEMU 9p mapped-xattr does not interact cleanly with apt's _apt sandbox
// chmods on downloaded index files. This image is a lab root shell, so keep
// apt package fetching in the root context.
APT::Sandbox::User "root";
EOF

  if [[ "$KARUDEB_JWM_VNC" == "1" ]]; then
    configure_jwm_vnc
  fi

  write_rootfs_file etc/issue <<EOF
karudeb $ARCH $SUITE \\n \\l

EOF

  write_rootfs_file etc/motd <<EOF
   __  ___                    ___
  /  |/  /__ ____  ___ ___   / _ \_______  _______ ___ ___ ___  _______
 / /|_/ / _ \`/ _ \(_-</ -_) / ___/ __/ _ \/ __/ -_|_-<(_-</ _ \/ __(_-<
/_/  /_/\_,_/_//_/___/\__/ /_/  /_/  \___/\__/\__/___/___/\___/_/ /___/
    __ __                 _____ __ __
   / //_/___ ________  __/ ___// // /  RVA23U64 User Application Profile
  / ,< / __ \`/ ___/ / / / __ \/ // /_  Full RVV 1.0 Vector, VLEN=256
 / /| / /_/ / /  / /_/ / /_/ /__  __/  Full Zvk Vector Crypto Features
/_/ |_\__,_/_/   \__,_/\____/  /_/     + PQC TG Vector Keccak Extension

karudeb: Debian $SUITE $ARCH NFS-root system for karu64
EOF

  configure_inittab
  ensure_securetty
  replace_root_shadow

  rootfs_cmd install -d -m 0755 "$ROOTFS_DIR/root"
  install_authorized_keys root /root 0 0 "${ROOT_SSH_AUTHORIZED_KEYS:-$shared_ssh_authorized_keys}"
  if [[ "$KARUDEB_JWM_VNC" == "1" ]]; then
    install_authorized_keys "$KARUDEB_VNC_USER" "/home/$KARUDEB_VNC_USER" \
      "$KARUDEB_VNC_UID" "$KARUDEB_VNC_GID" "$shared_ssh_authorized_keys"
  fi

  rootfs_cmd install -d -m 0755 "$ROOTFS_DIR/etc"
  rootfs_cmd truncate -s 0 "$ROOTFS_DIR/etc/machine-id"
}

if [[ "${ROOTFS_CONFIGURE_ONLY:-0}" == "1" ]]; then
  [[ -d "$ROOTFS_DIR" ]] || die "rootfs directory not found: $ROOTFS_DIR"
  configure_built_rootfs
  info "Rootfs configured: $ROOTFS_DIR"
  exit 0
fi

if [[ -e "$ROOTFS_DIR" ]]; then
  if [[ "${FORCE:-0}" == "1" ]]; then
    info "Removing existing rootfs: $ROOTFS_DIR"
    safe_remove_rootfs "$ROOTFS_DIR"
  else
    die "$ROOTFS_DIR already exists; set FORCE=1 to recreate it"
  fi
fi

mkdir -p "$(dirname "$ROOTFS_DIR")"

info "Building Debian $SUITE $ARCH rootfs in $ROOTFS_DIR"
info "Packages: $PACKAGES"

case "$ROOTFS_BUILDER" in
  auto)
    if have_cmd mmdebstrap; then
      build_with_mmdebstrap
    elif have_cmd debootstrap; then
      build_with_debootstrap
    else
      die "missing rootfs builder: install mmdebstrap or debootstrap"
    fi
    ;;
  mmdebstrap)
    need_cmd mmdebstrap mmdebstrap
    build_with_mmdebstrap
    ;;
  debootstrap)
    need_cmd debootstrap debootstrap
    build_with_debootstrap
    ;;
  *)
    die "ROOTFS_BUILDER must be auto, mmdebstrap, or debootstrap"
    ;;
esac

configure_built_rootfs

info "Rootfs ready: $ROOTFS_DIR"
rootfs_host_uid="$(stat -c %u "$ROOTFS_DIR")"
if [[ "$rootfs_host_uid" != "0" ]]; then
  info "Note: rootfs is shifted-owned on the host (uid $rootfs_host_uid). Use package-rootfs.sh or rebuild with MMDEBSTRAP_USE_SUDO=1 before NFS export."
fi
info "Export it with: ROOTFS_DIR='$ROOTFS_DIR' $SCRIPT_DIR/export-nfs-root.sh"
