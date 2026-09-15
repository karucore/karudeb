#!/usr/bin/env bash
#
# board_accept -- acceptance checks for a freshly programmed karu64 board,
# run natively on the target after it reaches userspace. Covers the list in
# the karu64 VCU118 handoff: NFS root, Ethernet, kernel version, advertised
# ISA, /dev/kvm, memory, crypto known answers, and the benchmark counters.
#
# Usage: board_accept [--expect-isa EXT,EXT,...] [--mem MiB] [--out DIR]
#
# Every check prints "ok" or "FAIL"; the exit status is the failure count.
# Results and raw logs are written under --out (default board-accept-<time>).

set -u

EXPECT_ISA="${BOARD_ACCEPT_ISA:-}"
MEM_MIB="${BOARD_ACCEPT_MEM:-256}"
OUT_DIR="${BOARD_ACCEPT_OUT:-board-accept-$(date +%Y%m%d-%H%M%S)}"
EXPECT_KERNEL="${BOARD_ACCEPT_KERNEL:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect-isa) EXPECT_ISA="$2"; shift 2 ;;
    --expect-kernel) EXPECT_KERNEL="$2"; shift 2 ;;
    --mem) MEM_MIB="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$OUT_DIR"
FAIL=0
ok()   { printf '  ok   %s\n' "$*"; }
fail() { printf '  FAIL %s\n' "$*"; FAIL=$((FAIL + 1)); }

echo "== board_accept on $(hostname) at $(date)"
uname -a | tee "$OUT_DIR/uname.txt"
echo

echo "== root filesystem"
root_src="$(awk '$2 == "/" {print $1, $3; exit}' /proc/mounts)"
if [[ "$root_src" == *" nfs"* ]]; then ok "root is NFS: $root_src"; else fail "root is not NFS: $root_src"; fi

echo "== ethernet"
if ip -br link show eth0 2>/dev/null | grep -q UP; then ok "eth0 up: $(ip -br addr show eth0 | awk '{print $3}')"; else fail "eth0 not up"; fi
# ping needs cap_net_raw, which an unprivileged user lacks on this image; a
# TCP connect to the NFS server's port 2049 proves the link without it.
nfs_srv="$(awk '$2 == "/" && $3 == "nfs" {split($1, a, ":"); print a[1]; exit}' /proc/mounts)"
if [[ -n "$nfs_srv" ]] && timeout 5 bash -c "exec 3<>/dev/tcp/$nfs_srv/2049" 2>/dev/null; then ok "NFS server $nfs_srv reachable (tcp/2049)"; else fail "cannot reach NFS server ${nfs_srv:-?} on tcp/2049"; fi

echo "== kernel"
kv="$(uname -r)"
if [[ -z "$EXPECT_KERNEL" || "$kv" == "$EXPECT_KERNEL" ]]; then ok "kernel $kv"; else fail "kernel $kv, expected $EXPECT_KERNEL"; fi

# Extensions Linux 7.2 has no cpuinfo token for: present in the DT is all that
# can be checked. ssstateen has no token (smstateen does).
NO_CPUINFO_TOKEN=" ssstateen "
echo "== ISA advertised to Linux"
isa="$(sed -n 's/^isa[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -1)"
printf '%s\n' "$isa" >"$OUT_DIR/isa.txt"
tr '\0' '\n' </proc/device-tree/cpus/cpu@0/riscv,isa-extensions >"$OUT_DIR/dt-isa-extensions.txt" 2>/dev/null
echo "     cpuinfo: $isa"
if [[ -n "$EXPECT_ISA" ]]; then
  for ext in ${EXPECT_ISA//,/ }; do
    if grep -qx "$ext" "$OUT_DIR/dt-isa-extensions.txt"; then
      if [[ "$NO_CPUINFO_TOKEN" == *" $ext "* ]]; then
        ok "$ext in DT (no cpuinfo token in this kernel)"
      elif [[ "$isa" == *"_$ext"* || "$isa" == *"$ext"_* || "$isa" == rv64*"$ext"* ]]; then
        ok "$ext in DT and in cpuinfo"
      else
        # single-letter extensions appear inside the base string
        case "$ext" in
          [a-z]) [[ "$(printf '%s' "$isa" | cut -d_ -f1)" == *"$ext"* ]] && ok "$ext in DT and in cpuinfo" || fail "$ext in DT but Linux did not enable it" ;;
          *) fail "$ext in DT but Linux did not enable it" ;;
        esac
      fi
    else
      fail "$ext not advertised in the device tree"
    fi
  done
fi
if [[ -e /proc/device-tree/cpus/cpu@0/karu,vkeccak ]]; then ok "karu,vkeccak marker present"; else fail "karu,vkeccak marker missing"; fi

echo "== KVM"
if [[ -e /dev/kvm ]]; then
  ok "/dev/kvm present"
  if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
    fail "/dev/kvm not accessible as $(id -un); rerun as root or add $(id -un) to the kvm group"
  elif board_accept kvm >"$OUT_DIR/kvm.txt" 2>&1; then ok "KVM API: VM and vCPU created (guest not run)"; sed 's/^/     /' "$OUT_DIR/kvm.txt"; else fail "KVM API smoke test"; sed 's/^/     /' "$OUT_DIR/kvm.txt"; fi
else
  fail "/dev/kvm absent"
fi

echo "== memory ($MEM_MIB MiB userspace pattern test)"
if board_accept mem "$MEM_MIB" >"$OUT_DIR/mem.txt" 2>&1; then ok "patterns verified"; else fail "memory pattern test"; sed 's/^/     /' "$OUT_DIR/mem.txt"; fi
free -m | sed 's/^/     /' | head -2

echo "== benchmark counters"
pua="$(cat /proc/sys/kernel/perf_user_access 2>/dev/null)"
[[ "$pua" == "2" ]] && ok "perf_user_access=2" || fail "perf_user_access=${pua:-unset}"
if out="$(perf_run --user-count -- /usr/local/bin/pqcbench mlkem-encap 2 1 2>&1)"; then
  # pqcbench's own probe flags any instret/expected ratio outside 0.9..1.1;
  # on karu64 the periodic 100 Hz tick lands a few percent of extra retired
  # instructions in the user-only count, so judge here on the ratio itself:
  # a frozen counter reads x0.00, a live one within 20%.
  ratio="$(printf '%s\n' "$out" | sed -n 's/.*(x\([0-9.]*\)).*/\1/p' | head -1)"
  if [[ -z "$ratio" ]]; then fail "no counter probe output"
  elif awk -v r="$ratio" 'BEGIN {exit !(r >= 0.8 && r <= 1.2)}'; then ok "cycle/instret counters live (probe x$ratio)"
  else fail "cycle/instret counters off: probe x$ratio"; fi
  printf '%s\n' "$out" >"$OUT_DIR/counters.txt"
else
  fail "perf_run/pqcbench: $(printf '%s\n' "$out" | tail -1)"
fi

echo "== crypto known answers (Zvknhk OpenSSL)"
if zvknhk_bench --check-only --out "$OUT_DIR/zvknhk" >"$OUT_DIR/zvknhk-check.txt" 2>&1; then
  ok "zvknhk_bench --check-only: $(grep -c '^  ok' "$OUT_DIR/zvknhk-check.txt") checks"
  grep -q 'trapped with SIGILL' "$OUT_DIR/zvknhk-check.txt" && fail "vkeccak.vi trapped; software path only"
else
  fail "zvknhk_bench --check-only"; grep -E 'FAIL|trapped' "$OUT_DIR/zvknhk-check.txt" | sed 's/^/     /'
fi
if [[ -x ./xtest ]]; then
  if ./xtest >"$OUT_DIR/xtest.txt" 2>&1 && grep -q '^\[INFO\] fail= 0' "$OUT_DIR/xtest.txt"; then ok "riscv-pqc xtest: $(grep -c '^\[PASS\]' "$OUT_DIR/xtest.txt") vectors"; else fail "riscv-pqc xtest"; fi
fi

echo "== vector ABI and cache coverage (vsetvl reserved vtype -> vill; cache windows; state discard across syscalls)"
if command -v vill_probe >/dev/null 2>&1; then
  if vill_probe >"$OUT_DIR/vill_probe.txt" 2>&1; then ok "vill_probe: reserved vtype requests set vill and vl=0"; else fail "vill_probe: $(grep -c "FAIL (spec" "$OUT_DIR/vill_probe.txt") reserved-vtype cases accepted"; grep "FAIL (spec" "$OUT_DIR/vill_probe.txt" | sed 's/^/     /'; fi
else
  echo "     (vill_probe not installed; skipped)"
fi
if command -v cache_window_probe >/dev/null 2>&1; then
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "     (cache_window_probe needs root for /proc/self/pagemap; skipped)"
  elif perf_run --user-count -- "$(command -v cache_window_probe)" >"$OUT_DIR/cache_window_probe.txt" 2>&1; then ok "cache_window_probe: fetch and load cost independent of physical placement ($(grep -E '^(inside|outside)' "$OUT_DIR/cache_window_probe.txt" | awk '{print $3}' | tr '\n' '/' | sed 's|/$||') cyc)"
  else fail "cache_window_probe: $(grep '^FAIL' "$OUT_DIR/cache_window_probe.txt" | tr '\n' ' ')"; fi
fi
vvp="$(command -v validate_v_ptrace 2>/dev/null || ls ./selftests/riscv/vector/validate_v_ptrace 2>/dev/null | head -1)"
if [[ -n "$vvp" ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "     (validate_v_ptrace needs root for ptrace; skipped)"
  elif "$vvp" >"$OUT_DIR/validate_v_ptrace.txt" 2>&1; then ok "validate_v_ptrace: $(grep -c '^ok' "$OUT_DIR/validate_v_ptrace.txt") cases incl. syscall clobbering"; else fail "validate_v_ptrace: $(grep '^not ok' "$OUT_DIR/validate_v_ptrace.txt" | tr '\n' ' ')"; fi
fi

echo
if [[ "$FAIL" -eq 0 ]]; then echo "board_accept: PASS (results in $OUT_DIR)"; else echo "board_accept: $FAIL FAILED (results in $OUT_DIR)"; fi
exit "$FAIL"
