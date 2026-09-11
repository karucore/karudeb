//  cbd_rvv.c
//  2026-05-12  Markku-Juhani O. Saarinen   <mjos@iki.fi>
//  === vector CBD2/CBD3 noise samplers for ML-KEM.

//  Layout reproduces cbd.c's per-byte / per-24-bit unpack exactly so
//  scalar and vector outputs are bit-identical for any given input.

#if MLKEM_RVV == 1

#include <stdint.h>
#include <riscv_vector.h>

#include "mlkem_params.h"

void cbd2_rvv(int16_t *r, const uint8_t *buf)
{
    const size_t vl = 16;   //  e8mf2 / e16m1 lanes

    for (unsigned i = 0; i < MLKEM_PAR_N / 32; i++) {
        vuint8mf2_t b = __riscv_vle8_v_u8mf2(buf + 16 * i, vl);

        //  d = (b & 0x55) + ((b>>1) & 0x55) — per-byte bit-pair sum
        vuint8mf2_t d = __riscv_vadd_vv_u8mf2(
            __riscv_vand_vx_u8mf2(b, 0x55, vl),
            __riscv_vand_vx_u8mf2(__riscv_vsrl_vx_u8mf2(b, 1, vl), 0x55, vl),
            vl);

        vuint8mf2_t c0u = __riscv_vsub_vv_u8mf2(
            __riscv_vand_vx_u8mf2(d, 0x3, vl),
            __riscv_vand_vx_u8mf2(__riscv_vsrl_vx_u8mf2(d, 2, vl), 0x3, vl), vl);
        vuint8mf2_t c1u = __riscv_vsub_vv_u8mf2(
            __riscv_vand_vx_u8mf2(__riscv_vsrl_vx_u8mf2(d, 4, vl), 0x3, vl),
            __riscv_vsrl_vx_u8mf2(d, 6, vl), vl);

        vint8mf2_t c0 = __riscv_vreinterpret_v_u8mf2_i8mf2(c0u);
        vint8mf2_t c1 = __riscv_vreinterpret_v_u8mf2_i8mf2(c1u);

        vint16m1_t c0w = __riscv_vsext_vf2_i16m1(c0, vl);
        vint16m1_t c1w = __riscv_vsext_vf2_i16m1(c1, vl);

        vint16m1x2_t pair = __riscv_vcreate_v_i16m1x2(c0w, c1w);
        __riscv_vsseg2e16_v_i16m1x2(r + 32 * i, pair, vl);
    }
}

void cbd3_rvv(int16_t *r, const uint8_t *buf)
{
    /* Scratch keeps storage at e32m1 (well-exercised by test_vlsseg).
     * The natural narrow path (e32m1 → e16mf2 via vncvt + vsse16 mf2
     * stride) hangs Marian's vstu; using a scratch + vector narrow
     * pass sidesteps it cleanly. (FIX) */

    static int32_t tmp[MLKEM_PAR_N] __attribute__((aligned(64)));

    const size_t   vl = 8;            /* e32m1 lanes */
    const uint32_t M  = 0x00249249u;  /* bits at positions 0,3,6,...,21 */

    for (unsigned i = 0; i < MLKEM_PAR_N / 32; i++) {
        vuint8mf4x3_t raw = __riscv_vlseg3e8_v_u8mf4x3(buf + 24 * i, vl);

        vuint32m1_t t = __riscv_vzext_vf4_u32m1(
            __riscv_vget_v_u8mf4x3_u8mf4(raw, 0), vl);
        t = __riscv_vor_vv_u32m1(t,
            __riscv_vsll_vx_u32m1(
                __riscv_vzext_vf4_u32m1(
                    __riscv_vget_v_u8mf4x3_u8mf4(raw, 1), vl), 8, vl), vl);
        t = __riscv_vor_vv_u32m1(t,
            __riscv_vsll_vx_u32m1(
                __riscv_vzext_vf4_u32m1(
                    __riscv_vget_v_u8mf4x3_u8mf4(raw, 2), vl), 16, vl), vl);

        vuint32m1_t d = __riscv_vand_vx_u32m1(t, M, vl);
        d = __riscv_vadd_vv_u32m1(d,
            __riscv_vand_vx_u32m1(__riscv_vsrl_vx_u32m1(t, 1, vl), M, vl), vl);
        d = __riscv_vadd_vv_u32m1(d,
            __riscv_vand_vx_u32m1(__riscv_vsrl_vx_u32m1(t, 2, vl), M, vl), vl);

        vint32m1_t c0 = __riscv_vreinterpret_v_u32m1_i32m1(__riscv_vsub_vv_u32m1(
            __riscv_vand_vx_u32m1(d, 0x7, vl),
            __riscv_vand_vx_u32m1(__riscv_vsrl_vx_u32m1(d, 3, vl), 0x7, vl), vl));
        vint32m1_t c1 = __riscv_vreinterpret_v_u32m1_i32m1(__riscv_vsub_vv_u32m1(
            __riscv_vand_vx_u32m1(__riscv_vsrl_vx_u32m1(d, 6, vl), 0x7, vl),
            __riscv_vand_vx_u32m1(__riscv_vsrl_vx_u32m1(d, 9, vl), 0x7, vl), vl));
        vint32m1_t c2 = __riscv_vreinterpret_v_u32m1_i32m1(__riscv_vsub_vv_u32m1(
            __riscv_vand_vx_u32m1(__riscv_vsrl_vx_u32m1(d, 12, vl), 0x7, vl),
            __riscv_vand_vx_u32m1(__riscv_vsrl_vx_u32m1(d, 15, vl), 0x7, vl), vl));
        vint32m1_t c3 = __riscv_vreinterpret_v_u32m1_i32m1(__riscv_vsub_vv_u32m1(
            __riscv_vand_vx_u32m1(__riscv_vsrl_vx_u32m1(d, 18, vl), 0x7, vl),
            __riscv_vsrl_vx_u32m1(d, 21, vl), vl));

        int32_t *base = tmp + 32 * i;
        __riscv_vsse32_v_i32m1(base + 0, 4 * sizeof(int32_t), c0, vl);
        __riscv_vsse32_v_i32m1(base + 1, 4 * sizeof(int32_t), c1, vl);
        __riscv_vsse32_v_i32m1(base + 2, 4 * sizeof(int32_t), c2, vl);
        __riscv_vsse32_v_i32m1(base + 3, 4 * sizeof(int32_t), c3, vl);
    }

    //  Vector i32 → i16 narrow at e32m2 → e16m1 (16 lanes/iter)
    for (unsigned j = 0; j < MLKEM_PAR_N; j += 16) {
        vint32m2_t v32 = __riscv_vle32_v_i32m2(&tmp[j], 16);
        vint16m1_t v16 = __riscv_vncvt_x_x_w_i16m1(v32, 16);
        __riscv_vse16_v_i16m1(&r[j], v16, 16);
    }
}

#endif  //  MLKEM_RVV == 1
