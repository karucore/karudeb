#!/usr/bin/env bash
#
# Build the Zvknhk (vkeccak.vi) OpenSSL benchmark binaries for the karudeb
# target from the riscv-pqc reference tree.
#
# The sources are not repo-local. ../riscv-pqc/zvknhk holds the Keccak backend
# (openssl/keccak1600_zvknhk.c.inc), the anchor-based patch script that layers
# it onto a pristine upstream OpenSSL submodule, and demo/pqcbench.c, the
# ML-KEM/ML-DSA cycle-counting driver. This script applies that patch exactly
# as `make openssl` does there, then configures OpenSSL out of tree into
# build/zvknhk so the riscv-pqc checkout keeps its own build directory.
#
# The binaries are linked fully static. The riscv64-unknown-linux-gnu sysroot
# ships a newer glibc than Debian trixie, so a dynamically linked cross build
# does not run on the Debian rootfs; static linking sidesteps that and also
# lets the same binary run on any RISC-V Linux, including qemu-riscv64.
#
# Outputs (staged for scripts/build-rootfs.sh):
#   build/zvknhk/bin/openssl     patched apps/openssl (static, no-shared)
#   build/zvknhk/bin/pqcbench    demo/pqcbench linked against the same libcrypto
#   build/zvknhk/openssl/        the out-of-tree OpenSSL build directory
#
# Usage:
#   ./scripts/build-zvknhk-openssl.sh [build|check|clean]
#
#   build   patch, configure once, compile, stage (default)
#   check   run known-answer and negative checks under the riscv-pqc user-mode
#           QEMU, if that QEMU has been built
#   clean   remove build/zvknhk

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

RISCV_PQC_DIR="${RISCV_PQC_DIR:-$PROJECT_ROOT/../riscv-pqc}"
ZVKNHK_DIR="$RISCV_PQC_DIR/zvknhk"
SSL_SRC="${SSL_SRC:-$ZVKNHK_DIR/demo/openssl}"
PQCBENCH_SRC="${PQCBENCH_SRC:-$ZVKNHK_DIR/demo/pqcbench.c}"
PATCH_SCRIPT="${PATCH_SCRIPT:-$ZVKNHK_DIR/scripts/apply-openssl-patch.sh}"
QEMU_USER="${QEMU_USER:-$ZVKNHK_DIR/qemu-src/build/qemu-riscv64}"

OUT_DIR="$(abs_path "${OUT_DIR:-$PROJECT_ROOT/build/zvknhk}")"
SSL_BUILD="$OUT_DIR/openssl"
BIN_DIR="$OUT_DIR/bin"
# Records the inputs the OpenSSL build directory was configured with, so a
# changed source tree, cross prefix, or Configure flag set triggers a
# reconfigure instead of silently reusing the old build.
CONFIG_STAMP="$SSL_BUILD/.karudeb-configure"

SSL_CROSS="${SSL_CROSS:-riscv64-unknown-linux-gnu-}"
SSL_PREFIX="${SSL_PREFIX:-/usr/local/openssl-zvknhk}"
# no-shared and -static together give a self-contained apps/openssl. Configure
# turns -static into no-pic and no-threads as well; neither matters for a
# single-threaded benchmark binary. no-dso/no-module drop the loadable-provider
# machinery that static glibc would only warn about, and no-tests keeps the
# build to libcrypto, libssl, and the apps.
SSL_CONFIG_FLAGS="${SSL_CONFIG_FLAGS:-linux64-riscv64 --cross-compile-prefix=$SSL_CROSS --prefix=$SSL_PREFIX --openssldir=$SSL_PREFIX/ssl no-shared no-dso no-module no-tests -static}"
# Extra compiler flags for both OpenSSL (Configure forwards unknown -options to
# CFLAGS) and pqcbench. Empty means the toolchain default, which for the
# riscv64-unknown-linux-gnu GCC here is -march=rv64gcv: GCC then
# autovectorises ML-KEM/ML-DSA arithmetic, which is slow on a core whose
# vector multiply is a multi-cycle FSM. For a scalar baseline build use e.g.
#   OUT_DIR=build/zvknhk-scalar SSL_CFLAGS='-march=rv64gc_zba_zbb_zbs' make zvknhk-openssl
SSL_CFLAGS="${SSL_CFLAGS:-}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
VLEN="${VLEN:-256}"

# The riscv-pqc demo uses OPENSSL_riscvcap to switch the backend, because
# Zvknhk has no hwprobe key. `_v_` needs its own underscore: OpenSSL's parser
# looks for a literal "_V", and "rv64gcv_zvknhk" does not contain one.
CAP="${CAP:-rv64gc_v_zvknhk}"
NOCAP="${NOCAP:-rv64gc}"

# SHA3-256 of the empty input, FIPS 202.
SHA3_256_EMPTY="a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"

usage() {
  cat <<EOF
Usage: $0 [build|check|clean]

Environment:
  RISCV_PQC_DIR     riscv-pqc checkout (default: $RISCV_PQC_DIR)
  OUT_DIR           staging directory (default: $OUT_DIR)
  SSL_CROSS         cross prefix (default: $SSL_CROSS)
  SSL_CONFIG_FLAGS  OpenSSL Configure arguments
  SSL_CFLAGS        extra compiler flags for OpenSSL and pqcbench (default: none)
  JOBS              parallel make jobs (default: $JOBS)
  QEMU_USER         user-mode QEMU with Zvknhk for 'check'
EOF
}

check_sources() {
  [[ -d "$ZVKNHK_DIR" ]] || \
    die "riscv-pqc checkout not found: $ZVKNHK_DIR (set RISCV_PQC_DIR)"
  [[ -x "$PATCH_SCRIPT" ]] || die "missing OpenSSL patch script: $PATCH_SCRIPT"
  [[ -f "$PQCBENCH_SRC" ]] || die "missing pqcbench source: $PQCBENCH_SRC"
  if [[ ! -f "$SSL_SRC/crypto/sha/keccak1600.c" ]]; then
    die "OpenSSL submodule not initialized: $SSL_SRC (run: git -C '$RISCV_PQC_DIR' submodule update --init zvknhk/demo/openssl)"
  fi
  need_cmd "${SSL_CROSS}gcc" "riscv64-unknown-linux-gnu toolchain"
  need_cmd perl perl
  need_cmd make make
}

# Only ever remove trees under this repository's build/ directory. OUT_DIR is
# an override, so a typo must not be able to take out unrelated data; this is
# the same rule safe_remove_rootfs() in common.sh applies.
check_removable() {
  local path="$1"

  [[ "$path" != "/" ]] || die "refusing to remove /"
  [[ "$path" == "$PROJECT_ROOT"/build/* || "${ALLOW_REMOVE_OUTSIDE_BUILD:-0}" == "1" ]] || \
    die "refusing to remove '$path'; set ALLOW_REMOVE_OUTSIDE_BUILD=1 if this is intentional"
}

# The compiler's own version line, so a toolchain change under the same
# cross prefix (for example a riscv-gnu-toolchain rebuild into the same
# install) also triggers a reconfigure and is visible in VERSION.
cross_cc_version() {
  "${SSL_CROSS}gcc" --version 2>/dev/null | head -1
}

configure_inputs() {
  cat <<EOF
ssl_src=$SSL_SRC
cross=$SSL_CROSS
cc=$(cross_cc_version)
prefix=$SSL_PREFIX
configure=$SSL_CONFIG_FLAGS
cflags=$SSL_CFLAGS
EOF
}

ssl_version() {
  local major minor patch
  major="$(sed -n 's/^MAJOR=//p' "$SSL_SRC/VERSION.dat")"
  minor="$(sed -n 's/^MINOR=//p' "$SSL_SRC/VERSION.dat")"
  patch="$(sed -n 's/^PATCH=//p' "$SSL_SRC/VERSION.dat")"
  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

do_build() {
  local ver

  check_sources
  ver="$(ssl_version)"
  info "riscv-pqc: $RISCV_PQC_DIR"
  info "OpenSSL $ver source: $SSL_SRC"
  info "Build directory: $SSL_BUILD"

  info "Applying the Zvknhk OpenSSL patch"
  "$PATCH_SCRIPT"

  # Reuse the build directory only when it was configured with exactly these
  # inputs. Otherwise start it over: Configure alone would leave objects
  # compiled under the previous flags in place.
  if [[ -f "$SSL_BUILD/Makefile" && -f "$CONFIG_STAMP" ]] && \
     cmp -s "$CONFIG_STAMP" <(configure_inputs); then
    info "OpenSSL already configured with the same inputs; reusing $SSL_BUILD"
  else
    if [[ -e "$SSL_BUILD" ]]; then
      info "OpenSSL configuration inputs changed; recreating $SSL_BUILD"
      check_removable "$SSL_BUILD"
      rm -rf "$SSL_BUILD"
    fi
    mkdir -p "$SSL_BUILD"
    info "Configuring OpenSSL: $SSL_CONFIG_FLAGS $SSL_CFLAGS"
    # shellcheck disable=SC2086
    (cd "$SSL_BUILD" && perl "$SSL_SRC/Configure" $SSL_CONFIG_FLAGS $SSL_CFLAGS)
    configure_inputs >"$CONFIG_STAMP"
  fi
  mkdir -p "$BIN_DIR"

  info "Building OpenSSL (-j$JOBS)"
  make -C "$SSL_BUILD" -j"$JOBS" build_sw

  [[ -f "$SSL_BUILD/apps/openssl" ]] || die "OpenSSL build did not produce apps/openssl"
  [[ -f "$SSL_BUILD/libcrypto.a" ]] || die "OpenSSL build did not produce libcrypto.a"
  grep -q 'ZVKNHK' "$SSL_SRC/include/crypto/riscv_arch.def" || \
    die "ZVKNHK capability missing from riscv_arch.def after patching"

  info "Building pqcbench"
  # Same flags as riscv-pqc's demo/Makefile plus -static. The sysroot's
  # setjmp.h declares sigsetjmp() as a plain function while its glibc exports
  # only __sigsetjmp (glibc's own header maps one to the other with a macro),
  # so the mapping is supplied here to keep the static link resolvable.
  # shellcheck disable=SC2086
  "${SSL_CROSS}gcc" -O2 -Wall -static $SSL_CFLAGS \
    -Dsigsetjmp=__sigsetjmp \
    -I"$SSL_SRC/include" -I"$SSL_BUILD/include" \
    -o "$BIN_DIR/pqcbench" "$PQCBENCH_SRC" \
    "$SSL_BUILD/libcrypto.a" -lpthread -ldl

  install -m 0755 "$SSL_BUILD/apps/openssl" "$BIN_DIR/openssl"
  cat >"$OUT_DIR/VERSION" <<EOF
openssl=$ver
riscv_pqc=$(git -C "$RISCV_PQC_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
cross=$SSL_CROSS
cc=$(cross_cc_version)
configure=$SSL_CONFIG_FLAGS
cflags=$SSL_CFLAGS
EOF

  info "Staged: $BIN_DIR/openssl"
  info "Staged: $BIN_DIR/pqcbench"
}

run_qemu() {
  local cpu="$1"
  shift
  "$QEMU_USER" -cpu "$cpu" "$@"
}

do_check() {
  local cpu_vk cpu_no got st fail=0 a b

  [[ -x "$BIN_DIR/openssl" && -x "$BIN_DIR/pqcbench" ]] || \
    die "staged binaries missing; run: $0 build"
  if [[ ! -x "$QEMU_USER" ]]; then
    info "Skipping check: no Zvknhk user-mode QEMU at $QEMU_USER (build it with: make -C '$ZVKNHK_DIR' qemu)"
    return 0
  fi

  cpu_vk="rv64,v=true,vlen=$VLEN,elen=64,zvknhk=true"
  cpu_no="rv64,v=true,vlen=$VLEN,elen=64"
  info "Checking staged binaries under $QEMU_USER (VLEN=$VLEN)"

  got="$(printf '' | OPENSSL_riscvcap="$CAP" run_qemu "$cpu_vk" "$BIN_DIR/openssl" dgst -sha3-256 2>&1 | sed 's/.*= //')"
  if [[ "$got" == "$SHA3_256_EMPTY" ]]; then
    info "  ok   SHA3-256 empty input (vkeccak)"
  else
    info "  FAIL SHA3-256 empty input (vkeccak): $got"
    fail=1
  fi

  got="$(printf '' | OPENSSL_riscvcap="$NOCAP" run_qemu "$cpu_no" "$BIN_DIR/openssl" dgst -sha3-256 2>&1 | sed 's/.*= //')"
  if [[ "$got" == "$SHA3_256_EMPTY" ]]; then
    info "  ok   SHA3-256 empty input (software)"
  else
    info "  FAIL SHA3-256 empty input (software): $got"
    fail=1
  fi

  a="$(OPENSSL_riscvcap="$CAP" run_qemu "$cpu_vk" "$BIN_DIR/pqcbench" fingerprint 1 2>/dev/null)" || a="status $?"
  b="$(OPENSSL_riscvcap="$NOCAP" run_qemu "$cpu_no" "$BIN_DIR/pqcbench" fingerprint 1 2>/dev/null)" || b="status $?"
  if [[ "$a" == "$b" && "$(printf '%s\n' "$a" | grep -c '^ml-')" -eq 3 ]]; then
    info "  ok   ML-KEM/ML-DSA fingerprints agree across both backends"
  else
    info "  FAIL fingerprints differ:"
    printf '%s\n' "$a" "--" "$b" | sed 's/^/         /'
    fail=1
  fi

  st=0
  OPENSSL_riscvcap="$CAP" run_qemu "$cpu_no" "$BIN_DIR/openssl" dgst -sha3-256 /dev/null >/dev/null 2>&1 || st=$?
  if [[ "$st" -eq 132 ]]; then
    info "  ok   negative: SIGILL (132) on a CPU without Zvknhk"
  else
    info "  FAIL negative: exit $st, wanted 132 (128+SIGILL)"
    fail=1
  fi

  [[ "$fail" -eq 0 ]] || die "Zvknhk OpenSSL check failed"
  info "Zvknhk OpenSSL check passed"
}

case "${1:-build}" in
  build) do_build ;;
  check) do_check ;;
  clean) check_removable "$OUT_DIR"; rm -rf "$OUT_DIR"; info "Removed $OUT_DIR" ;;
  -h|--help|help) usage ;;
  *) usage >&2; die "unknown action: $1" ;;
esac
