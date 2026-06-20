//  mlkem_kpke.c

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "mlkem_params.h"
#include "mlkem_kpke.h"
#include "mlkem_poly.h"
#include "mlkem_ntt.h"
#include "polyvec.h"
#include "symmetric.h"

//  Serialize the public key as concatenation of the
//  serialized vector of polynomials ek
//  and the public seed used to generate the matrix A.

static void pack_ek(const mlkem_param_t *par, uint8_t *r, pvec_t *ek,
                    const uint8_t seed[MLKEM_SYM_SZ])
{
    polyvec_tobytes(par, r, ek);
    memcpy(r + (par->k * MLKEM_POLY_SZ), seed, MLKEM_SYM_SZ);
}

//  De-serialize public key from a byte array; approximate inverse of pack_ek

static void unpack_ek(const mlkem_param_t *par, pvec_t *ek,
                      uint8_t seed[MLKEM_SYM_SZ], const uint8_t *packedek)
{
    polyvec_frombytes(par, ek, packedek);
    memcpy(seed, packedek + (par->k * MLKEM_POLY_SZ), MLKEM_SYM_SZ);
}

//  Serialize the secret key

static void pack_dk(const mlkem_param_t *par, uint8_t *r, pvec_t *dk)
{
    polyvec_tobytes(par, r, dk);
}

//  De-serialize the secret key; inverse of pack_dk

static void unpack_dk(const mlkem_param_t *par, pvec_t *dk,
                      const uint8_t *packeddk)
{
    polyvec_frombytes(par, dk, packeddk);
}

//  Serialize the ciphertext as concatenation of the compressed and
//  serialized vector of polynomials b and the compressed and serialized
//  polynomial v

static void pack_ciphertext(const mlkem_param_t *par, uint8_t *r, pvec_t *b,
                            poly_t *v)
{
    polyvec_compress(par, r, b);
    poly_compress(par, r + (par->k * par->du * (MLKEM_PAR_N / 8)), v);
}

//  De-serialize and decompress ciphertext from a byte array;
//  approximate inverse of pack_ciphertext

static void unpack_ciphertext(const mlkem_param_t *par, pvec_t *b, poly_t *v,
                              const uint8_t *c)
{
    polyvec_decompress(par, b, c);
    poly_decompress(par, v, c + (par->k * par->du * (MLKEM_PAR_N / 8)));
}

//  Run rejection sampling on uniform random bytes to generate
//  uniform random integers mod q

#if MLKEM_RVV == 1

//  prototype -- in rvv_poly.c
unsigned int mlkem_rej_uniform(int16_t *r, unsigned int len, const uint8_t *buf,
                         unsigned int buflen);

#else

static unsigned int mlkem_rej_uniform(int16_t *r, unsigned int len,
                                const uint8_t *buf, unsigned int buflen)
{
    unsigned int ctr, pos;
    uint16_t val0, val1;

    ctr = pos = 0;
    while (ctr < len && pos + 3 <= buflen) {
        val0 = ((buf[pos + 0] >> 0) | ((uint16_t) buf[pos + 1] << 8)) & 0xFFF;
        val1 = ((buf[pos + 1] >> 4) | ((uint16_t) buf[pos + 2] << 4)) & 0xFFF;
        pos += 3;

        if (val0 < MLKEM_PAR_Q) {
            r[ctr++] = val0;
        }
        if (ctr < len && val1 < MLKEM_PAR_Q) {
            r[ctr++] = val1;
        }
    }

    return ctr;
}
#endif

//  Deterministically generate matrix A (or the transpose of A) from a seed.
//  Entries of the matrix are polynomials that look uniformly random.
//  Performs rejection sampling on output of a XOF.

#if (XOF_BLOCKBYTES % 3)
#error \
    "Implementation of gen_matrix assumes that XOF_BLOCKBYTES is a multiple of 3"
#endif

#define GEN_MATRIX_NBLOCKS                                       \
    ((12 * MLKEM_PAR_N / 8 * (1 << 12) / MLKEM_PAR_Q + XOF_BLOCKBYTES) / \
     XOF_BLOCKBYTES)

static void gen_matrix(const mlkem_param_t *par, pvec_t *a,
                       const uint8_t seed[MLKEM_SYM_SZ], int transposed)
{
    unsigned int ctr, i, j;
    unsigned int buflen;
    uint8_t buf[GEN_MATRIX_NBLOCKS * XOF_BLOCKBYTES];
    xof_state state;

    for (i = 0; i < par->k; i++) {
        for (j = 0; j < par->k; j++) {
            if (transposed) {
                xof_absorb(&state, seed, i, j);
            } else {
                xof_absorb(&state, seed, j, i);
            }
            xof_squeezeblocks(buf, GEN_MATRIX_NBLOCKS, &state);
            buflen = GEN_MATRIX_NBLOCKS * XOF_BLOCKBYTES;
            ctr = mlkem_rej_uniform(a[i].vec[j].coeffs, MLKEM_PAR_N, buf, buflen);

            while (ctr < MLKEM_PAR_N) {
                xof_squeezeblocks(buf, 1, &state);
                buflen = XOF_BLOCKBYTES;
                ctr += mlkem_rej_uniform(a[i].vec[j].coeffs + ctr, MLKEM_PAR_N - ctr,
                                   buf, buflen);
            }
        }
    }
}

//  Uses randomness to generate an encryption key and a corresponding
//  decryption key.

void kpke_keygen(const mlkem_param_t *par,
                 uint8_t *ek, uint8_t *dk,
                 const uint8_t d[MLKEM_SYM_SZ])
{
    unsigned int i;
    uint8_t buf[2 * MLKEM_SYM_SZ];
    const uint8_t *publicseed = buf;
    const uint8_t *noiseseed = buf + MLKEM_SYM_SZ;
    uint8_t nonce = 0;
    pvec_t a[MLKEM_MAX_PAR_K], e, ekpv, dkpv;

    memcpy(buf, d, MLKEM_SYM_SZ);
    buf[MLKEM_SYM_SZ] = par->k;
    hash_g(buf, buf, MLKEM_SYM_SZ + 1);

    gen_matrix(par, a, publicseed, 0);

    for (i = 0; i < par->k; i++) {
        poly_getnoise_eta1(par, &dkpv.vec[i], noiseseed, nonce++);
    }
    for (i = 0; i < par->k; i++) {
        poly_getnoise_eta1(par, &e.vec[i], noiseseed, nonce++);
    }

    polyvec_ntt(par, &dkpv);
    polyvec_ntt(par, &e);

    // matrix-vector multiplication
    for (i = 0; i < par->k; i++) {
        polyvec_basemul_acc_montgomery(par, &ekpv.vec[i], &a[i], &dkpv);
        poly_tomont(&ekpv.vec[i]);
    }

    polyvec_add(par, &ekpv, &ekpv, &e);
    polyvec_reduce(par, &ekpv);

    pack_dk(par, dk, &dkpv);
    pack_ek(par, ek, &ekpv, publicseed);
}

//  Encryption function of the CPA-secure public-key encryption scheme
//  underlying Kyber.

void kpke_encrypt(const mlkem_param_t *par,
                  uint8_t *c, const uint8_t *ek,
                  const uint8_t m[MLKEM_MSG_SZ],
                  const uint8_t r[MLKEM_SYM_SZ])
{
    unsigned int i;
    uint8_t seed[MLKEM_SYM_SZ];
    uint8_t nonce = 0;
    pvec_t sp, ekpv, ep, at[MLKEM_MAX_PAR_K], b;
    poly_t v, k, epp;

    unpack_ek(par, &ekpv, seed, ek);
    poly_frommsg(&k, m);
    gen_matrix(par, at, seed, 1);

    for (i = 0; i < par->k; i++) {
        poly_getnoise_eta1(par, sp.vec + i, r, nonce++);
    }
    for (i = 0; i < par->k; i++) {
        poly_getnoise_eta2(ep.vec + i, r, nonce++);
    }
    poly_getnoise_eta2(&epp, r, nonce++);

    polyvec_ntt(par, &sp);

    // matrix-vector multiplication
    for (i = 0; i < par->k; i++) {
        polyvec_basemul_acc_montgomery(par, &b.vec[i], &at[i], &sp);
    }
    polyvec_basemul_acc_montgomery(par, &v, &ekpv, &sp);

    polyvec_invntt_tomont(par, &b);
    mlkem_poly_invntt_tomont(&v);

    polyvec_add(par, &b, &b, &ep);
    mlkem_poly_add(&v, &v, &epp);
    mlkem_poly_add(&v, &v, &k);
    polyvec_reduce(par, &b);
    mlkem_poly_reduce(&v);

    pack_ciphertext(par, c, &b, &v);
}

//  Uses the decryption key to decrypt a ciphertext.

void kpke_decrypt(const mlkem_param_t *par, uint8_t m[MLKEM_MSG_SZ],
                  const uint8_t *dk, const uint8_t *c)
{
    pvec_t b, dkpv;
    poly_t v, mp;

    unpack_ciphertext(par, &b, &v, c);
    unpack_dk(par, &dkpv, dk);

    polyvec_ntt(par, &b);
    polyvec_basemul_acc_montgomery(par, &mp, &dkpv, &b);
    mlkem_poly_invntt_tomont(&mp);

    mlkem_poly_sub(&mp, &v, &mp);
    mlkem_poly_reduce(&mp);

    poly_tomsg(m, &mp);
}
