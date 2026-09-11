//  polyvec.c

#include <stdint.h>
#include "mldsa_params.h"
#include "polyvec.h"
#include "mldsa_poly.h"

//  Implementation of ExpandA. Generates matrix A with uniformly
//  random coefficients a_{i,j} by performing rejection
//  sampling on the output stream of SHAKE128(rho|j|i)

void polyvec_matrix_expand(const mldsa_param_t *par, pvecl_t mat[],
                           const uint8_t rho[MLDSA_SEED_SZ])
{
    unsigned int i, j;

    for (i = 0; i < par->k; i++) {
        for (j = 0; j < par->ell; j++) {
            poly_uniform(&mat[i].vec[j], rho, (i << 8) + j);
        }
    }
}

void polyvec_matrix_pointwise_montgomery(const mldsa_param_t *par, pveck_t *t,
                                         const pvecl_t mat[], const pvecl_t *v)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        polyvecl_pointwise_acc_montgomery(par, &t->vec[i], &mat[i], v);
    }
}

void polyvecl_uniform_eta(const mldsa_param_t *par, pvecl_t *v,
                          const uint8_t seed[MLDSA_CRH_SZ], uint16_t nonce)
{
    unsigned int i;

    for (i = 0; i < par->ell; i++) {
        poly_uniform_eta(par, &v->vec[i], seed, nonce++);
    }
}

void polyvecl_uniform_gamma1(const mldsa_param_t *par, pvecl_t *v,
                             const uint8_t seed[MLDSA_CRH_SZ], uint16_t nonce)
{
    unsigned int i;

    for (i = 0; i < par->ell; i++) {
        poly_uniform_gamma1(par, &v->vec[i], seed, par->ell * nonce + i);
    }
}

void polyvecl_reduce(const mldsa_param_t *par, pvecl_t *v)
{
    unsigned int i;

    for (i = 0; i < par->ell; i++) {
        mldsa_poly_reduce(&v->vec[i]);
    }
}

//  Add vectors of polynomials of length L.
//  No modular reduction is performed.

void polyvecl_add(const mldsa_param_t *par, pvecl_t *w, const pvecl_t *u,
                  const pvecl_t *v)
{
    unsigned int i;

    for (i = 0; i < par->ell; i++) {
        mldsa_poly_add(&w->vec[i], &u->vec[i], &v->vec[i]);
    }
}

//  Forward NTT of all polynomials in vector of length L. Output
//  coefficients can be up to 16*Q larger than input coefficients.

void polyvecl_ntt(const mldsa_param_t *par, pvecl_t *v)
{
    unsigned int i;

    for (i = 0; i < par->ell; i++) {
        mldsa_poly_ntt(&v->vec[i]);
    }
}

void polyvecl_invntt_tomont(const mldsa_param_t *par, pvecl_t *v)
{
    unsigned int i;

    for (i = 0; i < par->ell; i++) {
        mldsa_poly_invntt_tomont(&v->vec[i]);
    }
}

void polyvecl_pointwise_poly_montgomery(const mldsa_param_t *par, pvecl_t *r,
                                        const poly_t *a, const pvecl_t *v)
{
    unsigned int i;

    for (i = 0; i < par->ell; i++) {
        poly_pointwise_montgomery(&r->vec[i], a, &v->vec[i]);
    }
}

//  Pointwise multiply vectors of polynomials of length L, multiply
//  resulting vector by 2^{-32} and add (accumulate) polynomials
//  in it. Input/output vectors are in NTT domain representation.

void polyvecl_pointwise_acc_montgomery(const mldsa_param_t *par, poly_t *w,
                                       const pvecl_t *u, const pvecl_t *v)
{
    unsigned int i;
    poly_t t;

    poly_pointwise_montgomery(w, &u->vec[0], &v->vec[0]);
    for (i = 1; i < par->ell; i++) {
        poly_pointwise_montgomery(&t, &u->vec[i], &v->vec[i]);
        mldsa_poly_add(w, w, &t);
    }
}

//  Check infinity norm of polynomials in vector of length L.
//  Assumes input pvecl_t to be reduced by polyvecl_reduce().

int polyvecl_chknorm(const mldsa_param_t *par, const pvecl_t *v, int32_t bound)
{
    unsigned int i;

    for (i = 0; i < par->ell; i++) {
        if (poly_chknorm(&v->vec[i], bound)) {
            return 1;
        }
    }

    return 0;
}

void polyveck_uniform_eta(const mldsa_param_t *par, pveck_t *v,
                          const uint8_t seed[MLDSA_CRH_SZ], uint16_t nonce)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        poly_uniform_eta(par, &v->vec[i], seed, nonce++);
    }
}

//  Reduce coefficients of polynomials in vector of length K
//  to representatives in [-6283008,6283008].

void polyveck_reduce(const mldsa_param_t *par, pveck_t *v)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        mldsa_poly_reduce(&v->vec[i]);
    }
}

//  For all coefficients of polynomials in vector of length K
//  add Q if coefficient is negative.

void polyveck_caddq(const mldsa_param_t *par, pveck_t *v)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        poly_caddq(&v->vec[i]);
    }
}

//  Add vectors of polynomials of length K.
//  No modular reduction is performed.

void polyveck_add(const mldsa_param_t *par, pveck_t *w, const pveck_t *u,
                  const pveck_t *v)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        mldsa_poly_add(&w->vec[i], &u->vec[i], &v->vec[i]);
    }
}

//  Subtract vectors of polynomials of length K.
//  No modular reduction is performed.

void polyveck_sub(const mldsa_param_t *par, pveck_t *w, const pveck_t *u,
                  const pveck_t *v)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        mldsa_poly_sub(&w->vec[i], &u->vec[i], &v->vec[i]);
    }
}

//  Multiply vector of polynomials of Length K by 2^D without
//  modular reduction. Assumes input coefficients to be less than 2^{31-D}.

void polyveck_shiftl(const mldsa_param_t *par, pveck_t *v)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        poly_shiftl(&v->vec[i]);
    }
}

//  Forward NTT of all polynomials in vector of length K. Output
//  coefficients can be up to 16*Q larger than input coefficients.

void polyveck_ntt(const mldsa_param_t *par, pveck_t *v)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        mldsa_poly_ntt(&v->vec[i]);
    }
}

//  Inverse NTT and multiplication by 2^{32} of polynomials in vector of
//  length K. Input coefficients need to be less than 2*Q.

void polyveck_invntt_tomont(const mldsa_param_t *par, pveck_t *v)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        mldsa_poly_invntt_tomont(&v->vec[i]);
    }
}

void polyveck_pointwise_poly_montgomery(const mldsa_param_t *par, pveck_t *r,
                                        const poly_t *a, const pveck_t *v)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        poly_pointwise_montgomery(&r->vec[i], a, &v->vec[i]);
    }
}

//  Check infinity norm of polynomials in vector of length K.
//  Assumes input pveck_t to be reduced by polyveck_reduce().

int polyveck_chknorm(const mldsa_param_t *par, const pveck_t *v, int32_t bound)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        if (poly_chknorm(&v->vec[i], bound)) {
            return 1;
        }
    }
    return 0;
}

//  For all coefficients a of polynomials in vector of length K,
//  compute a0, a1 such that a mod^+ Q = a1*2^D + a0
//  with -2^{D-1} < a0 <= 2^{D-1}. Assumes coefficients to be
//  standard representatives.

void polyveck_power2round(const mldsa_param_t *par, pveck_t *v1, pveck_t *v0,
                          const pveck_t *v)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        poly_power2round(&v1->vec[i], &v0->vec[i], &v->vec[i]);
    }
}

//  For all coefficients a of polynomials in vector of length K,
//  compute high and low bits a0, a1 such a mod^+ Q = a1*ALPHA + a0
//  with -ALPHA/2 < a0 <= ALPHA/2 except a1 = (Q-1)/ALPHA where we
//  set a1 = 0 and -ALPHA/2 <= a0 = a mod Q - Q < 0.

void polyveck_decompose(const mldsa_param_t *par, pveck_t *v1, pveck_t *v0,
                        const pveck_t *v)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        poly_decompose(par, &v1->vec[i], &v0->vec[i], &v->vec[i]);
    }
}

//  Compute hint vector

unsigned int polyveck_make_hint(const mldsa_param_t *par, pveck_t *h,
                                const pveck_t *v0, const pveck_t *v1)
{
    unsigned int i, s = 0;

    for (i = 0; i < par->k; i++) {
        s += poly_make_hint(par, &h->vec[i], &v0->vec[i], &v1->vec[i]);
    }

    return s;
}

//  Use hint vector to correct the high bits of input vector

void polyveck_use_hint(const mldsa_param_t *par, pveck_t *w, const pveck_t *u,
                       const pveck_t *h)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        poly_use_hint(par, &w->vec[i], &u->vec[i], &h->vec[i]);
    }
}

void polyveck_pack_w1(const mldsa_param_t *par, uint8_t *r, const pveck_t *w1)
{
    unsigned int i;

    for (i = 0; i < par->k; i++) {
        polyw1_pack(par, &r[i * par->w1p_sz], &w1->vec[i]);
    }
}
