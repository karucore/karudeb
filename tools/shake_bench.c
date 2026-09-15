// shake_bench.c -- resident-state SHAKE absorb/squeeze cycles on the board.
//
// Linux userspace port of karu64's test/fw/keccak_bench.c, the "Resident
// vkeccak" row of the paper's SHAKE table. The measured loops are byte for
// byte the firmware's: the 1600-bit state stays in v0..v7 across blocks;
// absorb loads one rate block into v8.., XORs it in and permutes; squeeze
// stores one rate block from the state and permutes. Rates 168 B (SHAKE128,
// vl=21) and 136 B (SHAKE256, vl=17). No per-block state reload/writeback,
// which is what the ML-KEM/ML-DSA wrapper pays and this does not.
//
// Cycles come from rdcycle around N unrolled iterations. On karu64 the fixed
// counters only advance while a perf event holds them open, and they count
// all privilege modes unless the event excludes the kernel, so run under
// `perf_run --user-count --`. N is larger than the firmware's 16 so the
// periodic 100 Hz tick averages into the noise; the per-op figure is the
// minimum over REPS repetitions of the whole N-block loop.
//
//   shake_bench [N] [REPS]         defaults 256 blocks, 7 repetitions

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VCLOBBERS "memory", "vl", "vtype", \
    "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", \
    "v8", "v9", "v10", "v11", "v12", "v13", "v14", "v15"

/* vkeccak.vi v0, 0 : .insn r 0x77, 0x2, 0x53, x0, x18, x0 */
#define VKECCAK24 ".word 0xa6092077\n"

static uint64_t st[32] __attribute__((aligned(64)));
static uint64_t *in_blocks, *out_blocks;
static unsigned N = 256, REPS = 7;

static inline uint64_t rdcycle(void)
{
    uint64_t c; __asm volatile("rdcycle %0" : "=r"(c)); return c;
}

/* Warm the input blocks into the data cache the way the firmware does. */
static void warm_input(size_t words)
{
    volatile uint64_t sink = 0;
    for (size_t i = 0; i < words; i++) sink += in_blocks[i];
}

#define ABSORB_LOOP(VL, BYTES)                                            \
    __asm volatile(                                                       \
        "vsetivli x0,25,e64,m8,tu,mu\n"                                   \
        "vle64.v v0,(%[s])\n"                                             \
        "vsetivli x0," #VL ",e64,m8,tu,mu\n"                              \
        "rdcycle %[c0]\n"                                                 \
        "1:\n"                                                            \
        "vle64.v v8,(%[p])\n"                                             \
        "vxor.vv v0,v0,v8\n"                                              \
        VKECCAK24                                                         \
        "addi %[p],%[p]," #BYTES "\n"                                     \
        "addi %[n],%[n],-1\n"                                             \
        "bnez %[n],1b\n"                                                  \
        "rdcycle %[c1]\n"                                                 \
        "vsetivli x0,25,e64,m8,tu,mu\n"                                   \
        "vse64.v v0,(%[s])\n"                                             \
        : [c0] "=&r"(c0), [c1] "=&r"(c1), [p] "+r"(p), [n] "+r"(n)        \
        : [s] "r"(st) : VCLOBBERS)

#define SQUEEZE_LOOP(VL, BYTES)                                           \
    __asm volatile(                                                       \
        "vsetivli x0,25,e64,m8,tu,mu\n"                                   \
        "vle64.v v0,(%[s])\n"                                             \
        "vsetivli x0," #VL ",e64,m8,tu,mu\n"                              \
        "rdcycle %[c0]\n"                                                 \
        "1:\n"                                                            \
        "vse64.v v0,(%[p])\n"                                             \
        VKECCAK24                                                         \
        "addi %[p],%[p]," #BYTES "\n"                                     \
        "addi %[n],%[n],-1\n"                                             \
        "bnez %[n],1b\n"                                                  \
        "rdcycle %[c1]\n"                                                 \
        : [c0] "=&r"(c0), [c1] "=&r"(c1), [p] "+r"(p), [n] "+r"(n)        \
        : [s] "r"(st) : VCLOBBERS)

static uint64_t absorb168(void) { uint64_t c0, c1, *p = in_blocks; long n = N; warm_input(21 * N); ABSORB_LOOP(21, 168); return c1 - c0; }
static uint64_t absorb136(void) { uint64_t c0, c1, *p = in_blocks; long n = N; warm_input(17 * N); ABSORB_LOOP(17, 136); return c1 - c0; }
static uint64_t squeeze168(void){ uint64_t c0, c1, *p = out_blocks; long n = N; SQUEEZE_LOOP(21, 168); return c1 - c0; }
static uint64_t squeeze136(void){ uint64_t c0, c1, *p = out_blocks; long n = N; SQUEEZE_LOOP(17, 136); return c1 - c0; }

/* Bare permutation, state resident: the floor the loops above sit on. */
static uint64_t perm_only(void)
{
    uint64_t c0, c1; long n = N;
    __asm volatile(
        "vsetivli x0,25,e64,m8,tu,mu\n"
        "vle64.v v0,(%[s])\n"
        "rdcycle %[c0]\n"
        "1:\n" VKECCAK24 "addi %[n],%[n],-1\n" "bnez %[n],1b\n"
        "rdcycle %[c1]\n"
        : [c0] "=&r"(c0), [c1] "=&r"(c1), [n] "+r"(n) : [s] "r"(st) : VCLOBBERS);
    return c1 - c0;
}

/* The ML-KEM/ML-DSA wrapper cost for reference: full 25-word reload and
 * writeback around every permutation. */
static uint64_t wrapper(void)
{
    uint64_t c0, c1; long n = N;
    __asm volatile(
        "vsetivli x0,25,e64,m8,tu,mu\n"
        "vle64.v v0,(%[s])\n vse64.v v0,(%[s])\n"
        "rdcycle %[c0]\n"
        "1:\n"
        "vsetivli x0,25,e64,m8,tu,mu\n"
        "vle64.v v0,(%[s])\n" VKECCAK24 "vse64.v v0,(%[s])\n"
        "addi %[n],%[n],-1\n" "bnez %[n],1b\n"
        "rdcycle %[c1]\n"
        : [c0] "=&r"(c0), [c1] "=&r"(c1), [n] "+r"(n) : [s] "r"(st) : VCLOBBERS);
    return c1 - c0;
}

static void report(const char *name, uint64_t (*fn)(void))
{
    uint64_t best = UINT64_MAX;
    fn();                                       /* warm */
    for (unsigned r = 0; r < REPS; r++) { uint64_t c = fn(); if (c < best) best = c; }
    printf("%-34s %8.2f cycles/block  (best of %u x %u blocks)\n",
           name, (double)best / N, REPS, N);
}

int main(int argc, char **argv)
{
    if (argc > 1) N = (unsigned)strtoul(argv[1], NULL, 10);
    if (argc > 2) REPS = (unsigned)strtoul(argv[2], NULL, 10);
    if (!N || !REPS) { fprintf(stderr, "usage: %s [N] [REPS]\n", argv[0]); return 2; }

    /* Probe that rdcycle advances at all (frozen under bare Linux on karu64). */
    { uint64_t a = rdcycle(); volatile int k = 0; for (int i = 0; i < 1000; i++) k += i; uint64_t b = rdcycle();
      if (b == a) { fprintf(stderr, "shake_bench: rdcycle is not advancing; run under perf_run --user-count --\n"); return 1; } }

    in_blocks  = aligned_alloc(64, 21 * 8 * (size_t)N);
    out_blocks = aligned_alloc(64, 21 * 8 * (size_t)N);
    if (!in_blocks || !out_blocks) { perror("alloc"); return 1; }
    for (unsigned i = 0; i < 32; ++i) st[i] = i;
    for (size_t i = 0; i < 21 * (size_t)N; ++i) in_blocks[i] = 0x0101010101010101ULL * i;
    memset(out_blocks, 0, 21 * 8 * (size_t)N);

    printf("[shake_bench: resident-state vkeccak.vi, VLEN=%lu bits, N=%u, REPS=%u]\n",
           ({ unsigned long vlenb; __asm volatile("csrr %0,0xc22" : "=r"(vlenb)); vlenb * 8; }), N, REPS);
    report("vkeccak.vi 24-round, VRF resident", perm_only);
    report("wrapper: vset+vle64+vkeccak+vse64", wrapper);
    report("absorb 168 B (SHAKE128)", absorb168);
    report("absorb 136 B (SHAKE256)", absorb136);
    report("squeeze 168 B (SHAKE128)", squeeze168);
    report("squeeze 136 B (SHAKE256)", squeeze136);
    return 0;
}
