#!/bin/sh
# vkeccak.vi encoding conformance on real hardware, native Linux.
#
# Port of riscv-pqc zvknhk/test/run_edge_cases.sh to a running board: the same
# 20 encodings and the same per-VLEN expectations, but the trap verdict is a
# process killed by SIGILL (shell status 132) instead of a simulator message.
# One case per process, because an illegal instruction ends the process.
#
#   vkeccak_encodings.sh [VLEN]        default 256
set -u
vlen="${1:-256}"
probe=./edge_probe0           # one binary, case number passed as argv[1]
cases='0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19'

expectation() {
    case "$1" in
        0|8|14) echo legal ;;
        1|2|7|16) [ "$vlen" -ge 256 ] && echo legal || echo illegal ;;
        5) [ "$vlen" -eq 128 ] && echo legal || echo illegal ;;
        12) { [ "$vlen" -eq 128 ] || [ "$vlen" -ge 2048 ]; } && echo legal || echo illegal ;;
        13) { [ "$vlen" -eq 128 ] || [ "$vlen" -ge 512 ]; } && echo legal || echo illegal ;;
        17) { [ "$vlen" -eq 128 ] || [ "$vlen" -ge 1024 ]; } && echo legal || echo illegal ;;
        18) { [ "$vlen" -eq 128 ] || [ "$vlen" -ge 4096 ]; } && echo either || echo illegal ;;
        *) echo illegal ;;
    esac
}

echo "== vkeccak.vi encoding conformance, VLEN=$vlen, native"
pass=0; fail=0
for n in $cases; do
    out=$("$probe" "$n" 2>&1); rc=$?
    want=$(expectation "$n")
    label=$(printf '%s' "$out" | sed -n 's/.*(\(.*\))$/\1/p')
    [ -n "$label" ] || label="(trapped)"
    if printf '%s' "$out" | grep -Eq '^RESULT ok vl=[0-9]+ vstart_after=0 bad=0 '; then
        got=legal
    elif [ "$rc" -eq 132 ] || [ "$rc" -eq 4 ]; then
        got=illegal
    else
        got="other(rc=$rc)"
    fi
    if [ "$want" = "$got" ] || { [ "$want" = either ] && [ "$got" != "other(rc=$rc)" ]; }; then
        printf '  ok   case %-2s %-9s %s\n' "$n" "$got" "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL case %-2s wanted %s, got %s  %s\n' "$n" "$want" "$got" "$label"
        printf '%s\n' "$out" | tail -n 4 | sed 's/^/         /'
        fail=$((fail + 1))
    fi
done
echo "== $pass/$((pass + fail)) encodings behave as specified"
exit "$fail"
