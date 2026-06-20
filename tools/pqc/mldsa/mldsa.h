//  mldsa.h
//  === FIPS 204

#ifndef _MLDSA_H_
#define _MLDSA_H_

#include <stddef.h>
#include <stdint.h>
#include "mldsa_params.h"
#include "mldsa_poly.h"
#include "polyvec.h"

//  parameter sets
#define MLDSA_PARAMS 3
extern const mldsa_param_t mldsa_44;
extern const mldsa_param_t mldsa_65;
extern const mldsa_param_t mldsa_87;
extern const mldsa_param_t *mldsa_par[MLDSA_PARAMS];

//  external interface
int mldsa_keygen_internal(const mldsa_param_t *par, uint8_t *pk, uint8_t *sk,
                          const uint8_t *seed);

int mldsa_sign_internal(const mldsa_param_t *par, uint8_t *sig, size_t *sig_sz,
                        const uint8_t *sk, const uint8_t *m, size_t m_sz,
                        const uint8_t *rnd);

int mldsa_verify_internal(const mldsa_param_t *par, const uint8_t *pk,
                          const uint8_t *m, size_t m_sz, const uint8_t *sig,
                          size_t sig_sz);

#endif
