//  rvv_poy.c

#if MLDSA_RVV == 1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../plat_local.h"
#include <riscv_vector.h>

#include "mldsa_params.h"
#include "mldsa_reduce.h"

#if defined(MARIAN_BUILD) && defined(MLDSA_RVV_NTT_OPT_OS)
#define MLDSA_RVV_NTT_ATTR __attribute__((optimize("Os")))
#else
#define MLDSA_RVV_NTT_ATTR
#endif

// Run rejection sampling on uniform random bytes to generate uniform
// integers mod q. Each candidate is encoded as 23 bits in three bytes.
unsigned int mldsa_rej_uniform(int32_t *a, unsigned int len, const uint8_t *buf,
                         unsigned int buflen)
{
    const size_t vl = 8;          // e32m1 over VLEN=256
    const size_t raw_vl = 3 * vl; // 24 packed bytes -> 8 candidates

    unsigned int ctr = 0;
    unsigned int pos = 0;

    while (ctr < len && pos + raw_vl <= buflen) {
        vuint8mf4x3_t raw = __riscv_vlseg3e8_v_u8mf4x3(&buf[pos], vl);
        pos += raw_vl;

        vuint32m1_t x = __riscv_vzext_vf4_u32m1(
            __riscv_vget_v_u8mf4x3_u8mf4(raw, 0), vl);
        x = __riscv_vor_vv_u32m1(
            x,
            __riscv_vsll_vx_u32m1(
                __riscv_vzext_vf4_u32m1(
                    __riscv_vget_v_u8mf4x3_u8mf4(raw, 1), vl),
                8, vl),
            vl);
        x = __riscv_vor_vv_u32m1(
            x,
            __riscv_vsll_vx_u32m1(
                __riscv_vzext_vf4_u32m1(
                    __riscv_vget_v_u8mf4x3_u8mf4(raw, 2), vl),
                16, vl),
            vl);
        x = __riscv_vand_vx_u32m1(x, 0x7FFFFF, vl);

        vbool32_t lt = __riscv_vmsltu_vx_u32m1_b32(x, MLDSA_PAR_Q, vl);
        size_t n = __riscv_vcpop_m_b32(lt, vl);

        if (n == vl) {
            size_t store_n = len - ctr < vl ? len - ctr : vl;
            __riscv_vse32_v_u32m1((uint32_t *) &a[ctr], x, store_n);
            ctr += store_n;
        } else {
            vuint32m1_t y = __riscv_vcompress_vm_u32m1(x, lt, vl);
            if (ctr + n > len) {
                n = len - ctr;
            }
            __riscv_vse32_v_u32m1((uint32_t *) &a[ctr], y, n);
            ctr += n;
        }
    }

    // Finish any short tail without vector over-read.
    while (ctr < len && pos + 3 <= buflen) {
        uint32_t t = buf[pos++];
        t |= (uint32_t) buf[pos++] << 8;
        t |= (uint32_t) buf[pos++] << 16;
        t &= 0x7FFFFF;

        if (t < MLDSA_PAR_Q) {
            a[ctr++] = t;
        }
    }

    return ctr;
}

/*
n = 256
q = 8380417
signq(x) = t=lift(x)%q;if(t>q/2,t-q,t)
r1 = signq(2^32)
qi = lift(Mod(q,2^32)^-1)
*/

#define PARAM_R1 -4186625
#define MLDSA_PAR_QI 58728449

inline vint32m1_t fq_redc2(vint64m2_t a, size_t vl)
{
    vint32m1_t t;

    t = __riscv_vncvt_x_x_w_i32m1(a, vl);
    t = __riscv_vmul_vx_i32m1(t, MLDSA_PAR_QI, vl);
    a = __riscv_vsub_vv_i64m2(a, __riscv_vwmul_vx_i64m2(t, MLDSA_PAR_Q, vl),
                              vl);
    t = __riscv_vnsra_wx_i32m1(a, 32, vl);

    return t;
}

static const int32_t zetas[MLDSA_PAR_N] = {
    0,        25847,    -2608894, -518909,  237124,   -777960,  -876248,
    466468,   1826347,  2353451,  -359251,  -2091905, 3119733,  -2884855,
    3111497,  2680103,  2725464,  1024112,  -1079900, 3585928,  -549488,
    -1119584, 2619752,  -2108549, -2118186, -3859737, -1399561, -3277672,
    1757237,  -19422,   4010497,  280005,   2706023,  95776,    3077325,
    3530437,  -1661693, -3592148, -2537516, 3915439,  -3861115, -3043716,
    3574422,  -2867647, 3539968,  -300467,  2348700,  -539299,  -1699267,
    -1643818, 3505694,  -3821735, 3507263,  -2140649, -1600420, 3699596,
    811944,   531354,   954230,   3881043,  3900724,  -2556880, 2071892,
    -2797779, -3930395, -1528703, -3677745, -3041255, -1452451, 3475950,
    2176455,  -1585221, -1257611, 1939314,  -4083598, -1000202, -3190144,
    -3157330, -3632928, 126922,   3412210,  -983419,  2147896,  2715295,
    -2967645, -3693493, -411027,  -2477047, -671102,  -1228525, -22981,
    -1308169, -381987,  1349076,  1852771,  -1430430, -3343383, 264944,
    508951,   3097992,  44288,    -1100098, 904516,   3958618,  -3724342,
    -8578,    1653064,  -3249728, 2389356,  -210977,  759969,   -1316856,
    189548,   -3553272, 3159746,  -1851402, -2409325, -177440,  1315589,
    1341330,  1285669,  -1584928, -812732,  -1439742, -3019102, -3881060,
    -3628969, 3839961,  2091667,  3407706,  2316500,  3817976,  -3342478,
    2244091,  -2446433, -3562462, 266997,   2434439,  -1235728, 3513181,
    -3520352, -3759364, -1197226, -3193378, 900702,   1859098,  909542,
    819034,   495491,   -1613174, -43260,   -522500,  -655327,  -3122442,
    2031748,  3207046,  -3556995, -525098,  -768622,  -3595838, 342297,
    286988,   -2437823, 4108315,  3437287,  -3342277, 1735879,  203044,
    2842341,  2691481,  -2590150, 1265009,  4055324,  1247620,  2486353,
    1595974,  -3767016, 1250494,  2635921,  -3548272, -2994039, 1869119,
    1903435,  -1050970, -1333058, 1237275,  -3318210, -1430225, -451100,
    1312455,  3306115,  -1962642, -1279661, 1917081,  -2546312, -1374803,
    1500165,  777191,   2235880,  3406031,  -542412,  -2831860, -1671176,
    -1846953, -2584293, -3724270, 594136,   -3776993, -2013608, 2432395,
    2454455,  -164721,  1957272,  3369112,  185531,   -1207385, -3183426,
    162844,   1616392,  3014001,  810149,   1652634,  -3694233, -1799107,
    -3038916, 3523897,  3866901,  269760,   2213111,  -975884,  1717735,
    472078,   -426683,  1723600,  -1803090, 1910376,  -1667432, -1104333,
    -260646,  -3833893, -2939036, -2235985, -420899,  -2286327, 183443,
    -976891,  1612842,  -3545687, -554416,  3919660,  -48306,   -1362209,
    3937738,  1400424,  -846154,  1976782};

const int32_t rvv_zeta[256] = {
    2091667,  3407706,  2316500,  3817976,  -3342478, 2244091,
    -2446433, -3562462, 2725464,  2706023,  95776,    -3930395,
    -1528703, -3677745, -3041255, 0,  // 0
    266997,   2434439,  -1235728, 3513181,  -3520352, -3759364,
    -1197226, -3193378, 1024112,  3077325,  3530437,  -1452451,
    3475950,  2176455,  -1585221, 25847,  // 10
    900702,   1859098,  909542,   819034,   495491,   -1613174,
    -43260,   -522500,  -1079900, -1661693, -3592148, -1257611,
    1939314,  -4083598, -1000202, -2608894,  // 20
    -655327,  -3122442, 2031748,  3207046,  -3556995, -525098,
    -768622,  -3595838, 3585928,  -2537516, 3915439,  -3190144,
    -3157330, -3632928, 126922,   -518909,  // 30
    342297,   286988,   -2437823, 4108315,  3437287,  -3342277,
    1735879,  203044,   -549488,  -3861115, -3043716, 3412210,
    -983419,  2147896,  2715295,  237124,  // 40
    2842341,  2691481,  -2590150, 1265009,  4055324,  1247620,
    2486353,  1595974,  -1119584, 3574422,  -2867647, -2967645,
    -3693493, -411027,  -2477047, -777960,  // 50
    -3767016, 1250494,  2635921,  -3548272, -2994039, 1869119,
    1903435,  -1050970, 2619752,  3539968,  -300467,  -671102,
    -1228525, -22981,   -1308169, -876248,  // 60
    -1333058, 1237275,  -3318210, -1430225, -451100,  1312455,
    3306115,  -1962642, -2108549, 2348700,  -539299,  -381987,
    1349076,  1852771,  -1430430, 466468,  // 70
    -1279661, 1917081,  -2546312, -1374803, 1500165,  777191,
    2235880,  3406031,  -2118186, -1699267, -1643818, -3343383,
    264944,   508951,   3097992,  1826347,  // 80
    -542412,  -2831860, -1671176, -1846953, -2584293, -3724270,
    594136,   -3776993, -3859737, 3505694,  -3821735, 44288,
    -1100098, 904516,   3958618,  2353451,  // 90
    -2013608, 2432395,  2454455,  -164721,  1957272,  3369112,
    185531,   -1207385, -1399561, 3507263,  -2140649, -3724342,
    -8578,    1653064,  -3249728, -359251,  // a0
    -3183426, 162844,   1616392,  3014001,  810149,   1652634,
    -3694233, -1799107, -3277672, -1600420, 3699596,  2389356,
    -210977,  759969,   -1316856, -2091905,  // b0
    -3038916, 3523897,  3866901,  269760,   2213111,  -975884,
    1717735,  472078,   1757237,  811944,   531354,   189548,
    -3553272, 3159746,  -1851402, 3119733,  // c0
    -426683,  1723600,  -1803090, 1910376,  -1667432, -1104333,
    -260646,  -3833893, -19422,   954230,   3881043,  -2409325,
    -177440,  1315589,  1341330,  -2884855,  // d0
    -2939036, -2235985, -420899,  -2286327, 183443,   -976891,
    1612842,  -3545687, 4010497,  3900724,  -2556880, 1285669,
    -1584928, -812732,  -1439742, 3111497,  // e0
    -554416,  3919660,  -48306,   -1362209, 3937738,  1400424,
    -846154,  1976782,  280005,   2071892,  -2797779, -3019102,
    -3881060, -3628969, 3839961,  2680103,  // f0
};

const int32_t rvv_izeta[256] = {
    -1976782, 846154,   -1400424, -3937738, 1362209,  48306,
    -3919660, 554416,   -280005,  2797779,  -2071892, -3839961,
    3628969,  3881060,  3019102,  0,         3545687,  -1612842,
    976891,   -183443,  2286327,  420899,     2235985,  2939036,
    -4010497, 2556880,  -3900724, 1439742,  812732,   1584928,
    -1285669, 0,         3833893,  260646,    1104333,  1667432,
    -1910376, 1803090,  -1723600, 426683,     19422,      -3881043,
    -954230,  -1341330, -1315589, 177440,     2409325,  0,
    -472078,  -1717735, 975884,   -2213111, -269760,  -3866901,
    -3523897, 3038916,  -1757237, -531354,  -811944,  1851402,
    -3159746, 3553272,  -189548,  0,         1799107,  3694233,
    -1652634, -810149,  -3014001, -1616392, -162844,  3183426,
    3277672,  -3699596, 1600420,  1316856,  -759969,  210977,
    -2389356, 0,         1207385,  -185531,  -3369112, -1957272,
    164721,   -2454455, -2432395, 2013608,  1399561,  2140649,
    -3507263, 3249728,  -1653064, 8578,   3724342,  0,
    3776993,  -594136,  3724270,  2584293,  1846953,  1671176,
    2831860,  542412,   3859737,  3821735,  -3505694, -3958618,
    -904516,  1100098,  -44288,   0,         -3406031, -2235880,
    -777191,  -1500165, 1374803,  2546312,  -1917081, 1279661,
    2118186,  1643818,  1699267,  -3097992, -508951,  -264944,
    3343383,  0,         1962642,  -3306115, -1312455, 451100,
    1430225,  3318210,  -1237275, 1333058,  2108549,  539299,
    -2348700, 1430430,  -1852771, -1349076, 381987,   0,
    1050970,  -1903435, -1869119, 2994039,  3548272,  -2635921,
    -1250494, 3767016,  -2619752, 300467,     -3539968, 1308169,
    22981,    1228525,  671102,   0,         -1595974, -2486353,
    -1247620, -4055324, -1265009, 2590150,  -2691481, -2842341,
    1119584,  2867647,  -3574422, 2477047,  411027,   3693493,
    2967645,  0,         -203044,  -1735879, 3342277,  -3437287,
    -4108315, 2437823,  -286988,  -342297,  549488,   3043716,
    3861115,  -2715295, -2147896, 983419,     -3412210, 0,
    3595838,  768622,   525098,   3556995,  -3207046, -2031748,
    3122442,  655327,   -3585928, -3915439, 2537516,  -126922,
    3632928,  3157330,  3190144,  0,         522500,      43260,
    1613174,  -495491,  -819034,  -909542,  -1859098, -900702,
    1079900,  3592148,  1661693,  1000202,  4083598,  -1939314,
    1257611,  0,         3193378,  1197226,  3759364,  3520352,
    -3513181, 1235728,  -2434439, -266997,  -1024112, -3530437,
    -3077325, 1585221,  -2176455, -3475950, 1452451,  0,
    3562462,  2446433,  -2244091, 3342478,  -3817976, -2316500,
    -3407706, -2091667, -2725464, -95776,     -2706023, 3041255,
    3677745,  1528703,  3930395,  0,
};

#define RVV_BFLY_FX2(u0, u1, ut, uz, vl)                       \
    {                                                          \
        ut = fq_redc2(__riscv_vwmul_vx_i64m2(u1, uz, vl), vl); \
        u1 = __riscv_vsub_vv_i32m1(u0, ut, vl);                \
        u0 = __riscv_vadd_vv_i32m1(u0, ut, vl);                \
    }

#define RVV_BFLY_FV2(u0, u1, ut, uz, vl)                       \
    {                                                          \
        ut = fq_redc2(__riscv_vwmul_vv_i64m2(u1, uz, vl), vl); \
        u1 = __riscv_vsub_vv_i32m1(u0, ut, vl);                \
        u0 = __riscv_vadd_vv_i32m1(u0, ut, vl);                \
    }

#define RVV_BFLY_RX2(u0, u1, ut, uz, vl)                       \
    {                                                          \
        ut = __riscv_vsub_vv_i32m1(u0, u1, vl);                \
        u0 = __riscv_vadd_vv_i32m1(u0, u1, vl);                \
        u1 = fq_redc2(__riscv_vwmul_vx_i64m2(ut, uz, vl), vl); \
    }

#define RVV_BFLY_RV2(u0, u1, ut, uz, vl)                       \
    {                                                          \
        ut = __riscv_vsub_vv_i32m1(u0, u1, vl);                \
        u0 = __riscv_vadd_vv_i32m1(u0, u1, vl);                \
        u1 = fq_redc2(__riscv_vwmul_vv_i64m2(ut, uz, vl), vl); \
    }

//  create a permutation for swapping index bits a and b, a < b

static MLDSA_RVV_NTT_ATTR vuint32m2_t bitswap_perm(unsigned a, unsigned b, size_t vl)
{
    const vuint32m2_t v2id = __riscv_vid_v_u32m2(vl);

    vuint32m2_t xa, xb;
    xa = __riscv_vsrl_vx_u32m2(v2id, b - a, vl);
    xa = __riscv_vxor_vv_u32m2(xa, v2id, vl);
    xa = __riscv_vand_vx_u32m2(xa, (1 << a), vl);
    xb = __riscv_vsll_vx_u32m2(xa, b - a, vl);
    xa = __riscv_vxor_vv_u32m2(xa, xb, vl);
    xa = __riscv_vxor_vv_u32m2(v2id, xa, vl);
    return xa;
}

static MLDSA_RVV_NTT_ATTR void vector_ntt2(int32_t *a, vint32m1_t v0, vint32m1_t v1, size_t o)
{
    size_t vl = 8;  //__riscv_vsetvlmax_e16m1();
    size_t vl2 = 2 * vl;

    const vuint32m2_t v2p4 = bitswap_perm(2, 3, vl2);
    const vuint32m2_t v2p2 = bitswap_perm(1, 3, vl2);
    const vuint32m2_t v2p1 = bitswap_perm(0, 3, vl2);

    //  p0 = p4(p2(p1))
    const vuint32m2_t v2p0 = __riscv_vrgather_vv_u32m2(
        __riscv_vrgather_vv_u32m2(v2p1, v2p2, vl2), v2p4, vl2);

    const vuint32m1_t vid = __riscv_vid_v_u32m1(vl);
    const vuint32m1_t cs4 =
        __riscv_vadd_vx_u32m1(__riscv_vsrl_vx_u32m1(vid, 2, vl), 1, vl);
    const vuint32m1_t cs2 =
        __riscv_vadd_vx_u32m1(__riscv_vsrl_vx_u32m1(vid, 1, vl), 3, vl);

    vint32m1_t c0, c8, cz, vt;
    vint32m2_t vp;

    c8 = __riscv_vle32_v_i32m1(&rvv_zeta[o], 8);
    cz = __riscv_vle32_v_i32m1(&rvv_zeta[o + 8], 8);

    RVV_BFLY_FX2(v0, v1, vt, __riscv_vmv_x_s_i32m1_i32(cz), vl);  //    0

    vp = __riscv_vcreate_v_i32m1_i32m2(v0, v1);
    vp = __riscv_vrgather_vv_i32m2(vp, v2p4, vl2);

    v0 = __riscv_vget_v_i32m2_i32m1(vp, 0);
    v1 = __riscv_vget_v_i32m2_i32m1(vp, 1);
    c0 = __riscv_vrgather_vv_i32m1(cz, cs4, vl);  //    2 3
    RVV_BFLY_FV2(v0, v1, vt, c0, vl);
    vp = __riscv_vcreate_v_i32m1_i32m2(v0, v1);

    //
    vp = __riscv_vrgather_vv_i32m2(vp, v2p2, vl2);
    v0 = __riscv_vget_v_i32m2_i32m1(vp, 0);
    v1 = __riscv_vget_v_i32m2_i32m1(vp, 1);
    c0 = __riscv_vrgather_vv_i32m1(cz, cs2, vl);
    RVV_BFLY_FV2(v0, v1, vt, c0, vl);
    vp = __riscv_vcreate_v_i32m1_i32m2(v0, v1);

    //
    vp = __riscv_vrgather_vv_i32m2(vp, v2p1, vl2);
    v0 = __riscv_vget_v_i32m2_i32m1(vp, 0);
    v1 = __riscv_vget_v_i32m2_i32m1(vp, 1);
    RVV_BFLY_FV2(v0, v1, vt, c8, vl);
    vp = __riscv_vcreate_v_i32m1_i32m2(v0, v1);

    //
    vp = __riscv_vrgather_vv_i32m2(vp, v2p0, vl2);
    __riscv_vse32_v_i32m2(&a[o], vp, 2 * vl);
}

static MLDSA_RVV_NTT_ATTR vint32m2_t vector_intt2(vint32m2_t vp, size_t o)
{
    size_t vl = 8;  //__riscv_vsetvlmax_e32m1();
    size_t vl2 = 2 * vl;

    const vuint32m2_t v2p4 = bitswap_perm(2, 3, vl2);
    const vuint32m2_t v2p2 = bitswap_perm(1, 3, vl2);
    const vuint32m2_t v2p1 = bitswap_perm(0, 3, vl2);

    const vuint32m2_t v2pi = __riscv_vrgather_vv_u32m2(
        __riscv_vrgather_vv_u32m2(v2p4, v2p2, vl2), v2p1, vl2);

    const vuint32m1_t vid = __riscv_vid_v_u32m1(vl);
    const vuint32m1_t cs4 =
        __riscv_vadd_vx_u32m1(__riscv_vsrl_vx_u32m1(vid, 2, vl), 1, vl);
    const vuint32m1_t cs2 =
        __riscv_vadd_vx_u32m1(__riscv_vsrl_vx_u32m1(vid, 1, vl), 3, vl);

    vint32m1_t c0, c8, cz, vt;
    vint32m1_t v0, v1;

    c8 = __riscv_vle32_v_i32m1(&rvv_izeta[o], 8);
    cz = __riscv_vle32_v_i32m1(&rvv_izeta[o + 8], 8);

    vp = __riscv_vrgather_vv_i32m2(vp, v2pi, vl2);
    v0 = __riscv_vget_v_i32m2_i32m1(vp, 0);
    v1 = __riscv_vget_v_i32m2_i32m1(vp, 1);
    RVV_BFLY_RV2(v0, v1, vt, c8, vl);

    vp = __riscv_vcreate_v_i32m1_i32m2(v0, v1);
    vp = __riscv_vrgather_vv_i32m2(vp, v2p1, vl2);
    v0 = __riscv_vget_v_i32m2_i32m1(vp, 0);
    v1 = __riscv_vget_v_i32m2_i32m1(vp, 1);
    c0 = __riscv_vrgather_vv_i32m1(cz, cs2, vl);
    RVV_BFLY_RV2(v0, v1, vt, c0, vl);

    vp = __riscv_vcreate_v_i32m1_i32m2(v0, v1);
    vp = __riscv_vrgather_vv_i32m2(vp, v2p2, vl2);
    v0 = __riscv_vget_v_i32m2_i32m1(vp, 0);
    v1 = __riscv_vget_v_i32m2_i32m1(vp, 1);
    c0 = __riscv_vrgather_vv_i32m1(cz, cs4, vl);
    RVV_BFLY_RV2(v0, v1, vt, c0, vl);

    vp = __riscv_vcreate_v_i32m1_i32m2(v0, v1);
    vp = __riscv_vrgather_vv_i32m2(vp, v2p4, vl2);
    v0 = __riscv_vget_v_i32m2_i32m1(vp, 0);
    v1 = __riscv_vget_v_i32m2_i32m1(vp, 1);
    RVV_BFLY_RX2(v0, v1, vt, __riscv_vmv_x_s_i32m1_i32(cz), vl);

    return __riscv_vcreate_v_i32m1_i32m2(v0, v1);
}

MLDSA_RVV_NTT_ATTR void mldsa_ntt(int32_t a[MLDSA_PAR_N])
{
    size_t vl = 8;  //__riscv_vsetvlmax_e32m1();
    size_t len, i, j;
    int32_t zeta;

    len = MLDSA_PAR_N / 2;

    //  first layer
    zeta = rvv_zeta[0x1f];

    for (j = 0; j < len; j += vl) {

        vint32m1_t v0, v1;
        vint32m1_t vt;

        v0 = __riscv_vle32_v_i32m1(&a[j], vl);
        v1 = __riscv_vle32_v_i32m1(&a[j + len], vl);
        RVV_BFLY_FX2(v0, v1, vt, zeta, vl);
        __riscv_vse32_v_i32m1(&a[j], v0, vl);
        __riscv_vse32_v_i32m1(&a[j + len], v1, vl);
    }

    //  2 * len == 16 * vl

    for (i = 0; i < MLDSA_PAR_N; i += 16 * vl) {
        int32_t *b;

        b = &a[i];

        vint32m1_t vt;
        vint32m1_t v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, va, vb, vc, vd, ve,
            vf;

        v0 = __riscv_vle32_v_i32m1(&b[0], vl);
        v1 = __riscv_vle32_v_i32m1(&b[vl], vl);
        v2 = __riscv_vle32_v_i32m1(&b[2 * vl], vl);
        v3 = __riscv_vle32_v_i32m1(&b[3 * vl], vl);
        v4 = __riscv_vle32_v_i32m1(&b[4 * vl], vl);
        v5 = __riscv_vle32_v_i32m1(&b[5 * vl], vl);
        v6 = __riscv_vle32_v_i32m1(&b[6 * vl], vl);
        v7 = __riscv_vle32_v_i32m1(&b[7 * vl], vl);
        v8 = __riscv_vle32_v_i32m1(&b[8 * vl], vl);
        v9 = __riscv_vle32_v_i32m1(&b[9 * vl], vl);
        va = __riscv_vle32_v_i32m1(&b[10 * vl], vl);
        vb = __riscv_vle32_v_i32m1(&b[11 * vl], vl);
        vc = __riscv_vle32_v_i32m1(&b[12 * vl], vl);
        vd = __riscv_vle32_v_i32m1(&b[13 * vl], vl);
        ve = __riscv_vle32_v_i32m1(&b[14 * vl], vl);
        vf = __riscv_vle32_v_i32m1(&b[15 * vl], vl);

        zeta = rvv_zeta[0x2f + (i >> 3)];
        RVV_BFLY_FX2(v0, v8, vt, zeta, vl);
        RVV_BFLY_FX2(v1, v9, vt, zeta, vl);
        RVV_BFLY_FX2(v2, va, vt, zeta, vl);
        RVV_BFLY_FX2(v3, vb, vt, zeta, vl);
        RVV_BFLY_FX2(v4, vc, vt, zeta, vl);
        RVV_BFLY_FX2(v5, vd, vt, zeta, vl);
        RVV_BFLY_FX2(v6, ve, vt, zeta, vl);
        RVV_BFLY_FX2(v7, vf, vt, zeta, vl);

        zeta = rvv_zeta[0x4F + (i >> 2)];
        RVV_BFLY_FX2(v0, v4, vt, zeta, vl);
        RVV_BFLY_FX2(v1, v5, vt, zeta, vl);
        RVV_BFLY_FX2(v2, v6, vt, zeta, vl);
        RVV_BFLY_FX2(v3, v7, vt, zeta, vl);

        zeta = rvv_zeta[0x5F + (i >> 2)];
        RVV_BFLY_FX2(v8, vc, vt, zeta, vl);
        RVV_BFLY_FX2(v9, vd, vt, zeta, vl);
        RVV_BFLY_FX2(va, ve, vt, zeta, vl);
        RVV_BFLY_FX2(vb, vf, vt, zeta, vl);

        zeta = rvv_zeta[0x8F + (i >> 1)];
        RVV_BFLY_FX2(v0, v2, vt, zeta, vl);
        RVV_BFLY_FX2(v1, v3, vt, zeta, vl);
        zeta = rvv_zeta[0x9F + (i >> 1)];
        RVV_BFLY_FX2(v4, v6, vt, zeta, vl);
        RVV_BFLY_FX2(v5, v7, vt, zeta, vl);
        zeta = rvv_zeta[0xAF + (i >> 1)];
        RVV_BFLY_FX2(v8, va, vt, zeta, vl);
        RVV_BFLY_FX2(v9, vb, vt, zeta, vl);
        zeta = rvv_zeta[0xBF + (i >> 1)];
        RVV_BFLY_FX2(vc, ve, vt, zeta, vl);
        RVV_BFLY_FX2(vd, vf, vt, zeta, vl);

        vector_ntt2(a, v0, v1, i);
        vector_ntt2(a, v2, v3, i + 2 * vl);
        vector_ntt2(a, v4, v5, i + 4 * vl);
        vector_ntt2(a, v6, v7, i + 6 * vl);
        vector_ntt2(a, v8, v9, i + 8 * vl);
        vector_ntt2(a, va, vb, i + 10 * vl);
        vector_ntt2(a, vc, vd, i + 12 * vl);
        vector_ntt2(a, ve, vf, i + 14 * vl);
    }
}

/*************************************************
 * Name:        invntt_tomont
 *
 * Description: Inverse NTT and multiplication by Montgomery factor 2^32.
 *              In-place. No modular reductions after additions or
 *              subtractions; input coefficients need to be smaller than
 *              Q in absolute value. Output coefficient are smaller than Q in
 *              absolute value.
 *
 * Arguments:   - uint32_t p[MLDSA_PAR_N]: input/output coefficient array
 **************************************************/

MLDSA_RVV_NTT_ATTR void mldsa_invntt(int32_t a[MLDSA_PAR_N])
{
    size_t i, j;
    int32_t zeta;
    const int32_t f = 41978;  // mont^2/256
    const size_t vl = 8;     //__riscv_vsetvlmax_e32m1();
    const size_t vl2 = 2 * vl;

    for (i = 0; i < MLDSA_PAR_N; i += 16 * vl) {
        vint32m1_t vt;
        vint32m1_t v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, va, vb, vc, vd, ve,
            vf;
        vint32m2_t vp;

        vp = vector_intt2(__riscv_vle32_v_i32m2(&a[i], vl2), i);
        v0 = __riscv_vget_v_i32m2_i32m1(vp, 0);
        v1 = __riscv_vget_v_i32m2_i32m1(vp, 1);

        vp = vector_intt2(__riscv_vle32_v_i32m2(&a[i + 2 * vl], vl2),
                          i + 2 * vl);
        v2 = __riscv_vget_v_i32m2_i32m1(vp, 0);
        v3 = __riscv_vget_v_i32m2_i32m1(vp, 1);

        vp = vector_intt2(__riscv_vle32_v_i32m2(&a[i + 4 * vl], vl2),
                          i + 4 * vl);
        v4 = __riscv_vget_v_i32m2_i32m1(vp, 0);
        v5 = __riscv_vget_v_i32m2_i32m1(vp, 1);

        vp = vector_intt2(__riscv_vle32_v_i32m2(&a[i + 6 * vl], vl2),
                          i + 6 * vl);
        v6 = __riscv_vget_v_i32m2_i32m1(vp, 0);
        v7 = __riscv_vget_v_i32m2_i32m1(vp, 1);

        vp = vector_intt2(__riscv_vle32_v_i32m2(&a[i + 8 * vl], vl2),
                          i + 8 * vl);
        v8 = __riscv_vget_v_i32m2_i32m1(vp, 0);
        v9 = __riscv_vget_v_i32m2_i32m1(vp, 1);

        vp = vector_intt2(__riscv_vle32_v_i32m2(&a[i + 10 * vl], vl2),
                          i + 10 * vl);
        va = __riscv_vget_v_i32m2_i32m1(vp, 0);
        vb = __riscv_vget_v_i32m2_i32m1(vp, 1);

        vp = vector_intt2(__riscv_vle32_v_i32m2(&a[i + 12 * vl], vl2),
                          i + 12 * vl);
        vc = __riscv_vget_v_i32m2_i32m1(vp, 0);
        vd = __riscv_vget_v_i32m2_i32m1(vp, 1);

        vp = vector_intt2(__riscv_vle32_v_i32m2(&a[i + 14 * vl], vl2),
                          i + 14 * vl);
        ve = __riscv_vget_v_i32m2_i32m1(vp, 0);
        vf = __riscv_vget_v_i32m2_i32m1(vp, 1);

        const size_t g16 = i >> 5;
        const size_t g32 = i >> 6;

        zeta = -zetas[15 - g16];
        RVV_BFLY_RX2(v0, v2, vt, zeta, vl);
        RVV_BFLY_RX2(v1, v3, vt, zeta, vl);
        zeta = -zetas[15 - (g16 + 1)];
        RVV_BFLY_RX2(v4, v6, vt, zeta, vl);
        RVV_BFLY_RX2(v5, v7, vt, zeta, vl);
        zeta = -zetas[15 - (g16 + 2)];
        RVV_BFLY_RX2(v8, va, vt, zeta, vl);
        RVV_BFLY_RX2(v9, vb, vt, zeta, vl);
        zeta = -zetas[15 - (g16 + 3)];
        RVV_BFLY_RX2(vc, ve, vt, zeta, vl);
        RVV_BFLY_RX2(vd, vf, vt, zeta, vl);

        zeta = -zetas[7 - g32];
        RVV_BFLY_RX2(v0, v4, vt, zeta, vl);
        RVV_BFLY_RX2(v1, v5, vt, zeta, vl);
        RVV_BFLY_RX2(v2, v6, vt, zeta, vl);
        RVV_BFLY_RX2(v3, v7, vt, zeta, vl);

        zeta = -zetas[7 - (g32 + 1)];
        RVV_BFLY_RX2(v8, vc, vt, zeta, vl);
        RVV_BFLY_RX2(v9, vd, vt, zeta, vl);
        RVV_BFLY_RX2(va, ve, vt, zeta, vl);
        RVV_BFLY_RX2(vb, vf, vt, zeta, vl);

        zeta = -zetas[3 - (i >> 7)];
        RVV_BFLY_RX2(v0, v8, vt, zeta, vl);
        RVV_BFLY_RX2(v1, v9, vt, zeta, vl);
        RVV_BFLY_RX2(v2, va, vt, zeta, vl);
        RVV_BFLY_RX2(v3, vb, vt, zeta, vl);
        RVV_BFLY_RX2(v4, vc, vt, zeta, vl);
        RVV_BFLY_RX2(v5, vd, vt, zeta, vl);
        RVV_BFLY_RX2(v6, ve, vt, zeta, vl);
        RVV_BFLY_RX2(v7, vf, vt, zeta, vl);

        __riscv_vse32_v_i32m1(&a[i], v0, vl);
        __riscv_vse32_v_i32m1(&a[i + vl], v1, vl);
        __riscv_vse32_v_i32m1(&a[i + 2 * vl], v2, vl);
        __riscv_vse32_v_i32m1(&a[i + 3 * vl], v3, vl);
        __riscv_vse32_v_i32m1(&a[i + 4 * vl], v4, vl);
        __riscv_vse32_v_i32m1(&a[i + 5 * vl], v5, vl);
        __riscv_vse32_v_i32m1(&a[i + 6 * vl], v6, vl);
        __riscv_vse32_v_i32m1(&a[i + 7 * vl], v7, vl);
        __riscv_vse32_v_i32m1(&a[i + 8 * vl], v8, vl);
        __riscv_vse32_v_i32m1(&a[i + 9 * vl], v9, vl);
        __riscv_vse32_v_i32m1(&a[i + 10 * vl], va, vl);
        __riscv_vse32_v_i32m1(&a[i + 11 * vl], vb, vl);
        __riscv_vse32_v_i32m1(&a[i + 12 * vl], vc, vl);
        __riscv_vse32_v_i32m1(&a[i + 13 * vl], vd, vl);
        __riscv_vse32_v_i32m1(&a[i + 14 * vl], ve, vl);
        __riscv_vse32_v_i32m1(&a[i + 15 * vl], vf, vl);
    }

    zeta = -zetas[1];
    for (j = 0; j < MLDSA_PAR_N / 2; j += vl) {
        vint32m1_t vt;
        vint32m1_t v0 = __riscv_vle32_v_i32m1(&a[j], vl);
        vint32m1_t v1 =
            __riscv_vle32_v_i32m1(&a[j + MLDSA_PAR_N / 2], vl);

        RVV_BFLY_RX2(v0, v1, vt, zeta, vl);
        v0 = fq_redc2(__riscv_vwmul_vx_i64m2(v0, f, vl), vl);
        v1 = fq_redc2(__riscv_vwmul_vx_i64m2(v1, f, vl), vl);
        __riscv_vse32_v_i32m1(&a[j], v0, vl);
        __riscv_vse32_v_i32m1(&a[j + MLDSA_PAR_N / 2], v1, vl);
    }
}

#endif  //  MLDSA_RVV == 1
