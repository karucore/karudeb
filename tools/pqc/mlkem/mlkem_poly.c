//  mlkem_poly.c

#include <stdint.h>
#include "mlkem_params.h"
#include "mlkem_poly.h"
#include "mlkem_ntt.h"
#include "reduce.h"
#include "cbd.h"
#include "symmetric.h"
#include "verify.h"

//  Compression and subsequent serialization of a polynomial

void poly_compress(const mlkem_param_t *par, uint8_t *r, const poly_t *a)
{
    unsigned int i, j;
    int32_t u;
    uint32_t d0;
    uint8_t t[8];

    if (par->dv == 4) {
        for (i = 0; i < MLKEM_PAR_N / 8; i++) {
            for (j = 0; j < 8; j++) {
                // map to positive standard representatives
                u = a->coeffs[8 * i + j];
                u += (u >> 15) & MLKEM_PAR_Q;
                /*    t[j] = ((((uint16_t)u << 4) + MLKEM_PAR_Q/2)/MLKEM_PAR_Q) & 15;
                 */
                d0 = u << 4;
                d0 += 1665;
                d0 *= 80635;
                d0 >>= 28;
                t[j] = d0 & 0xf;
            }

            r[0] = t[0] | (t[1] << 4);
            r[1] = t[2] | (t[3] << 4);
            r[2] = t[4] | (t[5] << 4);
            r[3] = t[6] | (t[7] << 4);
            r += 4;
        }
    } else {
        //  if (par->dv == 5) {

        for (i = 0; i < MLKEM_PAR_N / 8; i++) {
            for (j = 0; j < 8; j++) {
                // map to positive standard representatives
                u = a->coeffs[8 * i + j];
                u += (u >> 15) & MLKEM_PAR_Q;
                /*    t[j] = ((((uint32_t)u << 5) + MLKEM_PAR_Q/2)/MLKEM_PAR_Q) & 31;
                 */
                d0 = u << 5;
                d0 += 1664;
                d0 *= 40318;
                d0 >>= 27;
                t[j] = d0 & 0x1f;
            }

            r[0] = (t[0] >> 0) | (t[1] << 5);
            r[1] = (t[1] >> 3) | (t[2] << 2) | (t[3] << 7);
            r[2] = (t[3] >> 1) | (t[4] << 4);
            r[3] = (t[4] >> 4) | (t[5] << 1) | (t[6] << 6);
            r[4] = (t[6] >> 2) | (t[7] << 3);
            r += 5;
        }
    }
}

//  De-serialization and subsequent decompression of a polynomial;
//  approximate inverse of poly_compress.

void poly_decompress(const mlkem_param_t *par, poly_t *r, const uint8_t *a)
{
    unsigned int i;

    if (par->dv == 4) {

        for (i = 0; i < MLKEM_PAR_N / 2; i++) {
            r->coeffs[2 * i + 0] =
                (((uint16_t) (a[0] & 15) * MLKEM_PAR_Q) + 8) >> 4;
            r->coeffs[2 * i + 1] =
                (((uint16_t) (a[0] >> 4) * MLKEM_PAR_Q) + 8) >> 4;
            a += 1;
        }
    } else {
        //  if (par->dv == 5) {

        unsigned int j;
        uint8_t t[8];
        for (i = 0; i < MLKEM_PAR_N / 8; i++) {
            t[0] = (a[0] >> 0);
            t[1] = (a[0] >> 5) | (a[1] << 3);
            t[2] = (a[1] >> 2);
            t[3] = (a[1] >> 7) | (a[2] << 1);
            t[4] = (a[2] >> 4) | (a[3] << 4);
            t[5] = (a[3] >> 1);
            t[6] = (a[3] >> 6) | (a[4] << 2);
            t[7] = (a[4] >> 3);
            a += 5;

            for (j = 0; j < 8; j++) {
                r->coeffs[8 * i + j] =
                    ((uint32_t) (t[j] & 31) * MLKEM_PAR_Q + 16) >> 5;
            }
        }
    }
}

//  Serialization of a polynomial

void poly_tobytes(uint8_t r[MLKEM_POLY_SZ], const poly_t *a)
{
    unsigned int i;
    uint16_t t0, t1;

    for (i = 0; i < MLKEM_PAR_N / 2; i++) {
        // map to positive standard representatives
        t0 = a->coeffs[2 * i];
        t0 += ((int16_t) t0 >> 15) & MLKEM_PAR_Q;
        t1 = a->coeffs[2 * i + 1];
        t1 += ((int16_t) t1 >> 15) & MLKEM_PAR_Q;
        r[3 * i + 0] = (t0 >> 0);
        r[3 * i + 1] = (t0 >> 8) | (t1 << 4);
        r[3 * i + 2] = (t1 >> 4);
    }
}

//  De-serialization of a polynomial; inverse of poly_tobytes

void poly_frombytes(poly_t *r, const uint8_t a[MLKEM_POLY_SZ])
{
    unsigned int i;

    for (i = 0; i < MLKEM_PAR_N / 2; i++) {
        r->coeffs[2 * i] =
            ((a[3 * i + 0] >> 0) | ((uint16_t) a[3 * i + 1] << 8)) & 0xFFF;
        r->coeffs[2 * i + 1] =
            ((a[3 * i + 1] >> 4) | ((uint16_t) a[3 * i + 2] << 4)) & 0xFFF;
    }
}

//  Convert 32-byte message to polynomial

void poly_frommsg(poly_t *r, const uint8_t msg[MLKEM_MSG_SZ])
{
    unsigned int i, j;

#if (MLKEM_MSG_SZ != MLKEM_PAR_N / 8)
#error "MLKEM_MSG_SZ must be equal to MLKEM_PAR_N/8 bytes!"
#endif

    for (i = 0; i < MLKEM_PAR_N / 8; i++) {
        for (j = 0; j < 8; j++) {
            r->coeffs[8 * i + j] = 0;
            cmov_int16(r->coeffs + 8 * i + j, ((MLKEM_PAR_Q + 1) / 2),
                       (msg[i] >> j) & 1);
        }
    }
}

//  Convert polynomial to 32-byte message

void poly_tomsg(uint8_t msg[MLKEM_MSG_SZ], const poly_t *a)
{
    unsigned int i, j;
    uint32_t t;

    for (i = 0; i < MLKEM_PAR_N / 8; i++) {
        msg[i] = 0;
        for (j = 0; j < 8; j++) {
            t = a->coeffs[8 * i + j];
            // t += ((int16_t)t >> 15) & MLKEM_PAR_Q;
            // t  = (((t << 1) + MLKEM_PAR_Q/2)/MLKEM_PAR_Q) & 1;
            t <<= 1;
            t += 1665;
            t *= 80635;
            t >>= 28;
            t &= 1;
            msg[i] |= t << j;
        }
    }
}

//  Sample a polynomial deterministically from a seed and a nonce,
//  with output polynomial close to centered binomial distribution
//  with parameter MLKEM_ETA1

void poly_getnoise_eta1(const mlkem_param_t *par, poly_t *r,
                        const uint8_t seed[MLKEM_SYM_SZ], uint8_t nonce)
{
    uint8_t buf[MLKEM_MAX_PAR_ETA1 * MLKEM_PAR_N / 4];

    prf(buf, par->eta1 * (MLKEM_PAR_N / 4), seed, nonce);
    poly_cbd_eta1(par, r, buf);
}

//  Sample a polynomial deterministically from a seed and a nonce,
//  with output polynomial close to centered binomial distribution
//  with parameter MLKEM_PAR_ETA2

void poly_getnoise_eta2(poly_t *r, const uint8_t seed[MLKEM_SYM_SZ],
                        uint8_t nonce)
{
    uint8_t buf[MLKEM_PAR_ETA2 * MLKEM_PAR_N / 4];
    prf(buf, sizeof(buf), seed, nonce);
    poly_cbd_eta2(r, buf);
}

