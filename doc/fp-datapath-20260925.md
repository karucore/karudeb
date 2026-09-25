# Scalar floating point on karu64, bitstream `b11d5efb79a544f9`

Date: 2026-09-25. Board: VCU118, 75 MHz, VLEN=256, 2 GiB DDR4.
Bitstream `b11d5efb79a544f9` (karu64 `7c2563e` / `e240434`) — the two-read
floating-point register file RTL change. Image: karudeb NFS root, Linux 7.2.6,
RVA23S64 profile. Acceptance (`board_accept.sh`) PASSED with the same results as
the two preceding bitstreams (`c61da577`, `03eeb088`).

Summary: Berkeley TestFloat-3e passes clean on this bitstream — 36 functions,
~50.9 million cases, no errors. The scalar FP cycle costs below are the first
FP measurements taken on karu64 hardware; there is no earlier bitstream
baseline to compare them against.

Raw output under `doc/data/`: `board-accept-20260925.txt` (acceptance),
`fp_probe-20260925.txt` (cycle costs), `testfloat-20260925.txt` (TestFloat).

## 1. Cycle costs (`tools/fp_probe.c`)

Run as `perf_run --user-count -- fp_probe` (the fixed counters only advance
while a perf event holds them open). 20000 iterations, best of 5.
Dependent loops use one accumulator, so the figure is the operation's latency;
independent loops use eight accumulators, so the figure is throughput.

| operation | cycles/op | | operation | cycles/op |
|---|---|---|---|---|
| `fmadd.d` dependent  | 66.914 | | `fmadd.s` dependent  | 13.189 |
| `fmadd.d` indep. x8  | 65.883 | | `fmadd.s` indep. x8  | 12.776 |
| `fmul.d`  dependent  | 62.979 | | `fmul.s`  indep. x8  | 10.707 |
| `fmul.d`  indep. x8  | 62.715 | | | |
| `fdiv.d`  indep. x4  | 63.775 | | `fld` indep. x8      |  7.528 |
| `fsqrt.d` indep. x8  | 62.732 | | | |
| `fadd.d`  dependent  |  8.113 | | | |
| `fadd.d`  indep. x8  |  6.932 | | | |
| `fsgnj.d` indep. x8  |  5.329 | | | |

### What sets these numbers

Everything multiply-class in double costs ~63–67 cycles, while `fadd.d` is ~7
and `fsgnj.d` ~5. That is the configured mantissa multiplier, not the register
file:

- `rtl/karu_cfg.vh:55` defaults `KARU_MUL_CYCLES=4` outside `SIM_TB`, and that
  cascades to `KARU_D_MUL_CYCLES` and thence to `KARU_D_FMA_CYCLES`.
- `rtl/karu_fmul_d.v:36` clamps any value other than 1 to `D_MUL_CYCLES = 53`:
  radix-2 bit-serial 53x53.
- `rtl/karu_ffma_d.v:43` gives the fused FMA `latency = 7 + 53 = 60`; measured
  65.9 = 60 plus issue and writeback.
- `fdiv.d` is a separate digit-recurrence unit at `KARU_D_DIV_CYCLES=1`, one
  quotient bit/cycle over 55 fraction bits. `fsqrt.d` is its own fixed
  bit-serial unit, `1 + 54 + 2 = 57` cycles (`rtl/karu_fsqrt_d.v:124`, where the
  reported latency is clamped to the 5-bit port width). Both land beside the
  multiply by coincidence of width, not by sharing its knob.
- Single precision resolves to `F_MUL_CYCLES=4` (6 bits/cycle), giving 10.7 and
  12.8.

So the shipped FPGA build runs double multiply, FMA, divide and square root
bit-serially, by design, for area and timing; in simulation (`SIM_TB`) the same
RTL is combinational. `KARU_D_MUL_CYCLES=1` / `KARU_D_FMA_CYCLES=1` together
with `KARU_D_MUL_PIPE>=2` is the documented lever for a pipelined DSP fast path
if the double datapath is ever worth FPGA timing budget.

### What this says about the two-read register file

Dependent and independent figures agree for every multiply-class operation, so
that unit is unpipelined and its 53 cycles hide whatever the register file's
read ports cost. The FMA-minus-multiply gap — +3.17 cycles double, +2.07 single
— is an *upper bound* on the third-operand read, not an isolated measurement of
it: it also contains the addend alignment work. Isolating the read ports needs a
before/after of this same probe against a bitstream with the previous register
file (`03eeb088`); `fp_probe` runs in seconds, so that pairing is cheap whenever
the earlier bitstream is loaded.

`fp_probe` is now built into the image by `configure_board_accept` in
`scripts/build-rootfs.sh` and reported as an informational block by
`tools/board_accept.sh`, so these numbers are recorded per bitstream from now
on.

## 2. Functional verification: Berkeley TestFloat-3e

`testfloat` tests the machine's own FP against SoftFloat-3e as the reference
model. Sources are vendored in `../karu64/test/{berkeley-softfloat-3,TestFloat-3e}`.

Cross-built for the board (out-of-tree, sources read-only):

```
make -C build/testfloat/softfloat -f <karu64>/test/berkeley-softfloat-3/build/Linux-RISCV64-GCC/Makefile \
  SOURCE_DIR=<karu64>/test/berkeley-softfloat-3/source \
  CC=riscv64-unknown-linux-gnu-gcc MARCH=rv64gc
make -C build/testfloat/testfloat -f <karu64>/test/TestFloat-3e/build/Linux-RISCV64-GCC/Makefile \
  SOURCE_DIR=<karu64>/test/TestFloat-3e/source SOFTFLOAT_DIR=... \
  CC=riscv64-unknown-linux-gnu-gcc MARCH=rv64gc \
  TESTFLOAT_OPTS='-DFLOAT64 -DFLOAT_ROUND_ODD' LINK_FLAGS=-static
```

Build notes:

- `CC` must be passed on the command line. The Makefile writes `CC ?=`, which
  loses to make's built-in `CC=cc`, so a plain environment variable silently
  builds for the host.
- The stock `MARCH` is `rv64g_zfh_zfhmin_zfbfmin0p8` and `TESTFLOAT_OPTS`
  requests `-DFLOAT16 -DBFLOAT16 -DFLOAT128`. karu64 has none of Zfh, Zfhmin or
  Zfbfmin, so both must be cut back to `rv64gc` and f32/f64 only.

### Coverage and caveats

- Level 1, all rounding modes the subject supports, `-checkAll` (so specific
  NaN results and specific invalid integer-conversion results are checked, not
  just "some NaN").
- 36 functions: `ui32/ui64/i32/i64 -> f32/f64`, `f32/f64 -> ui32/ui64/i32/i64`
  (`rx_minMag`), `f32<->f64`, and add / sub / mul / mulAdd / div / sqrt / eq /
  le / lt for both f32 and f64.
- **Four rounding modes, not five.** The subject is `source/subj-C`, which sets
  the mode with `fesetround()`, so only RNE, RTZ, RDN and RUP are reachable.
  RISC-V's fifth mode, RMM (`near_maxMag`, nearest-ties-away), has no C99 name,
  `SUBJFLOAT_ROUND_NEAR_MAXMAG` stays undefined, and TestFloat leaves it
  untested. Covering RMM needs a subject that writes `frm` directly.
- The subject is compiled `-O0`, so `mulAdd` and `sqrt` go through glibc
  `__fma`/`__fmaf`/`__sqrt`/`__sqrtf`. Each of those is a single hardware
  instruction (`fmadd.d`, `fmadd.s`, `fsqrt.d`, `fsqrt.s` — confirmed by
  disassembling the binary), so the hardware is still what gets tested; the call
  only costs time.
- Two-operand f32/f64 functions are 46,464 cases per rounding mode. The
  three-operand `mulAdd` cases are `9 * 88^3 = 6,133,248` per rounding mode
  (`genCases_f32.c:566`), which is ~132x more work — those two functions
  dominate the runtime.

### Results

Level 1, `-checkAll`, `-errors 4`, seed 1. All 36 functions, **no errors in any
function in any rounding mode.** Total wall time 9,275 s (2 h 35 min). The case
total, ~50.9 million, is derived from the generator formulas below rather than
read back from the tool: this run's log kept only the pass/fail line per
function, not the per-function "In N tests" totals.

| function group | functions | modes each | result |
|---|---|---|---|
| `ui32/ui64/i32/i64 -> f32/f64` | 8 | 1 or 4 | no errors |
| `f32/f64 -> ui32/ui64/i32/i64` (`rx_minMag`) | 8 | 1 | no errors |
| `f32_to_f64` / `f64_to_f32` | 2 | 1 / 4 | no errors |
| `f32_add/sub/mul/div` | 4 | 4 | no errors |
| `f64_add/sub/mul/div` | 4 | 4 | no errors |
| `f32_mulAdd` / `f64_mulAdd` | 2 | 4 | no errors |
| `f32_sqrt` / `f64_sqrt` | 2 | 4 | no errors |
| `f32_eq/le/lt`, `f64_eq/le/lt` | 6 | 1 | no errors |

A "1 mode" entry is a function whose result is exact (`ui32_to_f64`,
`i32_to_f64`, `f32_to_f64`), whose rounding is inherent to the function
(`*_rx_minMag`), or which does not round at all (the compares). `f64_to_f32` is
inexact in the narrowing direction, so it is tested in all four.

Case counts follow the generators directly: 1-operand functions are
`3 * NumQOut * NumP1` = 600 (f32) / 768 (f64); 2-operand are
`6 * (22*4)^2` = 46,464 (`genCases_f32.c:486`); 3-operand are
`9 * (22*4)^3` = 6,133,248 (`genCases_f32.c:566`). The two `mulAdd` functions
are therefore 49.1 M of the 50.9 M cases and 93% of the runtime.

Per-function runtime, measured: ~30 s for a two-operand f32 function in all four
modes, 65 min for `f32_mulAdd`, 78 min for `f64_mulAdd`. The cost is set by the
SoftFloat reference executing in software — ~12,000 cycles per case at 75 MHz —
so the hardware's own 66-cycle `fmadd.d` contributes under 1% of it. TestFloat
has no case-count cap and level 1 is already its minimum, so there is no shorter
version of this run.

Reproduce on the board:

```
perf_run --user-count -- ./fp_probe
for f in $(./testfloat -list); do ./testfloat -checkAll -errors 4 $f; done
```
