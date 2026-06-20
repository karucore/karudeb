//  polyvec.c

#include <stdint.h>
#include "polyvec.h"
#include "mlkem_ntt.h"

//  Compress and serialize vector of polynomials

void polyvec_compress(const mlkem_param_t *par, uint8_t *r, const pvec_t *a)
{
    unsigned int i, j, k;
    uint64_t d0;

    if (par->du == 11) {

        uint16_t t[8];
        for (i = 0; i < par->k; i++) {
            for (j = 0; j < MLKEM_PAR_N / 8; j++) {
                for (k = 0; k < 8; k++) {
                    t[k] = a->vec[i].coeffs[8 * j + k];
                    t[k] += ((int16_t) t[k] >> 15) & MLKEM_PAR_Q;
                    /*      t[k]  = ((((uint32_t)t[k] << 11) +
                     * MLKEM_PAR_Q/2)/MLKEM_PAR_Q) & 0x7ff; */
                    d0 = t[k];
                    d0 <<= 11;
                    d0 += 1664;
                    d0 *= 645084;
                    d0 >>= 31;
                    t[k] = d0 & 0x7ff;
                }

                r[0] = (t[0] >> 0);
                r[1] = (t[0] >> 8) | (t[1] << 3);
                r[2] = (t[1] >> 5) | (t[2] << 6);
                r[3] = (t[2] >> 2);
                r[4] = (t[2] >> 10) | (t[3] << 1);
                r[5] = (t[3] >> 7) | (t[4] << 4);
                r[6] = (t[4] >> 4) | (t[5] << 7);
                r[7] = (t[5] >> 1);
                r[8] = (t[5] >> 9) | (t[6] << 2);
                r[9] = (t[6] >> 6) | (t[7] << 5);
                r[10] = (t[7] >> 3);
                r += 11;
            }
        }

    } else {
        // if (par->du == 10) {

        uint16_t t[4];
        for (i = 0; i < par->k; i++) {
            for (j = 0; j < MLKEM_PAR_N / 4; j++) {
                for (k = 0; k < 4; k++) {
                    t[k] = a->vec[i].coeffs[4 * j + k];
                    t[k] += ((int16_t) t[k] >> 15) & MLKEM_PAR_Q;
                    /*      t[k]  = ((((uint32_t)t[k] << 10) + MLKEM_PAR_Q/2)/
                     * MLKEM_PAR_Q) & 0x3ff; */
                    d0 = t[k];
                    d0 <<= 10;
                    d0 += 1665;
                    d0 *= 1290167;
                    d0 >>= 32;
                    t[k] = d0 & 0x3ff;
                }

                r[0] = (t[0] >> 0);
                r[1] = (t[0] >> 8) | (t[1] << 2);
                r[2] = (t[1] >> 6) | (t[2] << 4);
                r[3] = (t[2] >> 4) | (t[3] << 6);
                r[4] = (t[3] >> 2);
                r += 5;
            }
        }
    }
}

//  De-serialize and decompress vector of polynomials; approximate
//  inverse of polyvec_compress

void polyvec_decompress(const mlkem_param_t *par, pvec_t *r, const uint8_t *a)
{
    unsigned int i, j, k;

    if (par->du == 11) {

        uint16_t t[8];
        for (i = 0; i < par->k; i++) {
            for (j = 0; j < MLKEM_PAR_N / 8; j++) {
                t[0] = (a[0] >> 0) | ((uint16_t) a[1] << 8);
                t[1] = (a[1] >> 3) | ((uint16_t) a[2] << 5);
                t[2] = (a[2] >> 6) | ((uint16_t) a[3] << 2) |
                       ((uint16_t) a[4] << 10);
                t[3] = (a[4] >> 1) | ((uint16_t) a[5] << 7);
                t[4] = (a[5] >> 4) | ((uint16_t) a[6] << 4);
                t[5] = (a[6] >> 7) | ((uint16_t) a[7] << 1) |
                       ((uint16_t) a[8] << 9);
                t[6] = (a[8] >> 2) | ((uint16_t) a[9] << 6);
                t[7] = (a[9] >> 5) | ((uint16_t) a[10] << 3);
                a += 11;

                for (k = 0; k < 8; k++)
                    r->vec[i].coeffs[8 * j + k] =
                        ((uint32_t) (t[k] & 0x7FF) * MLKEM_PAR_Q + 1024) >> 11;
            }
        }

    } else {
        // if (par->du == 10) {

        uint16_t t[4];
        for (i = 0; i < par->k; i++) {
            for (j = 0; j < MLKEM_PAR_N / 4; j++) {
                t[0] = (a[0] >> 0) | ((uint16_t) a[1] << 8);
                t[1] = (a[1] >> 2) | ((uint16_t) a[2] << 6);
                t[2] = (a[2] >> 4) | ((uint16_t) a[3] << 4);
                t[3] = (a[3] >> 6) | ((uint16_t) a[4] << 2);
                a += 5;

                for (k = 0; k < 4; k++)
                    r->vec[i].coeffs[4 * j + k] =
                        ((uint32_t) (t[k] & 0x3FF) * MLKEM_PAR_Q + 512) >> 10;
            }
        }
    }
}

//  Serialize vector of polynomials

void polyvec_tobytes(const mlkem_param_t *par, uint8_t *r, const pvec_t *a)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        poly_tobytes(r + i * MLKEM_POLY_SZ, &a->vec[i]);
    }
}

//  De-serialize vector of polynomials; inverse of polyvec_tobytes

void polyvec_frombytes(const mlkem_param_t *par, pvec_t *r, const uint8_t *a)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        poly_frombytes(&r->vec[i], a + i * MLKEM_POLY_SZ);
    }
}

//  Apply forward NTT to all elements of a vector of polynomials

void polyvec_ntt(const mlkem_param_t *par, pvec_t *r)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        mlkem_poly_ntt(&r->vec[i]);
    }
}

//  Apply inverse NTT to all elements of a vector of polynomials
//  and multiply by Montgomery factor 2^16

void polyvec_invntt_tomont(const mlkem_param_t *par, pvec_t *r)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        mlkem_poly_invntt_tomont(&r->vec[i]);
    }
}

//  Multiply elements of a and b in NTT domain, accumulate into r,
//  and multiply by 2^-16.

void polyvec_basemul_acc_montgomery(const mlkem_param_t *par, poly_t *r,
                                    const pvec_t *a, const pvec_t *b)
{
    unsigned int i;
    poly_t t;

    poly_basemul_montgomery(r, &a->vec[0], &b->vec[0]);
    for (i = 1; i < par->k; i++) {
        poly_basemul_montgomery(&t, &a->vec[i], &b->vec[i]);
        mlkem_poly_add(r, r, &t);
    }

    mlkem_poly_reduce(r);
}

//  Applies Barrett reduction to each coefficient of each element of a
//  vector of polynomials; for details of the Barrett reduction see comments
//  in reduce.c

void polyvec_reduce(const mlkem_param_t *par, pvec_t *r)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        mlkem_poly_reduce(&r->vec[i]);
    }
}

// Description: Add vectors of polynomials

void polyvec_add(const mlkem_param_t *par, pvec_t *r, const pvec_t *a,
                 const pvec_t *b)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        mlkem_poly_add(&r->vec[i], &a->vec[i], &b->vec[i]);
    }
}
