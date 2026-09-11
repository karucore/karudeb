//  polyvec.h

#ifndef _POLYVEC_H_
#define _POLYVEC_H_

#include <stdint.h>
#include "mlkem_params.h"
#include "mlkem_poly.h"

typedef struct {
    poly_t vec[MLKEM_MAX_PAR_K];
} pvec_t;

void polyvec_compress(const mlkem_param_t *par, uint8_t *r, const pvec_t *a);
void polyvec_decompress(const mlkem_param_t *par, pvec_t *r, const uint8_t *a);

void polyvec_tobytes(const mlkem_param_t *par, uint8_t *r, const pvec_t *a);
void polyvec_frombytes(const mlkem_param_t *par, pvec_t *r, const uint8_t *a);

void polyvec_ntt(const mlkem_param_t *par, pvec_t *r);
void polyvec_invntt_tomont(const mlkem_param_t *par, pvec_t *r);

void polyvec_basemul_acc_montgomery(const mlkem_param_t *par, poly_t *r,
                                    const pvec_t *a, const pvec_t *b);

void polyvec_reduce(const mlkem_param_t *par, pvec_t *r);
void polyvec_add(const mlkem_param_t *par, pvec_t *r, const pvec_t *a,
                 const pvec_t *b);

#endif
