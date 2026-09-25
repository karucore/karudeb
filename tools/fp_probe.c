// fp_probe.c -- scalar FP throughput and latency on the target.
//
// Written for the karu64 two-read floating-point register file change: an
// FMA reads three registers, an add or multiply reads two. With fewer read
// ports than an FMA needs, the register file must take an extra cycle to
// collect the third operand, so independent FMAs cost more per operation
// than independent multiplies. Same-shape loops for both make that
// difference, if any, directly visible.
//
// Each loop is 16 unrolled operations; the accumulators are chosen so the
// values stay near 1.0, away from denormals and infinities, and no
// exception flags are raised.
//
//   dependent    one accumulator: consecutive ops are serialised, so the
//                figure is the operation's latency.
//   independent  eight accumulators: the figure is throughput, bounded by
//                issue rate and register-file ports, not latency.
//
// Measured on the FPGA build (see doc/fp-datapath-20260925.md), the double
// multiply, FMA, divide and square root all cost ~63-67 cycles because
// KARU_D_MUL_CYCLES resolves to a bit-serial 53x53 mantissa multiply, and
// dependent equals independent because that unit is not pipelined. The
// fmadd-minus-fmul gap is therefore an upper bound on the third-operand read,
// not an isolated measurement of it: the short ops (fadd.d ~7, fsgnj.d ~5)
// are where register-file effects are visible at all.
//
// Cycles come from rdcycle. On karu64 the fixed counters only advance while
// a perf event holds them open, so run this under `perf_run --user-count --`.
//
//   fp_probe [ITERS] [REPS]        defaults 20000 iterations, 5 repetitions
//                                  (each iteration is 16 operations)

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned ITERS = 20000, REPS = 5;

/* operands: a ~1.0, b ~1.0, c tiny, so a*b+c and a*b stay near 1.0 */
static double d_val[4] = { 1.0000000001, 0.9999999999, 1e-12, 4.0 };
static float  f_val[4] = { 1.0000001f, 0.9999999f, 1e-12f, 4.0f };

/* The clobber list is the same for every loop, so it lives here rather than
 * as a macro argument: a comma-separated list cannot be passed as one. */
#define TIME_LOOP(SETUP, BODY)                                             \
    do {                                                                   \
        uint64_t c0, c1; long n = ITERS;                                   \
        __asm volatile(                                                    \
            SETUP                                                          \
            "rdcycle %[c0]\n"                                              \
            "1:\n" ".rept 16\n" BODY ".endr\n"                             \
            "addi %[n], %[n], -1\n"                                        \
            "bnez %[n], 1b\n"                                              \
            "rdcycle %[c1]\n"                                              \
            : [c0] "=&r"(c0), [c1] "=&r"(c1), [n] "+r"(n)                  \
            : [d] "r"(d_val), [f] "r"(f_val)                               \
            : "memory", "ft0", "ft1", "ft2", "ft3", "ft4", "ft5", "ft6",   \
              "ft7", "ft8", "ft9", "ft10");                                \
        cycles = c1 - c0;                                                  \
    } while (0)

/* load the three double operands into ft8, ft9, ft10 and seed ft0..ft7 */
#define SETUP_D                                                            \
    "fld ft8, 0(%[d])\n fld ft9, 8(%[d])\n fld ft10, 16(%[d])\n"           \
    "fld ft0, 0(%[d])\n fmv.d ft1, ft0\n fmv.d ft2, ft0\n fmv.d ft3, ft0\n"\
    "fmv.d ft4, ft0\n fmv.d ft5, ft0\n fmv.d ft6, ft0\n fmv.d ft7, ft0\n"
#define SETUP_F                                                            \
    "flw ft8, 0(%[f])\n flw ft9, 4(%[f])\n flw ft10, 8(%[f])\n"            \
    "flw ft0, 0(%[f])\n fmv.s ft1, ft0\n fmv.s ft2, ft0\n fmv.s ft3, ft0\n"\
    "fmv.s ft4, ft0\n fmv.s ft5, ft0\n fmv.s ft6, ft0\n fmv.s ft7, ft0\n"

/* eight independent chains, one per accumulator */
#define EIGHT(OP, SRC2)                                                    \
    OP " ft0, ft0, " SRC2 "\n" OP " ft1, ft1, " SRC2 "\n"                  \
    OP " ft2, ft2, " SRC2 "\n" OP " ft3, ft3, " SRC2 "\n"                  \
    OP " ft4, ft4, " SRC2 "\n" OP " ft5, ft5, " SRC2 "\n"                  \
    OP " ft6, ft6, " SRC2 "\n" OP " ft7, ft7, " SRC2 "\n"
#define EIGHT3(OP, SRC2, SRC3)                                             \
    OP " ft0, ft0, " SRC2 ", " SRC3 "\n" OP " ft1, ft1, " SRC2 ", " SRC3 "\n" \
    OP " ft2, ft2, " SRC2 ", " SRC3 "\n" OP " ft3, ft3, " SRC2 ", " SRC3 "\n" \
    OP " ft4, ft4, " SRC2 ", " SRC3 "\n" OP " ft5, ft5, " SRC2 ", " SRC3 "\n" \
    OP " ft6, ft6, " SRC2 ", " SRC3 "\n" OP " ft7, ft7, " SRC2 ", " SRC3 "\n"

static void report(const char *name, unsigned ops_per_iter, uint64_t best)
{
    printf("  %-34s %8.3f cycles/op\n", name,
           (double)best / ((double)ITERS * ops_per_iter));
}

#define RUN(name, ops, setup, body)                                        \
    do {                                                                   \
        uint64_t cycles, best = UINT64_MAX;                                \
        for (unsigned r = 0; r < REPS + 1; r++) {                          \
            TIME_LOOP(setup, body);                                        \
            if (r && cycles < best) best = cycles;   /* drop the warm-up */ \
        }                                                                  \
        report(name, ops, best);                                           \
    } while (0)

int main(int argc, char **argv)
{
    if (argc > 1) ITERS = (unsigned)strtoul(argv[1], NULL, 10);
    if (argc > 2) REPS  = (unsigned)strtoul(argv[2], NULL, 10);
    if (!ITERS || !REPS) { fprintf(stderr, "usage: %s [ITERS] [REPS]\n", argv[0]); return 2; }

    {   /* the counters must be running, or every figure below is zero */
        uint64_t a, b; volatile int k = 0; (void)k;
        __asm volatile("rdcycle %0" : "=r"(a));
        for (int i = 0; i < 1000; i++) k += i;
        __asm volatile("rdcycle %0" : "=r"(b));
        if (a == b) {
            fprintf(stderr, "fp_probe: rdcycle is not advancing; "
                            "run under perf_run --user-count --\n");
            return 1;
        }
    }

    printf("[fp_probe: %u iterations, best of %u; dependent loops 16 ops/iter,"
           " independent loops 256]\n", ITERS, REPS);

    puts("-- double precision");
    RUN("fmadd.d dependent (latency)", 16, SETUP_D, "fmadd.d ft0, ft0, ft9, ft10\n");
    RUN("fmadd.d independent x8",      256, SETUP_D, EIGHT3("fmadd.d", "ft9", "ft10") EIGHT3("fmadd.d", "ft9", "ft10"));
    RUN("fmul.d  independent x8",      256, SETUP_D, EIGHT("fmul.d", "ft9") EIGHT("fmul.d", "ft9"));
    RUN("fadd.d  independent x8",      256, SETUP_D, EIGHT("fadd.d", "ft10") EIGHT("fadd.d", "ft10"));
    RUN("fmul.d  dependent (latency)", 16, SETUP_D, "fmul.d ft0, ft0, ft9\n");
    RUN("fadd.d  dependent (latency)", 16, SETUP_D, "fadd.d ft0, ft0, ft10\n");
    RUN("fdiv.d  independent x4",      256, SETUP_D,
        "fdiv.d ft0, ft0, ft9\n fdiv.d ft1, ft1, ft9\n fdiv.d ft2, ft2, ft9\n fdiv.d ft3, ft3, ft9\n"
        "fdiv.d ft4, ft4, ft9\n fdiv.d ft5, ft5, ft9\n fdiv.d ft6, ft6, ft9\n fdiv.d ft7, ft7, ft9\n"
        "fdiv.d ft0, ft0, ft9\n fdiv.d ft1, ft1, ft9\n fdiv.d ft2, ft2, ft9\n fdiv.d ft3, ft3, ft9\n"
        "fdiv.d ft4, ft4, ft9\n fdiv.d ft5, ft5, ft9\n fdiv.d ft6, ft6, ft9\n fdiv.d ft7, ft7, ft9\n");
    RUN("fsqrt.d independent x8",      256, SETUP_D,
        "fsqrt.d ft0, ft0\n fsqrt.d ft1, ft1\n fsqrt.d ft2, ft2\n fsqrt.d ft3, ft3\n"
        "fsqrt.d ft4, ft4\n fsqrt.d ft5, ft5\n fsqrt.d ft6, ft6\n fsqrt.d ft7, ft7\n"
        "fsqrt.d ft0, ft0\n fsqrt.d ft1, ft1\n fsqrt.d ft2, ft2\n fsqrt.d ft3, ft3\n"
        "fsqrt.d ft4, ft4\n fsqrt.d ft5, ft5\n fsqrt.d ft6, ft6\n fsqrt.d ft7, ft7\n");
    RUN("fsgnj.d independent x8",      256, SETUP_D, EIGHT("fsgnj.d", "ft9") EIGHT("fsgnj.d", "ft9"));

    puts("-- single precision");
    RUN("fmadd.s dependent (latency)", 16, SETUP_F, "fmadd.s ft0, ft0, ft9, ft10\n");
    RUN("fmadd.s independent x8",      256, SETUP_F, EIGHT3("fmadd.s", "ft9", "ft10") EIGHT3("fmadd.s", "ft9", "ft10"));
    RUN("fmul.s  independent x8",      256, SETUP_F, EIGHT("fmul.s", "ft9") EIGHT("fmul.s", "ft9"));

    puts("-- memory side (for reference)");
    RUN("fld     independent x8",      256, SETUP_D,
        "fld ft0, 0(%[d])\n fld ft1, 8(%[d])\n fld ft2, 16(%[d])\n fld ft3, 24(%[d])\n"
        "fld ft4, 0(%[d])\n fld ft5, 8(%[d])\n fld ft6, 16(%[d])\n fld ft7, 24(%[d])\n"
        "fld ft0, 0(%[d])\n fld ft1, 8(%[d])\n fld ft2, 16(%[d])\n fld ft3, 24(%[d])\n"
        "fld ft4, 0(%[d])\n fld ft5, 8(%[d])\n fld ft6, 16(%[d])\n fld ft7, 24(%[d])\n");

    puts("\nAn FMA reads three registers, fmul/fadd read two, so fmadd minus");
    puts("fmul bounds the third-operand read cost -- loosely, since it also");
    puts("contains the addend work. Where the mantissa multiply is bit-serial,");
    puts("its latency dominates and dependent equals independent.");
    return 0;
}
