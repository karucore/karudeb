#ifndef _POLYVEC_H_
#define _POLYVEC_H_

#include <stdint.h>
#include "mldsa_params.h"
#include "mldsa_poly.h"

/* Vectors of polynomials of length L */
typedef struct {
    poly_t vec[MLDSA_MAX_PAR_ELL];
} pvecl_t;

/* Vectors of polynomials of length K */
typedef struct {
    poly_t vec[MLDSA_MAX_PAR_K];
} pveck_t;

void polyvec_matrix_expand(const mldsa_param_t *par, pvecl_t mat[],
                           const uint8_t rho[MLDSA_SEED_SZ]);

void polyvec_matrix_pointwise_montgomery(const mldsa_param_t *par, pveck_t *t,
                                         const pvecl_t mat[],
                                         const pvecl_t *v);

void polyvecl_uniform_eta(const mldsa_param_t *par, pvecl_t *v,
                          const uint8_t seed[MLDSA_CRH_SZ], uint16_t nonce);

void polyvecl_uniform_gamma1(const mldsa_param_t *par, pvecl_t *v,
                             const uint8_t seed[MLDSA_CRH_SZ], uint16_t nonce);

void polyvecl_reduce(const mldsa_param_t *par, pvecl_t *v);

void polyvecl_add(const mldsa_param_t *par, pvecl_t *w, const pvecl_t *u,
                  const pvecl_t *v);

void polyvecl_ntt(const mldsa_param_t *par, pvecl_t *v);
void polyvecl_invntt_tomont(const mldsa_param_t *par, pvecl_t *v);
void polyvecl_pointwise_poly_montgomery(const mldsa_param_t *par, pvecl_t *r,
                                        const poly_t *a, const pvecl_t *v);
void polyvecl_pointwise_acc_montgomery(const mldsa_param_t *par, poly_t *w,
                                       const pvecl_t *u, const pvecl_t *v);
int polyvecl_chknorm(const mldsa_param_t *par, const pvecl_t *v, int32_t bb);

void polyveck_uniform_eta(const mldsa_param_t *par, pveck_t *v,
                          const uint8_t seed[MLDSA_CRH_SZ], uint16_t nonce);

void polyveck_reduce(const mldsa_param_t *par, pveck_t *v);
void polyveck_caddq(const mldsa_param_t *par, pveck_t *v);

void polyveck_add(const mldsa_param_t *par, pveck_t *w, const pveck_t *u,
                  const pveck_t *v);
void polyveck_sub(const mldsa_param_t *par, pveck_t *w, const pveck_t *u,
                  const pveck_t *v);
void polyveck_shiftl(const mldsa_param_t *par, pveck_t *v);

void polyveck_ntt(const mldsa_param_t *par, pveck_t *v);
void polyveck_invntt_tomont(const mldsa_param_t *par, pveck_t *v);
void polyveck_pointwise_poly_montgomery(const mldsa_param_t *par, pveck_t *r,
                                        const poly_t *a, const pveck_t *v);

int polyveck_chknorm(const mldsa_param_t *par, const pveck_t *v, int32_t B);

void polyveck_power2round(const mldsa_param_t *par, pveck_t *v1, pveck_t *v0,
                          const pveck_t *v);
void polyveck_decompose(const mldsa_param_t *par, pveck_t *v1, pveck_t *v0,
                        const pveck_t *v);
unsigned int polyveck_make_hint(const mldsa_param_t *par, pveck_t *h,
                                const pveck_t *v0, const pveck_t *v1);
void polyveck_use_hint(const mldsa_param_t *par, pveck_t *w, const pveck_t *v,
                       const pveck_t *h);

void polyveck_pack_w1(const mldsa_param_t *par, uint8_t *r, const pveck_t *w1);

#endif
