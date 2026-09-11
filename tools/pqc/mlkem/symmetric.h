//  symmetric.h

#ifndef _SYMMETRIC_H_
#define _SYMMETRIC_H_

#include <stddef.h>
#include <stdint.h>
#include "mlkem_params.h"

#include "fips202.h"

typedef keccak_state xof_state;

void kyber_shake128_absorb(keccak_state *s, const uint8_t seed[MLKEM_SYM_SZ],
                           uint8_t x, uint8_t y);
void kyber_shake256_prf(uint8_t *out, size_t outlen,
                        const uint8_t key[MLKEM_SYM_SZ], uint8_t nonce);
void kyber_shake256_rkprf(const mlkem_param_t *par, uint8_t *out,
                          const uint8_t *key, const uint8_t *ct_in);

#define XOF_BLOCKBYTES SHAKE128_RATE

#define hash_h(OUT, IN, INBYTES) sha3_256(OUT, IN, INBYTES)
#define hash_g(OUT, IN, INBYTES) sha3_512(OUT, IN, INBYTES)
#define xof_absorb(STATE, SEED, X, Y) kyber_shake128_absorb(STATE, SEED, X, Y)
#define xof_squeezeblocks(OUT, OUTBLOCKS, STATE) \
    shake128_squeezeblocks(OUT, OUTBLOCKS, STATE)
#define prf(OUT, OUTBYTES, KEY, NONCE) \
    kyber_shake256_prf(OUT, OUTBYTES, KEY, NONCE)

#endif
