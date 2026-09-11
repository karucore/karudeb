//  symmetric-shake.c

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "mlkem_params.h"
#include "symmetric.h"
#include "fips202.h"

/*************************************************
 * Name:        kyber_shake128_absorb
 *
 * Description: Absorb step of the SHAKE128 specialized for the Kyber context.
 *
 * Arguments:   - keccak_state *state: pointer to (uninitialized) output Keccak
 *state
 *              - const uint8_t *seed: pointer to MLKEM_SYM_SZ input to be
 *absorbed into state
 *              - uint8_t i: additional byte of input
 *              - uint8_t j: additional byte of input
 **************************************************/
void kyber_shake128_absorb(keccak_state *state,
                           const uint8_t seed[MLKEM_SYM_SZ], uint8_t x,
                           uint8_t y)
{
    uint8_t extseed[MLKEM_SYM_SZ + 2];

    memcpy(extseed, seed, MLKEM_SYM_SZ);
    extseed[MLKEM_SYM_SZ + 0] = x;
    extseed[MLKEM_SYM_SZ + 1] = y;

    shake128_absorb_once(state, extseed, sizeof(extseed));
}

/*************************************************
 * Name:        kyber_shake256_prf
 *
 * Description: Usage of SHAKE256 as a PRF, concatenates secret and public
 *input and then generates outlen bytes of SHAKE256 output
 *
 * Arguments:   - uint8_t *out: pointer to output
 *              - size_t outlen: number of requested output bytes
 *              - const uint8_t *key: pointer to the key (of length
 *MLKEM_SYM_SZ)
 *              - uint8_t nonce: single-byte nonce (public PRF input)
 **************************************************/
void kyber_shake256_prf(uint8_t *out, size_t outlen,
                        const uint8_t key[MLKEM_SYM_SZ], uint8_t nonce)
{
    uint8_t extkey[MLKEM_SYM_SZ + 1];

    memcpy(extkey, key, MLKEM_SYM_SZ);
    extkey[MLKEM_SYM_SZ] = nonce;

    shake256(out, outlen, extkey, sizeof(extkey));
}

/*************************************************
 * Name:        kyber_shake256_prf
 *
 * Description: Usage of SHAKE256 as a PRF, concatenates secret and public
 * input and then generates outlen bytes of SHAKE256 output
 *
 * Arguments:   - uint8_t *out: pointer to output
 *              - size_t outlen: number of requested output bytes
 *              - const uint8_t *key: pointer to the key (of length
 *MLKEM_SYM_SZ)
 *              - uint8_t nonce: single-byte nonce (public PRF input)
 **************************************************/
void kyber_shake256_rkprf(const mlkem_param_t *par, uint8_t *out,
                          const uint8_t *key, const uint8_t *ct_in)
{
    keccak_state s;

    shake256_init(&s);
    shake256_absorb(&s, key, MLKEM_SYM_SZ);
    shake256_absorb(&s, ct_in, par->ct_sz);
    shake256_finalize(&s);
    shake256_squeeze(out, MLKEM_SS_SZ, &s);
}
