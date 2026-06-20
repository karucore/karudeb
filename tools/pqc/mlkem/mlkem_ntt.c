//  mlkem_ntt.c

#if MLKEM_RVV != 1

#include <stdint.h>
#include "mlkem_params.h"
#include "mlkem_ntt.h"
#include "reduce.h"

/* Code to generate zetas and zetas_inv used in the number-theoretic transform:

#define MLKEM_ROOT_OF_UNITY 17

static const uint8_t tree[128] = {
  0, 64, 32, 96, 16, 80, 48, 112, 8, 72, 40, 104, 24, 88, 56, 120,
  4, 68, 36, 100, 20, 84, 52, 116, 12, 76, 44, 108, 28, 92, 60, 124,
  2, 66, 34, 98, 18, 82, 50, 114, 10, 74, 42, 106, 26, 90, 58, 122,
  6, 70, 38, 102, 22, 86, 54, 118, 14, 78, 46, 110, 30, 94, 62, 126,
  1, 65, 33, 97, 17, 81, 49, 113, 9, 73, 41, 105, 25, 89, 57, 121,
  5, 69, 37, 101, 21, 85, 53, 117, 13, 77, 45, 109, 29, 93, 61, 125,
  3, 67, 35, 99, 19, 83, 51, 115, 11, 75, 43, 107, 27, 91, 59, 123,
  7, 71, 39, 103, 23, 87, 55, 119, 15, 79, 47, 111, 31, 95, 63, 127
};

void init_ntt() {
  unsigned int i;
  int16_t tmp[128];

  tmp[0] = MONT;
  for(i=1;i<128;i++)
    tmp[i] = fqmul(tmp[i-1],MONT*MLKEM_ROOT_OF_UNITY % MLKEM_PAR_Q);

  for(i=0;i<128;i++) {
    zetas[i] = tmp[tree[i]];
    if(zetas[i] > MLKEM_PAR_Q/2)
      zetas[i] -= MLKEM_PAR_Q;
    if(zetas[i] < -MLKEM_PAR_Q/2)
      zetas[i] += MLKEM_PAR_Q;
  }
}
*/

static const int16_t mlkem_zetas[128] = {
    -1044, -758,  -359,  -1517, 1493,  1422,  287,   202,  -171,  622,   1577,
    182,   962,   -1202, -1474, 1468,  573,   -1325, 264,  383,   -829,  1458,
    -1602, -130,  -681,  1017,  732,   608,   -1542, 411,  -205,  -1571, 1223,
    652,   -552,  1015,  -1293, 1491,  -282,  -1544, 516,  -8,    -320,  -666,
    -1618, -1162, 126,   1469,  -853,  -90,   -271,  830,  107,   -1421, -247,
    -951,  -398,  961,   -1508, -725,  448,   -1065, 677,  -1275, -1103, 430,
    555,   843,   -1251, 871,   1550,  105,   422,   587,  177,   -235,  -291,
    -460,  1574,  1653,  -246,  778,   1159,  -147,  -777, 1483,  -602,  1119,
    -1590, 644,   -872,  349,   418,   329,   -156,  -75,  817,   1097,  603,
    610,   1322,  -1285, -1465, 384,   -1215, -136,  1218, -1335, -874,  220,
    -1187, -1659, -1185, -1530, -1278, 794,   -1510, -854, -870,  478,   -108,
    -308,  996,   991,   958,   -1460, 1522,  1628};

//  Inplace number-theoretic transform (NTT) in Rq.
//  input is in standard order, output is in bitreversed order

static void mlkem_ntt(int16_t r[256])
{
    unsigned int len, start, j, k;
    int16_t t, zeta;

    k = 1;
    for (len = 128; len >= 2; len >>= 1) {
        for (start = 0; start < 256; start = j + len) {
            zeta = mlkem_zetas[k++];
            for (j = start; j < start + len; j++) {
                t = fqmul(zeta, r[j + len]);
                r[j + len] = r[j] - t;
                r[j] = r[j] + t;
            }
        }
    }
}

static void mlkem_invntt(int16_t r[256])
{
    unsigned int start, len, j, k;
    int16_t t, zeta;
    const int16_t f = 1441;  // mont^2/128

    k = 127;
    for (len = 2; len <= 128; len <<= 1) {
        for (start = 0; start < 256; start = j + len) {
            zeta = mlkem_zetas[k--];
            for (j = start; j < start + len; j++) {
                t = r[j];
                r[j] = barrett_reduce(t + r[j + len]);
                r[j + len] = r[j + len] - t;
                r[j + len] = fqmul(zeta, r[j + len]);
            }
        }
    }

    for (j = 0; j < 256; j++) {
        r[j] = fqmul(r[j], f);
    }
}

//  Computes negacyclic number-theoretic transform (NTT) of a polynomial in
//  place; inputs assumed to be in normal order, output in bitreversed order.

void mlkem_poly_ntt(poly_t *r)
{
    mlkem_ntt(r->coeffs);
    mlkem_poly_reduce(r);
}

//  Computes inverse of negacyclic number-theoretic transform (NTT)
//  of a polynomial in place; inputs assumed to be in bitreversed order,
//  output in normal order.

void mlkem_poly_invntt_tomont(poly_t *r)
{
    mlkem_invntt(r->coeffs);
}

//  Multiplication of two polynomials in NTT domain

void poly_basemul_montgomery(poly_t *r, const poly_t *a, const poly_t *b)
{
    unsigned int i;
    for (i = 0; i < MLKEM_PAR_N / 4; i++) {
        basemul(&r->coeffs[4 * i], &a->coeffs[4 * i], &b->coeffs[4 * i],
                mlkem_zetas[64 + i]);
        basemul(&r->coeffs[4 * i + 2], &a->coeffs[4 * i + 2],
                &b->coeffs[4 * i + 2], -mlkem_zetas[64 + i]);
    }
}

//  Inplace conversion of all coefficients of a polynomial
//  from normal domain to Montgomery domain

void poly_tomont(poly_t *r)
{
    unsigned int i;
    const int16_t f = (1ULL << 32) % MLKEM_PAR_Q;

    for (i = 0; i < MLKEM_PAR_N; i++) {
        r->coeffs[i] = montgomery_reduce((int32_t) r->coeffs[i] * f);
    }
}

//  Applies Barrett reduction to all coefficients of a polynomial
//  for details of the Barrett reduction see comments in reduce.c

void mlkem_poly_reduce(poly_t *r)
{
    unsigned int i;

    for (i = 0; i < MLKEM_PAR_N; i++) {
        r->coeffs[i] = barrett_reduce(r->coeffs[i]);
    }
}

//  Add two polynomials; no modular reduction is performed

void mlkem_poly_add(poly_t *r, const poly_t *a, const poly_t *b)
{
    unsigned int i;

    for (i = 0; i < MLKEM_PAR_N; i++) {
        r->coeffs[i] = a->coeffs[i] + b->coeffs[i];
    }
}

//  Subtract two polynomials; no modular reduction is performed

void mlkem_poly_sub(poly_t *r, const poly_t *a, const poly_t *b)
{
    unsigned int i;

    for (i = 0; i < MLKEM_PAR_N; i++) {
        r->coeffs[i] = a->coeffs[i] - b->coeffs[i];
    }
}

#endif
