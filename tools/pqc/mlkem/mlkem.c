//  mlkem.c

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "mlkem.h"
#include "mlkem_kpke.h"
#include "verify.h"
#include "symmetric.h"

//  parameter sets

const mlkem_param_t mlkem_512 = {.name = "ML-KEM-512",
                                 .level = 1,
                                 .k = 2,
                                 .eta1 = 3,
                                 .du = 10,
                                 .dv = 4,
                                 .ek_sz = 800,
                                 .dk_sz = 1632,
                                 .ct_sz = 768};

const mlkem_param_t mlkem_768 = {.name = "ML-KEM-768",
                                 .level = 3,
                                 .k = 3,
                                 .eta1 = 2,
                                 .du = 10,
                                 .dv = 4,
                                 .ek_sz = 1184,
                                 .dk_sz = 2400,
                                 .ct_sz = 1088};

const mlkem_param_t mlkem_1024 = {.name = "ML-KEM-1024",
                                  .level = 5,
                                  .k = 4,
                                  .eta1 = 2,
                                  .du = 11,
                                  .dv = 5,
                                  .ek_sz = 1568,
                                  .dk_sz = 3168,
                                  .ct_sz = 1568};

const mlkem_param_t *mlkem_par[MLKEM_PARAMS] = {
    &mlkem_512,
    &mlkem_768,
    &mlkem_1024,
};

//  Generates public and private key for CCA-secure KEM

int mlkem_keygen_internal(const mlkem_param_t *par, uint8_t *ek, uint8_t *dk,
                          const uint8_t *d, const uint8_t *z)
{
    kpke_keygen(par, ek, dk, d);
    memcpy(dk + (par->k * MLKEM_POLY_SZ), ek, par->ek_sz);
    hash_h(dk + par->dk_sz - 2 * MLKEM_SYM_SZ, ek, par->ek_sz);
    /* Value z for pseudo-random output on reject */
    memcpy(dk + par->dk_sz - MLKEM_SYM_SZ, z, MLKEM_SYM_SZ);
    return 0;
}

//  Generates cipher text and shared secret for given public key

int mlkem_encaps_internal(const mlkem_param_t *par, uint8_t *kk, uint8_t *ct,
                          const uint8_t *ek, const uint8_t *m)
{
    uint8_t buf[2 * MLKEM_SYM_SZ];
    /* Will contain key, coins */
    uint8_t kr[2 * MLKEM_SYM_SZ];

    memcpy(buf, m, MLKEM_SYM_SZ);

    /* Multitarget countermeasure for coins + contributory KEM */
    hash_h(buf + MLKEM_SYM_SZ, ek, par->ek_sz);
    hash_g(kr, buf, 2 * MLKEM_SYM_SZ);

    /* coins are in kr+MLKEM_SYM_SZ */
    kpke_encrypt(par, ct, ek, buf, kr + MLKEM_SYM_SZ);

    memcpy(kk, kr, MLKEM_SYM_SZ);
    return 0;
}

//  Generates shared secret for given ciphertext and private key

int mlkem_decaps_internal(const mlkem_param_t *par, uint8_t *kp,
                          const uint8_t *dk, const uint8_t *ct)
{
    int fail;
    uint8_t buf[2 * MLKEM_SYM_SZ];
    /* Will contain key, coins */
    uint8_t kr[2 * MLKEM_SYM_SZ];
    uint8_t cmp[MLKEM_MAX_CT_SZ + MLKEM_SYM_SZ];
    const uint8_t *pk = dk + (par->k * MLKEM_POLY_SZ);

    kpke_decrypt(par, buf, dk, ct);

    /* Multitarget countermeasure for coins + contributory KEM */
    memcpy(buf + MLKEM_SYM_SZ, dk + par->dk_sz - 2 * MLKEM_SYM_SZ,
           MLKEM_SYM_SZ);
    hash_g(kr, buf, 2 * MLKEM_SYM_SZ);

    /* coins are in kr+MLKEM_SYM_SZ */
    kpke_encrypt(par, cmp, pk, buf, kr + MLKEM_SYM_SZ);

    fail = verify(ct, cmp, par->ct_sz);

    /* Compute rejection key */
    kyber_shake256_rkprf(par, kp, dk + par->dk_sz - MLKEM_SYM_SZ, ct);

    /* Copy true key to return buffer if fail is false */
    cmov(kp, kr, MLKEM_SYM_SZ, !fail);

    return 0;
}
