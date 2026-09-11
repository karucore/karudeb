//  mlkem_poly.h

#ifndef _MLKEM_POLY_H_
#define _MLKEM_POLY_H_

#include <stdint.h>
#include "mlkem_params.h"

/*
 * Elements of R_q = Z_q[X]/(X^n + 1). Represents polynomial
 * coeffs[0] + X*coeffs[1] + X^2*coeffs[2] + ... + X^{n-1}*coeffs[n-1]
 */
typedef struct {
    int16_t coeffs[MLKEM_PAR_N];
} poly_t;

void poly_compress(const mlkem_param_t *par, uint8_t *r, const poly_t *a);
void poly_decompress(const mlkem_param_t *par, poly_t *r, const uint8_t *a);
void poly_tobytes(uint8_t r[MLKEM_POLY_SZ], const poly_t *a);
void poly_frombytes(poly_t *r, const uint8_t a[MLKEM_POLY_SZ]);
void poly_frommsg(poly_t *r, const uint8_t msg[MLKEM_MSG_SZ]);
void poly_tomsg(uint8_t msg[MLKEM_MSG_SZ], const poly_t *r);
void poly_getnoise_eta1(const mlkem_param_t *par, poly_t *r,
                        const uint8_t seed[MLKEM_SYM_SZ], uint8_t nonce);
void poly_getnoise_eta2(poly_t *r, const uint8_t seed[MLKEM_SYM_SZ],
                        uint8_t nonce);

#endif
