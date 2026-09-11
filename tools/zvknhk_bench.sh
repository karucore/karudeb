#!/usr/bin/env bash
#
# zvknhk_bench -- check and benchmark the Zvknhk (vkeccak.vi) OpenSSL backend
# natively on the karudeb target.
#
# This is the on-target counterpart of ../riscv-pqc/zvknhk/demo: the same
# known-answer, round-trip and fingerprint checks that `make test-openssl`
# runs under QEMU there, followed by what `make -C demo cycles` does on real
# hardware -- pqcbench reading rdcycle/rdinstret around each ML-KEM-768 and
# ML-DSA-65 operation -- and `openssl speed` for the same primitives.
#
# Zvknhk has no hwprobe key, so OpenSSL only uses the instruction when told to
# through OPENSSL_riscvcap. Every step therefore runs twice: once with the
# capability on (vkeccak path) and once with it off (software path), with the
# same binary. `_v_` in the capability string needs its own underscore;
# OpenSSL's parser looks for a literal "_V".

set -u

OPENSSL_BIN="${ZVKNHK_OPENSSL:-/usr/local/openssl-zvknhk/bin/openssl}"
PQCBENCH_BIN="${ZVKNHK_PQCBENCH:-}"
PQC_N="${ZVKNHK_N:-10}"
PQC_REPS="${ZVKNHK_REPS:-5}"
SECONDS_PER_TEST="${ZVKNHK_SECONDS:-5}"
OUT_DIR="${ZVKNHK_OUT:-zvknhk-bench-$(date +%Y%m%d-%H%M%S)}"
CAP="${ZVKNHK_CAP:-rv64gc_v_zvknhk}"
NOCAP="${ZVKNHK_NOCAP:-rv64gc}"
# pqcbench reads cycle/instret directly. On karu64 those fixed counters only
# run while a perf event holds them open, and they count every privilege mode
# unless the event excludes the kernel, so pqcbench is run under
# `perf_run --user-count`, which does both. auto = use perf_run if installed.
PERF_RUN="${ZVKNHK_PERF_RUN:-auto}"
RUN_CHECK=1
RUN_CYCLES=1
RUN_SPEED=1
REQUIRE_ZVKNHK=0
STOP_VNC=0

usage() {
  cat <<'EOF'
Usage: zvknhk_bench [options]

Checks and benchmarks the Zvknhk (vkeccak.vi) OpenSSL backend on this machine:
SHA-3/SHAKE known answers with the instruction on and off, ML-KEM-768 and
ML-DSA-65 round trips, a fingerprint comparison across both backends, then
pqcbench cycle counts and `openssl speed` for both capability strings.

Options:
  --openssl PATH     Zvknhk OpenSSL binary
                     (default: /usr/local/openssl-zvknhk/bin/openssl)
  --pqcbench PATH    pqcbench binary (default: pqcbench in PATH)
  --n N              pqcbench iterations per repetition (default: 10)
  --reps R           pqcbench repetitions, best of R (default: 5)
  --seconds S        seconds per openssl speed run (default: 5)
  --out DIR          output directory for logs and CSV
  --cap STR          OPENSSL_riscvcap for the vkeccak path
                     (default: rv64gc_v_zvknhk)
  --nocap STR        OPENSSL_riscvcap for the software path (default: rv64gc)
  --perf-run PATH    perf_run wrapper for pqcbench (default: auto-detect)
  --no-perf-run      run pqcbench bare (counters may read frozen on karu64)
  --check-only       run the checks only
  --no-check         skip the checks
  --no-cycles        skip pqcbench
  --no-speed         skip openssl speed
  --require-zvknhk   fail instead of falling back when vkeccak.vi traps
  --stop-vnc         stop karudeb-vnc before benchmarking, if present
  -h, --help         Show this help

Environment mirrors the options:
  ZVKNHK_OPENSSL, ZVKNHK_PQCBENCH, ZVKNHK_N, ZVKNHK_REPS, ZVKNHK_SECONDS,
  ZVKNHK_OUT, ZVKNHK_CAP, ZVKNHK_NOCAP, ZVKNHK_PERF_RUN

pqcbench reads the cycle and instret CSRs directly; on karudeb the
karudeb-benchmark-counters service permits that at boot, and perf_run
--user-count keeps the counters running and user-only while pqcbench runs.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --openssl) OPENSSL_BIN="$2"; shift 2 ;;
    --pqcbench) PQCBENCH_BIN="$2"; shift 2 ;;
    --n) PQC_N="$2"; shift 2 ;;
    --reps) PQC_REPS="$2"; shift 2 ;;
    --seconds) SECONDS_PER_TEST="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --cap) CAP="$2"; shift 2 ;;
    --nocap) NOCAP="$2"; shift 2 ;;
    --perf-run) PERF_RUN="$2"; shift 2 ;;
    --no-perf-run) PERF_RUN=none; shift ;;
    --check-only) RUN_CYCLES=0; RUN_SPEED=0; shift ;;
    --no-check) RUN_CHECK=0; shift ;;
    --no-cycles) RUN_CYCLES=0; shift ;;
    --no-speed) RUN_SPEED=0; shift ;;
    --require-zvknhk) REQUIRE_ZVKNHK=1; shift ;;
    --stop-vnc) STOP_VNC=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

find_pqcbench() {
  local self_dir

  if [[ -n "$PQCBENCH_BIN" ]]; then
    printf '%s\n' "$PQCBENCH_BIN"
    return 0
  fi
  if command -v pqcbench >/dev/null 2>&1; then
    command -v pqcbench
    return 0
  fi
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  if [[ -x "$self_dir/pqcbench" ]]; then
    printf '%s\n' "$self_dir/pqcbench"
    return 0
  fi
  return 1
}

[[ -x "$OPENSSL_BIN" ]] || { echo "Zvknhk OpenSSL binary not found: $OPENSSL_BIN" >&2; exit 1; }
PQCBENCH_BIN="$(find_pqcbench || true)"
if [[ "$RUN_CYCLES" == "1" && -z "$PQCBENCH_BIN" ]]; then
  echo "pqcbench not found; install it or use --pqcbench PATH or --no-cycles" >&2
  exit 1
fi

# Command prefix for pqcbench measurements. perf_run execs its argument
# literally, so pqcbench is passed as an absolute path.
PQC_PREFIX=()
PERF_RUN_BIN=""
case "$PERF_RUN" in
  none) ;;
  auto) PERF_RUN_BIN="$(command -v perf_run 2>/dev/null || true)" ;;
  *) PERF_RUN_BIN="$PERF_RUN" ;;
esac
if [[ -n "$PERF_RUN_BIN" ]]; then
  [[ -x "$PERF_RUN_BIN" ]] || { echo "perf_run not found: $PERF_RUN_BIN" >&2; exit 1; }
  PQC_PREFIX=("$PERF_RUN_BIN" --user-count --)
  [[ -n "$PQCBENCH_BIN" ]] && PQCBENCH_BIN="$(cd "$(dirname "$PQCBENCH_BIN")" && pwd -P)/$(basename "$PQCBENCH_BIN")"
fi

if [[ "$STOP_VNC" == "1" && -x /etc/init.d/karudeb-vnc ]]; then
  /etc/init.d/karudeb-vnc stop >/dev/null 2>&1 || true
fi

mkdir -p "$OUT_DIR/logs"
KAT_CSV="$OUT_DIR/kat.csv"
CYCLES_CSV="$OUT_DIR/cycles.csv"
SPEED_CSV="$OUT_DIR/speed.csv"
printf 'check,mode,openssl_riscvcap,expected,actual,pass\n' >"$KAT_CSV"

FAIL=0
ok()   { printf '  ok   %s\n' "$*"; }
fail() { printf '  FAIL %s\n' "$*"; FAIL=1; }

# Run openssl with a capability string. Stdout/stderr go to the caller.
ossl() {
  local cap="$1"
  shift
  OPENSSL_riscvcap="$cap" "$OPENSSL_BIN" "$@"
}

# ------------------------------------------------------------ environment ---

echo "== Zvknhk OpenSSL benchmark =="
echo "OpenSSL:  $OPENSSL_BIN"
"$OPENSSL_BIN" version 2>/dev/null | sed 's/^/          /'
"$OPENSSL_BIN" version -a 2>/dev/null | sed -n 's/^CPUINFO: /          auto-detected /p'
[[ -n "$PQCBENCH_BIN" ]] && echo "pqcbench: $PQCBENCH_BIN"
if [[ -n "$PERF_RUN_BIN" ]]; then
  echo "perf_run: $PERF_RUN_BIN --user-count (fixed counters kept running, user-only)"
else
  echo "perf_run: none (pqcbench reads the counters bare)"
fi
echo "caps:     vkeccak=$CAP software=$NOCAP"
echo "kernel:   $(uname -r 2>/dev/null)"
isa="$(sed -n 's/^isa[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo 2>/dev/null | head -1)"
[[ -n "$isa" ]] && echo "isa:      $isa"
if [[ -e /proc/device-tree/cpus/cpu@0/karu,vkeccak ]]; then
  echo "dtb:      karu,vkeccak present"
fi
if [[ -r /proc/sys/kernel/perf_user_access ]]; then
  pua="$(cat /proc/sys/kernel/perf_user_access)"
  echo "counters: kernel.perf_user_access=$pua"
  if [[ "$pua" != "2" && "$RUN_CYCLES" == "1" ]]; then
    echo "          (not 2: pqcbench falls back to wall clock; run" \
         "'service karudeb-benchmark-counters start' as root)"
  fi
fi
echo "output:   $OUT_DIR"
echo

# ------------------------------------------------------------------ probe ---
#
# Run the smallest thing that executes vkeccak.vi. Exit status 132 is
# 128+SIGILL: the CPU does not implement the instruction, or implements a
# different encoding. Anything else nonzero is a different failure and is
# fatal, since it would make every later result meaningless.

HAVE_VK=1
st=0
ossl "$CAP" dgst -sha3-256 /dev/null >"$OUT_DIR/logs/probe.log" 2>&1 || st=$?
if [[ "$st" -eq 132 ]]; then
  HAVE_VK=0
  echo "vkeccak.vi trapped with SIGILL under OPENSSL_riscvcap=$CAP."
  echo "This CPU does not implement Zvknhk with the encoding this OpenSSL uses;"
  if [[ "$REQUIRE_ZVKNHK" == "1" ]]; then
    echo "--require-zvknhk given, stopping."
    exit 1
  fi
  echo "continuing with the software path only."
  echo
elif [[ "$st" -ne 0 ]]; then
  echo "probe failed with exit status $st:" >&2
  sed 's/^/  /' "$OUT_DIR/logs/probe.log" >&2
  exit 1
fi

MODES="software"
[[ "$HAVE_VK" == "1" ]] && MODES="vkeccak software"

mode_cap() {
  if [[ "$1" == "vkeccak" ]]; then printf '%s\n' "$CAP"; else printf '%s\n' "$NOCAP"; fi
}

# ----------------------------------------------------------------- checks ---
#
# Known answers for the empty input, "<alg>|<extra args>|<expected>". The
# 200-byte SHAKE vectors matter: output shorter than the rate (168 for
# SHAKE128, 136 for SHAKE256) never reaches the permutation call in
# SHA3_squeeze(), so without them only the absorb side is tested.

KATS=(
  "sha3-256||a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"
  "sha3-512||a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26"
  "shake128|-xoflen 32|7f9c2ba4e88f827d616045507605853ed73b8093f6efbc88eb1a6eacfa66ef26"
  "shake256|-xoflen 32|46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762f"
  "shake128|-xoflen 200|7f9c2ba4e88f827d616045507605853ed73b8093f6efbc88eb1a6eacfa66ef263cb1eea988004b93103cfb0aeefd2a686e01fa4a58e8a3639ca8a1e3f9ae57e235b8cc873c23dc62b8d260169afa2f75ab916a58d974918835d25e6a435085b2badfd6dfaac359a5efbb7bcc4b59d538df9a04302e10c8bc1cbf1a0b3a5120ea17cda7cfad765f5623474d368ccca8af0007cd9f5e4c849f167a580b14aabdefaee7eef47cb0fca9767be1fda69419dfb927e9df07348b196691abaeb580b32def58538b8d23f877"
  "shake256|-xoflen 200|46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762fd75dc4ddd8c0f200cb05019d67b592f6fc821c49479ab48640292eacb3b7c4be141e96616fb13957692cc7edd0b45ae3dc07223c8e92937bef84bc0eab862853349ec75546f58fb7c2775c38462c5010d846c185c15111e595522a6bcd16cf86f3d122109e3b1fdd943b6aec468a2d621a7c06c6a957c62b54dafc3be87567d677231395f6147293b68ceab7a9e0c58d864e8efde4e1b9a46cbe854713672f5caaae314ed9083dab"
)

run_checks() {
  local mode cap kat alg args exp got d fp_vk fp_sw

  echo "== checks =="
  for mode in $MODES; do
    cap="$(mode_cap "$mode")"
    for kat in "${KATS[@]}"; do
      alg="${kat%%|*}"
      args="${kat#*|}"; args="${args%%|*}"
      exp="${kat##*|}"
      # shellcheck disable=SC2086
      got="$(printf '' | ossl "$cap" dgst "-$alg" $args 2>&1 | sed 's/.*= //')"
      if [[ "$got" == "$exp" ]]; then
        ok "$(printf '%-20s (%s)' "$alg $args" "$mode")"
        printf '%s,%s,%s,%s,%s,1\n' "$alg${args:+ $args}" "$mode" "$cap" "$exp" "$got" >>"$KAT_CSV"
      else
        fail "$(printf '%-20s (%s): %s' "$alg $args" "$mode" "$got")"
        printf '%s,%s,%s,%s,%s,0\n' "$alg${args:+ $args}" "$mode" "$cap" "$exp" "$got" >>"$KAT_CSV"
      fi
    done

    d="$(mktemp -d)"
    if ossl "$cap" genpkey -algorithm ML-KEM-768 -out "$d/k.pem" >"$OUT_DIR/logs/mlkem-$mode.log" 2>&1 &&
       ossl "$cap" pkeyutl -encap -inkey "$d/k.pem" -secret "$d/s1" -out "$d/ct" >>"$OUT_DIR/logs/mlkem-$mode.log" 2>&1 &&
       ossl "$cap" pkeyutl -decap -inkey "$d/k.pem" -in "$d/ct" -secret "$d/s2" >>"$OUT_DIR/logs/mlkem-$mode.log" 2>&1 &&
       cmp -s "$d/s1" "$d/s2"; then
      ok "ML-KEM-768 keygen/encap/decap ($mode)"
      printf 'ml-kem-768-roundtrip,%s,%s,,,1\n' "$mode" "$cap" >>"$KAT_CSV"
    else
      fail "ML-KEM-768 keygen/encap/decap ($mode)"
      printf 'ml-kem-768-roundtrip,%s,%s,,,0\n' "$mode" "$cap" >>"$KAT_CSV"
    fi
    echo zvknhk >"$d/m"
    if ossl "$cap" genpkey -algorithm ML-DSA-65 -out "$d/d.pem" >"$OUT_DIR/logs/mldsa-$mode.log" 2>&1 &&
       ossl "$cap" pkeyutl -sign -rawin -inkey "$d/d.pem" -in "$d/m" -out "$d/sig" >>"$OUT_DIR/logs/mldsa-$mode.log" 2>&1 &&
       ossl "$cap" pkeyutl -verify -rawin -inkey "$d/d.pem" -in "$d/m" -sigfile "$d/sig" >>"$OUT_DIR/logs/mldsa-$mode.log" 2>&1; then
      ok "ML-DSA-65 keygen/sign/verify ($mode)"
      printf 'ml-dsa-65-roundtrip,%s,%s,,,1\n' "$mode" "$cap" >>"$KAT_CSV"
    else
      fail "ML-DSA-65 keygen/sign/verify ($mode)"
      printf 'ml-dsa-65-roundtrip,%s,%s,,,0\n' "$mode" "$cap" >>"$KAT_CSV"
    fi
    rm -rf "$d"
  done

  # The round trips are self-consistent, so a uniformly wrong Keccak would
  # still pass them. The fingerprint grows both keys from a fixed seed and
  # signs deterministically, so its SHA-256 digests are a pure function of the
  # Keccak implementation and must agree between the two backends.
  if [[ -n "$PQCBENCH_BIN" ]]; then
    fp_sw="$(OPENSSL_riscvcap="$NOCAP" "$PQCBENCH_BIN" fingerprint 1 2>"$OUT_DIR/logs/fingerprint-software.log")" || fp_sw="status $?"
    printf '%s\n' "$fp_sw" >"$OUT_DIR/fingerprint-software.txt"
    if [[ "$HAVE_VK" == "1" ]]; then
      fp_vk="$(OPENSSL_riscvcap="$CAP" "$PQCBENCH_BIN" fingerprint 1 2>"$OUT_DIR/logs/fingerprint-vkeccak.log")" || fp_vk="status $?"
      printf '%s\n' "$fp_vk" >"$OUT_DIR/fingerprint-vkeccak.txt"
      if [[ "$fp_vk" == "$fp_sw" && "$(printf '%s\n' "$fp_vk" | grep -c '^ml-')" -eq 3 ]]; then
        ok "ML-KEM/ML-DSA fingerprints agree across both backends"
        printf 'fingerprint,both,,,,1\n' >>"$KAT_CSV"
      else
        fail "ML-KEM/ML-DSA fingerprints differ:"
        printf '%s\n' "$fp_vk" "--" "$fp_sw" | sed 's/^/         /'
        printf 'fingerprint,both,,,,0\n' >>"$KAT_CSV"
      fi
    else
      printf '%s\n' "$fp_sw" | sed 's/^/  info software fingerprint /'
    fi
  fi
  echo
}

# ----------------------------------------------------------------- cycles ---
#
# pqcbench prints one row per operation: op, cycles/op, insns/op, CPI, ns/op,
# with "-" in the counter columns when the CSRs are not readable. The counter
# check it prints first is kept in the log and echoed here.

run_cycles() {
  local mode cap log

  echo "== pqcbench all $PQC_N $PQC_REPS =="
  printf 'op,mode,openssl_riscvcap,cycles_per_op,insns_per_op,cpi,ns_per_op\n' >"$CYCLES_CSV"
  for mode in $MODES; do
    cap="$(mode_cap "$mode")"
    log="$OUT_DIR/logs/pqcbench-$mode.log"
    echo "-- $mode (OPENSSL_riscvcap=$cap)"
    # Discarded warm-up: the first run after boot pages the static binary in
    # over NFS root, which stretches pqcbench's counter probe and inflates
    # its instruction count.
    OPENSSL_riscvcap="$cap" "${PQC_PREFIX[@]}" "$PQCBENCH_BIN" mlkem-keygen 1 >/dev/null 2>&1 || true
    if OPENSSL_riscvcap="$cap" "${PQC_PREFIX[@]}" "$PQCBENCH_BIN" all "$PQC_N" "$PQC_REPS" >"$log" 2>&1; then
      sed 's/^/   /' "$log"
      awk -v mode="$mode" -v cap="$cap" -v OFS=, \
        '/^(mlkem|mldsa)-/ {print $1, mode, cap, $2, $3, $4, $5}
         /^perf_user_(cycle|instret)=/ {split($0, kv, "="); print "process-" kv[1], mode, cap, kv[2], "", "", ""}' \
        "$log" >>"$CYCLES_CSV"
    else
      fail "pqcbench ($mode) exited $?"
      sed 's/^/   /' "$log"
    fi
  done

  if [[ "$HAVE_VK" == "1" ]]; then
    echo "-- summary (cycles/op, best of $PQC_REPS; process-* rows are whole-run user totals)"
    printf '   %-22s %12s %12s %8s\n' op software vkeccak speedup
    awk -F, 'NR > 1 && $4 != "-" && $4 != "" {
        c[$1 "," $2] = $4; ops[$1] = 1
      }
      END {
        for (op in ops) {
          s = c[op ",software"]; v = c[op ",vkeccak"]
          if (s != "" && v != "" && v > 0)
            printf "   %-22s %12d %12d %7.2fx\n", op, s, v, s / v
        }
      }' "$CYCLES_CSV" | sort -k1,1
  fi
  echo
}

# ------------------------------------------------------------------ speed ---

run_speed() {
  local mode cap alg log line

  echo "== openssl speed -seconds $SECONDS_PER_TEST =="
  printf 'algorithm,mode,openssl_riscvcap,result\n' >"$SPEED_CSV"
  for mode in $MODES; do
    cap="$(mode_cap "$mode")"
    echo "-- $mode (OPENSSL_riscvcap=$cap)"
    for alg in sha3-256 shake128 ML-KEM-768 ML-DSA-65; do
      log="$OUT_DIR/logs/speed-$alg-$mode.log"
      case "$alg" in
        sha3-*|shake*)
          ossl "$cap" speed -seconds "$SECONDS_PER_TEST" -evp "$alg" >"$log" 2>&1 ;;
        *)
          ossl "$cap" speed -seconds "$SECONDS_PER_TEST" "$alg" >"$log" 2>&1 ;;
      esac
      if [[ $? -ne 0 ]]; then
        fail "openssl speed $alg ($mode)"
        tail -3 "$log" | sed 's/^/   /'
        continue
      fi
      # The last line of a speed run is the result row for the algorithm.
      line="$(grep -i -E "^(${alg}|[[:space:]]*${alg})[[:space:]]" "$log" | tail -1)"
      [[ -n "$line" ]] || line="$(tail -1 "$log")"
      printf '   %s\n' "$line"
      printf '%s,%s,%s,"%s"\n' "$alg" "$mode" "$cap" "$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/"/""/g')" >>"$SPEED_CSV"
    done
  done
  echo
}

[[ "$RUN_CHECK" == "1" ]] && run_checks
[[ "$RUN_CYCLES" == "1" ]] && run_cycles
[[ "$RUN_SPEED" == "1" ]] && run_speed

if [[ "$FAIL" -ne 0 ]]; then
  echo "zvknhk_bench: FAILED (see $OUT_DIR)"
  exit 1
fi
echo "zvknhk_bench: done (results in $OUT_DIR)"
