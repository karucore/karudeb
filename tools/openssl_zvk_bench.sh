#!/usr/bin/env bash

set -u

OPENSSL_BIN="${OPENSSL_BIN:-openssl}"
KAT_HELPER="${OPENSSL_ZVK_KAT_HELPER:-}"
SECONDS_PER_TEST="${OPENSSL_ZVK_SECONDS:-5}"
BYTES_PER_TEST="${OPENSSL_ZVK_BYTES:-16384}"
OUT_DIR="${OPENSSL_ZVK_OUT:-openssl-zvk-bench-$(date +%Y%m%d-%H%M%S)}"
CASE_FILTER="${OPENSSL_ZVK_CASES:-}"
CAP_FILTER="${OPENSSL_ZVK_CAPS:-}"
FORCE=0
QUICK=0
LIST_ONLY=0
STOP_VNC=0
RUN_KATS="${OPENSSL_ZVK_KATS:-1}"
KAT_ONLY=0

usage() {
  cat <<'EOF'
Usage: openssl_zvk_bench [options]

Runs OpenSSL speed tests under selected RISC-V capability overrides.
Unsupported forced cap sets are skipped unless --force is used.

Options:
  --openssl PATH       OpenSSL binary to run (default: openssl)
  --kat-helper PATH    OpenSSL Zvk KAT helper (default: openssl_zvk_kat)
  --seconds N          Seconds per speed run (default: 5)
  --bytes N            Buffer size for non-PKI tests (default: 16384)
  --out DIR            Output directory for logs and CSV
  --cases LIST         Comma/space separated case names to run
  --caps LIST          Comma/space separated cap set names to run
  --quick              Run a smaller representative subset
  --kat               Run deterministic known-answer tests before benchmarks
  --kat-only           Run deterministic known-answer tests only
  --no-kat             Skip deterministic known-answer tests
  --force              Run forced cap sets even if not auto-detected
  --stop-vnc           Stop karudeb-vnc before benchmarking, if present
  --list               List cases and cap sets, then exit
  -h, --help           Show this help

Environment mirrors the options:
  OPENSSL_BIN, OPENSSL_ZVK_KAT_HELPER, OPENSSL_ZVK_SECONDS,
  OPENSSL_ZVK_BYTES, OPENSSL_ZVK_OUT, OPENSSL_ZVK_CASES, OPENSSL_ZVK_CAPS,
  OPENSSL_ZVK_KATS

CSV summary is written to OUT/summary.csv. Raw OpenSSL output is kept in OUT/logs.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --openssl) OPENSSL_BIN="$2"; shift 2 ;;
    --kat-helper) KAT_HELPER="$2"; shift 2 ;;
    --seconds) SECONDS_PER_TEST="$2"; shift 2 ;;
    --bytes) BYTES_PER_TEST="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --cases) CASE_FILTER="$2"; shift 2 ;;
    --caps) CAP_FILTER="$2"; shift 2 ;;
    --quick) QUICK=1; shift ;;
    --kat) RUN_KATS=1; shift ;;
    --kat-only) RUN_KATS=1; KAT_ONLY=1; shift ;;
    --no-kat) RUN_KATS=0; shift ;;
    --force) FORCE=1; shift ;;
    --stop-vnc) STOP_VNC=1; shift ;;
    --list) LIST_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! command -v "$OPENSSL_BIN" >/dev/null 2>&1; then
  echo "openssl binary not found: $OPENSSL_BIN" >&2
  exit 1
fi

declare -A CAP_ENV CAP_DESC
CAP_ORDER=()

add_cap() {
  local name="$1" env="$2" desc="$3"
  CAP_ORDER+=("$name")
  CAP_ENV["$name"]="$env"
  CAP_DESC["$name"]="$desc"
}

add_cap auto "" "OpenSSL auto-detected caps"
add_cap scalar "rv64gc" "Disable optional extensions in OpenSSL"
add_cap v "rv64gc_v" "V only, no vector crypto"
add_cap v_zbb "rv64gc_v_zbb" "ChaCha vector baseline without ZVKB"
add_cap v_zbb_zvkb "rv64gc_v_zbb_zvkb" "ChaCha vector with ZVKB"
add_cap zvkned "rv64gc_v_zvkned" "AES vector crypto"
add_cap zvkb_zvkned "rv64gc_v_zvkb_zvkned" "AES vector crypto plus ZVKB"
add_cap zvkg "rv64gc_v_zvkg" "Vector GHASH"
add_cap zvkb_zvkg "rv64gc_v_zvkb_zvkg" "Vector GHASH plus ZVKB init"
add_cap zvkb_zvkg_zvkned "rv64gc_v_zvkb_zvkg_zvkned" "AES-GCM vector path"
add_cap zvkb_zvknha "rv64gc_v_zvkb_zvknha" "SHA-256 vector crypto"
add_cap zvkb_zvknhb "rv64gc_v_zvkb_zvknhb" "SHA-2 vector crypto incl SHA-512"
add_cap zvkb_zvksh "rv64gc_v_zvkb_zvksh" "SM3 vector crypto"
add_cap zvkb_zvksed "rv64gc_v_zvkb_zvksed" "SM4 vector crypto"
add_cap zvbb_zvkg_zvkned "rv64gc_v_zvbb_zvkg_zvkned" "AES-XTS stronger vector path"
add_cap full "" "Force the full auto-detected capability string"

CASES=()
KATS=()

add_case() {
  local name="$1" kind="$2" alg="$3" extra="$4" caps="$5" group="$6"
  CASES+=("$name|$kind|$alg|$extra|$caps|$group")
}

add_kat() {
  local name="$1" kind="$2" alg="$3" key="$4" iv="$5" input="$6" expected="$7" caps="$8"
  KATS+=("$name|$kind|$alg|$key|$iv|$input|$expected|$caps")
}

add_case aes-128-ecb evp aes-128-ecb "" "scalar v zvkned zvkb_zvkned full auto" core
add_case aes-256-ecb evp aes-256-ecb "" "scalar v zvkned zvkb_zvkned full auto" full
add_case aes-128-ctr evp aes-128-ctr "" "scalar v zvkned zvkb_zvkned full auto" core
add_case aes-128-cbc-enc evp aes-128-cbc "" "scalar v zvkned full auto" full
add_case aes-128-cbc-dec evp aes-128-cbc "-decrypt" "scalar v zvkned full auto" full
add_case aes-128-cfb evp aes-128-cfb "" "scalar v zvkned full auto" full
add_case aes-128-ofb evp aes-128-ofb "" "scalar v zvkned full auto" full
add_case aes-128-gcm evp aes-128-gcm "-aead" "scalar v zvkned zvkb_zvkg_zvkned full auto" core
add_case aes-128-ccm evp aes-128-ccm "" "scalar v zvkned full auto" full
add_case aes-128-ocb evp aes-128-ocb "" "scalar v zvkned full auto" full
add_case aes-128-xts evp aes-128-xts "" "scalar v zvkned zvbb_zvkg_zvkned full auto" core
add_case ghash raw ghash "" "scalar v zvkg zvkb_zvkg full auto" core
add_case sha256 raw sha256 "" "scalar v zvkb_zvknha zvkb_zvknhb full auto" core
add_case sha512 raw sha512 "" "scalar v zvkb_zvknhb full auto" core
add_case sm3 evp sm3 "" "scalar v zvkb_zvksh full auto" core
add_case sm4-ecb evp sm4-ecb "" "scalar v zvkb_zvksed full auto" core
add_case sm4-ctr evp sm4-ctr "" "scalar v zvkb_zvksed full auto" full
add_case sm4-cfb evp sm4-cfb "" "scalar v zvkb_zvksed full auto" full
add_case sm4-ofb evp sm4-ofb "" "scalar v zvkb_zvksed full auto" full
add_case sm4-gcm evp sm4-gcm "-aead" "scalar v zvkb_zvksed full auto" full
add_case sm4-ccm evp sm4-ccm "" "scalar v zvkb_zvksed full auto" full
add_case sm4-xts evp sm4-xts "" "scalar v zvkb_zvksed full auto" full
add_case chacha20 evp chacha20 "" "scalar v v_zbb v_zbb_zvkb full auto" core

add_kat aes-128-ecb enc aes-128-ecb \
  000102030405060708090a0b0c0d0e0f "" \
  00112233445566778899aabbccddeeff \
  69c4e0d86a7b0430d8cdb78070b4c55a \
  "scalar v zvkned zvkb_zvkned full auto"
add_kat aes-256-ecb enc aes-256-ecb \
  000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f "" \
  00112233445566778899aabbccddeeff \
  8ea2b7ca516745bfeafc49904b496089 \
  "scalar v zvkned zvkb_zvkned full auto"
add_kat aes-128-ctr enc aes-128-ctr \
  2b7e151628aed2a6abf7158809cf4f3c f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff \
  6bc1bee22e409f96e93d7e117393172a \
  874d6191b620e3261bef6864990db6ce \
  "scalar v zvkned zvkb_zvkned full auto"
add_kat aes-128-cbc enc aes-128-cbc \
  000102030405060708090a0b0c0d0e0f 000102030405060708090a0b0c0d0e0f \
  00112233445566778899aabbccddeeff \
  76d0627da1d290436e21a4af7fca94b7 \
  "scalar v zvkned full auto"
add_kat aes-128-cfb enc aes-128-cfb \
  000102030405060708090a0b0c0d0e0f 000102030405060708090a0b0c0d0e0f \
  00112233445566778899aabbccddeeff \
  0a852986053b9632795a3ee30a8e04a5 \
  "scalar v zvkned full auto"
add_kat aes-128-ofb enc aes-128-ofb \
  000102030405060708090a0b0c0d0e0f 000102030405060708090a0b0c0d0e0f \
  00112233445566778899aabbccddeeff \
  0a852986053b9632795a3ee30a8e04a5 \
  "scalar v zvkned full auto"
add_kat sm4-ecb enc sm4-ecb \
  0123456789abcdeffedcba9876543210 "" \
  0123456789abcdeffedcba9876543210 \
  681edf34d206965e86b3e94f536e4246 \
  "scalar v zvkb_zvksed full auto"
add_kat sm4-cbc enc sm4-cbc \
  0123456789abcdeffedcba9876543210 000102030405060708090a0b0c0d0e0f \
  00112233445566778899aabbccddeeff \
  4691e99a3261b6144f6aa68bea48dbbd \
  "scalar v zvkb_zvksed full auto"
add_kat sm4-ctr enc sm4-ctr \
  0123456789abcdeffedcba9876543210 000102030405060708090a0b0c0d0e0f \
  00112233445566778899aabbccddeeff \
  0689be5279f30edaa2145d392d751795 \
  "scalar v zvkb_zvksed full auto"
add_kat sm4-cfb enc sm4-cfb \
  0123456789abcdeffedcba9876543210 000102030405060708090a0b0c0d0e0f \
  00112233445566778899aabbccddeeff \
  0689be5279f30edaa2145d392d751795 \
  "scalar v zvkb_zvksed full auto"
add_kat sm4-ofb enc sm4-ofb \
  0123456789abcdeffedcba9876543210 000102030405060708090a0b0c0d0e0f \
  00112233445566778899aabbccddeeff \
  0689be5279f30edaa2145d392d751795 \
  "scalar v zvkb_zvksed full auto"
add_kat sha256 dgst sha256 "" "" \
  616263 \
  ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad \
  "scalar v zvkb_zvknha zvkb_zvknhb full auto"
add_kat sha512 dgst sha512 "" "" \
  616263 \
  ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f \
  "scalar v zvkb_zvknhb full auto"
add_kat sm3 dgst sm3 "" "" \
  616263 \
  66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0 \
  "scalar v zvkb_zvksh full auto"
add_kat chacha20 enc chacha20 \
  000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f 000102030405060708090a0b0c0d0e0f \
  00112233445566778899aabbccddeeff000102030405060708090a0b0c0d0e0f \
  b64a529452afe1f8f5f9bc5d148424e8469e0d22997fd176ff8529ddb9ec83ec \
  "scalar v v_zbb v_zbb_zvkb full auto"
add_kat gcm-evp-zero helper gcm-evp-zero "" "" "" \
  0388dace60b6a392f328c2b971b2fe78:ab6e47d42cec13bdf53a67b21257bddf \
  "scalar v zvkned zvkb_zvkg_zvkned full auto"
add_kat ghash-gcm128-zero helper ghash-gcm128-zero "" "" "" \
  0388dace60b6a392f328c2b971b2fe78:ab6e47d42cec13bdf53a67b21257bddf \
  "scalar v zvkg zvkb_zvkg full auto"

normalize_list() {
  printf '%s\n' "$1" | tr ',' ' '
}

want_item() {
  local filter="$1" item="$2" word
  [[ -n "$filter" ]] || return 0
  for word in $(normalize_list "$filter"); do
    [[ "$word" == "$item" ]] && return 0
  done
  return 1
}

sanitize() {
  printf '%s\n' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

csv_escape() {
  local s="$1"
  s="${s//\"/\"\"}"
  printf '"%s"' "$s"
}

hex_to_file() {
  local hex="$1" out="$2" esc="" pair
  hex="${hex//[[:space:]]/}"
  while [[ -n "$hex" ]]; do
    pair="${hex:0:2}"
    esc="${esc}\\x${pair}"
    hex="${hex:2}"
  done
  printf '%b' "$esc" >"$out"
}

file_to_hex() {
  od -An -tx1 -v "$1" | tr -d ' \n'
}

detect_caps() {
  "$OPENSSL_BIN" version -a 2>/dev/null |
    awk -F'OPENSSL_riscvcap=' '/CPUINFO/ {print $2; exit}' |
    awk '{print $1}'
}

find_kat_helper() {
  local self_dir

  if [[ -n "$KAT_HELPER" ]]; then
    printf '%s\n' "$KAT_HELPER"
    return 0
  fi
  if command -v openssl_zvk_kat >/dev/null 2>&1; then
    command -v openssl_zvk_kat
    return 0
  fi
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  if [[ -x "$self_dir/openssl_zvk_kat" ]]; then
    printf '%s\n' "$self_dir/openssl_zvk_kat"
    return 0
  fi
  return 1
}

DETECTED_CAPS="$(detect_caps)"
DETECTED_CAPS_UPPER="${DETECTED_CAPS^^}"
[[ -n "$DETECTED_CAPS" ]] && CAP_ENV[full]="$DETECTED_CAPS"
KAT_HELPER_BIN="$(find_kat_helper || true)"

cap_supported() {
  local name="$1" env="$2" norm token upper
  [[ "$FORCE" == "1" ]] && return 0
  [[ "$name" == "auto" || "$name" == "scalar" ]] && return 0
  [[ -n "$env" && -n "$DETECTED_CAPS_UPPER" ]] || return 1

  norm="_${DETECTED_CAPS_UPPER}_"
  IFS='_' read -r -a toks <<< "$env"
  for token in "${toks[@]}"; do
    upper="${token^^}"
    case "$upper" in
      RV32*|RV64*|I|M|A|F|D|C|G|GC|"") continue ;;
    esac
    if [[ "$upper" == "V" || "$upper" == Z* ]]; then
      [[ "$norm" == *"_${upper}_"* ]] || return 1
    fi
  done
  return 0
}

print_lists() {
  local cap env entry name kind alg extra caps group
  echo "Detected caps: ${DETECTED_CAPS:-unknown}"
  echo
  echo "Cap sets:"
  for cap in "${CAP_ORDER[@]}"; do
    env="${CAP_ENV[$cap]}"
    printf '  %-20s %-55s %s\n' "$cap" "${env:-<auto>}" "${CAP_DESC[$cap]}"
  done
  echo
  echo "Cases:"
  for entry in "${CASES[@]}"; do
    IFS='|' read -r name kind alg extra caps group <<< "$entry"
    printf '  %-18s %-4s %-16s %-10s %s\n' "$name" "$kind" "$alg" "$group" "$caps"
  done
  echo
  echo "KATs:"
  local key iv input expected
  for entry in "${KATS[@]}"; do
    IFS='|' read -r name kind alg key iv input expected caps <<< "$entry"
    printf '  %-18s %-4s %-16s %s\n' "$name" "$kind" "$alg" "$caps"
  done
}

if [[ "$LIST_ONLY" == "1" ]]; then
  print_lists
  exit 0
fi

if [[ "$STOP_VNC" == "1" ]]; then
  if command -v service >/dev/null 2>&1 && [[ -x /etc/init.d/karudeb-vnc ]]; then
    service karudeb-vnc stop >/dev/null 2>&1 || true
  fi
fi

mkdir -p "$OUT_DIR/logs"
mkdir -p "$OUT_DIR/kat"
SUMMARY="$OUT_DIR/summary.csv"
printf 'case,cap_set,openssl_riscvcap,algorithm,requested_seconds,bytes,ops,measured_seconds,bytes_per_second,kbytes_per_second,rc,log\n' >"$SUMMARY"
KAT_SUMMARY="$OUT_DIR/kat.csv"
printf 'kat,cap_set,openssl_riscvcap,expected_hex,actual_hex,scalar_reference_hex,match_expected,match_scalar,rc,log\n' >"$KAT_SUMMARY"

echo "OpenSSL: $("$OPENSSL_BIN" version 2>/dev/null || true)"
echo "Detected caps: ${DETECTED_CAPS:-unknown}"
echo "KAT helper:    ${KAT_HELPER_BIN:-unavailable}"
echo "Seconds/test: $SECONDS_PER_TEST"
echo "Bytes/test:   $BYTES_PER_TEST"
echo "Output:       $OUT_DIR"
echo

run_kat_one() {
  local name="$1" kind="$2" alg="$3" key="$4" iv="$5" input_hex="$6" cap="$7" env="$8"
  local tmpdir in out log rc actual
  local -a cmd

  tmpdir="$OUT_DIR/kat/tmp-${name}-${cap}"
  mkdir -p "$tmpdir"
  in="$tmpdir/in.bin"
  out="$tmpdir/out.bin"
  log="$OUT_DIR/kat/$(sanitize "$name")__$(sanitize "$cap").log"
  hex_to_file "$input_hex" "$in"

  case "$kind" in
    enc)
      cmd=("$OPENSSL_BIN" enc "-$alg" -K "$key" -nosalt -nopad -in "$in" -out "$out")
      [[ -z "$iv" ]] || cmd+=(-iv "$iv")
      ;;
    dgst)
      cmd=("$OPENSSL_BIN" dgst "-$alg" -binary -out "$out" "$in")
      ;;
    helper)
      if [[ -z "$KAT_HELPER_BIN" ]]; then
        echo "openssl_zvk_kat helper not found" >"$log"
        return 127
      fi
      cmd=("$KAT_HELPER_BIN" "$alg")
      ;;
    *)
      echo "internal error: unknown KAT kind $kind" >&2
      return 2
      ;;
  esac

  if [[ "$cap" == "auto" ]]; then
    "${cmd[@]}" >"$log" 2>&1
    rc=$?
  else
    OPENSSL_riscvcap="$env" "${cmd[@]}" >"$log" 2>&1
    rc=$?
  fi

  actual=""
  if [[ "$kind" == "helper" ]]; then
    actual="$(awk 'NF {line=$0} END {print line}' "$log")"
  elif [[ "$rc" == "0" ]]; then
    if [[ -s "$out" ]]; then
      actual="$(file_to_hex "$out")"
    fi
  fi
  printf '%s\n' "$actual"
  return "$rc"
}

run_kats() {
  local entry name kind alg key iv input expected caps cap env actual rc ref
  local match_expected match_scalar log

  echo "KATs:"
  for entry in "${KATS[@]}"; do
    IFS='|' read -r name kind alg key iv input expected caps <<< "$entry"
    want_item "$CASE_FILTER" "$name" || continue
    ref=""
    for cap in $caps; do
      want_item "$CAP_FILTER" "$cap" || continue
      env="${CAP_ENV[$cap]}"
      if ! cap_supported "$cap" "$env"; then
        printf '%-18s %-20s SKIP unsupported by detected caps\n' "$name" "$cap"
        continue
      fi
      actual="$(run_kat_one "$name" "$kind" "$alg" "$key" "$iv" "$input" "$cap" "$env")"
      rc=$?
      log="$OUT_DIR/kat/$(sanitize "$name")__$(sanitize "$cap").log"
      [[ "$cap" == "scalar" && "$rc" == "0" ]] && ref="$actual"
      match_expected=""
      match_scalar=""
      if [[ "$rc" == "0" ]]; then
        [[ -z "$expected" || "$actual" == "$expected" ]] && match_expected=yes || match_expected=no
        [[ -z "$ref" || "$actual" == "$ref" ]] && match_scalar=yes || match_scalar=no
      fi
      {
        csv_escape "$name"; printf ','
        csv_escape "$cap"; printf ','
        csv_escape "$env"; printf ','
        csv_escape "$expected"; printf ','
        csv_escape "$actual"; printf ','
        csv_escape "$ref"; printf ','
        csv_escape "$match_expected"; printf ','
        csv_escape "$match_scalar"; printf ','
        csv_escape "$rc"; printf ','
        csv_escape "$log"; printf '\n'
      } >>"$KAT_SUMMARY"
      if [[ "$rc" == "0" && "$match_expected" != "no" && "$match_scalar" != "no" ]]; then
        printf '%-18s %-20s PASS\n' "$name" "$cap"
      else
        printf '%-18s %-20s FAIL rc=%s expected=%s scalar=%s (%s)\n' \
          "$name" "$cap" "$rc" "$match_expected" "$match_scalar" "$log"
      fi
    done
  done
  echo "KAT summary: $KAT_SUMMARY"
  echo
}

if [[ "$RUN_KATS" == "1" ]]; then
  run_kats
fi

if [[ "$KAT_ONLY" == "1" ]]; then
  echo "Summary: $SUMMARY"
  exit 0
fi

run_one() {
  local name="$1" kind="$2" alg="$3" extra="$4" cap="$5" env="$6"
  local log rc fline rline algorithm ops measured bps kbps
  local -a cmd extra_args

  log="$OUT_DIR/logs/$(sanitize "$name")__$(sanitize "$cap").log"
  cmd=("$OPENSSL_BIN" speed -mr -elapsed -seconds "$SECONDS_PER_TEST" -bytes "$BYTES_PER_TEST")
  case "$kind" in
    evp) cmd+=(-evp "$alg") ;;
    raw) cmd+=("$alg") ;;
    *) echo "internal error: unknown case kind $kind" >&2; return 2 ;;
  esac
  if [[ -n "$extra" ]]; then
    # shellcheck disable=SC2206
    extra_args=($extra)
    cmd+=("${extra_args[@]}")
  fi

  if [[ "$cap" == "auto" ]]; then
    "${cmd[@]}" >"$log" 2>&1
    rc=$?
  else
    OPENSSL_riscvcap="$env" "${cmd[@]}" >"$log" 2>&1
    rc=$?
  fi

  fline="$(awk -F: '/^\+F:/ {line=$0} END {print line}' "$log")"
  rline="$(awk -F: '/^\+R:/ {line=$0} END {print line}' "$log")"
  algorithm=""
  ops=""
  measured=""
  bps=""
  kbps=""
  if [[ -n "$fline" ]]; then
    algorithm="$(awk -F: '{print $3}' <<< "$fline")"
    bps="$(awk -F: '{print $4}' <<< "$fline")"
    kbps="$(awk -v b="$bps" 'BEGIN {printf "%.2f", b / 1000.0}')"
  fi
  if [[ -n "$rline" ]]; then
    ops="$(awk -F: '{print $2}' <<< "$rline")"
    measured="$(awk -F: '{print $4}' <<< "$rline")"
  fi

  {
    csv_escape "$name"; printf ','
    csv_escape "$cap"; printf ','
    csv_escape "$env"; printf ','
    csv_escape "$algorithm"; printf ','
    csv_escape "$SECONDS_PER_TEST"; printf ','
    csv_escape "$BYTES_PER_TEST"; printf ','
    csv_escape "$ops"; printf ','
    csv_escape "$measured"; printf ','
    csv_escape "$bps"; printf ','
    csv_escape "$kbps"; printf ','
    csv_escape "$rc"; printf ','
    csv_escape "$log"; printf '\n'
  } >>"$SUMMARY"

  if [[ "$rc" == "0" && -n "$kbps" ]]; then
    printf '%-18s %-20s %12s kB/s\n' "$name" "$cap" "$kbps"
  else
    printf '%-18s %-20s FAIL rc=%s (%s)\n' "$name" "$cap" "$rc" "$log"
  fi
}

for entry in "${CASES[@]}"; do
  IFS='|' read -r name kind alg extra caps group <<< "$entry"
  want_item "$CASE_FILTER" "$name" || continue
  [[ "$QUICK" == "0" || "$group" == "core" ]] || continue

  for cap in $caps; do
    want_item "$CAP_FILTER" "$cap" || continue
    env="${CAP_ENV[$cap]}"
    if ! cap_supported "$cap" "$env"; then
      printf '%-18s %-20s SKIP unsupported by detected caps\n' "$name" "$cap"
      continue
    fi
    run_one "$name" "$kind" "$alg" "$extra" "$cap" "$env"
  done
done

echo
echo "Summary: $SUMMARY"
