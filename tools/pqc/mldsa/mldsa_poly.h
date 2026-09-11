//  mldsa_poly.h

#ifndef _MLDSA_POLY_H_
#define _MLDSA_POLY_H_

#include <stdint.h>
#include "mldsa_params.h"

typedef struct {
    int32_t coeffs[MLDSA_PAR_N];
} poly_t;

void mldsa_poly_reduce(poly_t *a);
void poly_caddq(poly_t *a);

void mldsa_poly_add(poly_t *c, const poly_t *a, const poly_t *b);
void mldsa_poly_sub(poly_t *c, const poly_t *a, const poly_t *b);
void poly_shiftl(poly_t *a);
void mldsa_poly_ntt(poly_t *a);
void mldsa_poly_invntt_tomont(poly_t *a);
void poly_pointwise_montgomery(poly_t *c, const poly_t *a, const poly_t *b);
void poly_power2round(poly_t *a1, poly_t *a0, const poly_t *a);
void poly_decompose(const mldsa_param_t *par, poly_t *a1, poly_t *a0,
                    const poly_t *a);
unsigned int poly_make_hint(const mldsa_param_t *par, poly_t *h,
                            const poly_t *a0, const poly_t *a1);
void poly_use_hint(const mldsa_param_t *par, poly_t *b, const poly_t *a,
                   const poly_t *h);

int poly_chknorm(const poly_t *a, int32_t B);
void poly_uniform(poly_t *a, const uint8_t seed[MLDSA_SEED_SZ],
                  uint16_t nonce);
void poly_uniform_eta(const mldsa_param_t *par, poly_t *a,
                      const uint8_t seed[MLDSA_CRH_SZ], uint16_t nonce);
void poly_uniform_gamma1(const mldsa_param_t *par, poly_t *a,
                         const uint8_t seed[MLDSA_CRH_SZ], uint16_t nonce);
void poly_challenge(const mldsa_param_t *par, poly_t *c, const uint8_t *seed);

void polyeta_pack(const mldsa_param_t *par, uint8_t *r, const poly_t *a);
void polyeta_unpack(const mldsa_param_t *par, poly_t *r, const uint8_t *a);

void polyt1_pack(uint8_t *r, const poly_t *a);
void polyt1_unpack(poly_t *r, const uint8_t *a);

void polyt0_pack(uint8_t *r, const poly_t *a);
void polyt0_unpack(poly_t *r, const uint8_t *a);

void polyz_pack(const mldsa_param_t *par, uint8_t *r, const poly_t *a);
void polyz_unpack(const mldsa_param_t *par, poly_t *r, const uint8_t *a);

void polyw1_pack(const mldsa_param_t *par, uint8_t *r, const poly_t *a);

#endif
