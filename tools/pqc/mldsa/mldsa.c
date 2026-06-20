//  mldsa.c

#include <stdint.h>
#include <string.h>
#include "mldsa_params.h"
#include "mldsa.h"
#include "mldsa_poly.h"
#include "polyvec.h"
#include "symmetric.h"
#include "fips202.h"

//  parameter sets

const mldsa_param_t mldsa_44 = {.name = "ML-DSA-44",
                                .level = 2,
                                .k = 4,
                                .ell = 4,
                                .eta = 2,
                                .tau = 39,
                                .beta = 78,
                                .gamma1 = (1 << 17),
                                .gamma2 = ((MLDSA_PAR_Q - 1) / 88),
                                .omega = 80,
                                .pzp_sz = 576,
                                .w1p_sz = 192,
                                .eta_sz = 96,
                                .cp_sz = 32,
                                .sk_sz = 2560,
                                .pk_sz = 1312,
                                .sig_sz = 2420};

const mldsa_param_t mldsa_65 = {.name = "ML-DSA-65",
                                .level = 3,
                                .k = 6,
                                .ell = 5,
                                .eta = 4,
                                .tau = 49,
                                .beta = 196,
                                .gamma1 = (1 << 19),
                                .gamma2 = ((MLDSA_PAR_Q - 1) / 32),
                                .omega = 55,
                                .pzp_sz = 640,
                                .w1p_sz = 128,
                                .eta_sz = 128,
                                .cp_sz = 48,
                                .sk_sz = 4032,
                                .pk_sz = 1952,
                                .sig_sz = 3309};

const mldsa_param_t mldsa_87 = {.name = "ML-DSA-87",
                                .level = 5,
                                .k = 8,
                                .ell = 7,
                                .eta = 2,
                                .tau = 60,
                                .beta = 120,
                                .gamma1 = (1 << 19),
                                .gamma2 = ((MLDSA_PAR_Q - 1) / 32),
                                .omega = 75,
                                .pzp_sz = 640,
                                .w1p_sz = 128,
                                .eta_sz = 96,
                                .cp_sz = 64,
                                .sk_sz = 4896,
                                .pk_sz = 2592,
                                .sig_sz = 4627};

const mldsa_param_t *mldsa_par[MLDSA_PARAMS] = {
    &mldsa_44,
    &mldsa_65,
    &mldsa_87,
};

//  Bit-pack public key pk = (rho, t1).

static void pack_pk(const mldsa_param_t *par, uint8_t *pk,
                    const uint8_t rho[MLDSA_SEED_SZ], const pveck_t *t1)
{
    size_t i;

    for (i = 0; i < MLDSA_SEED_SZ; i++) {
        pk[i] = rho[i];
    }
    pk += MLDSA_SEED_SZ;

    for (i = 0; i < par->k; i++) {
        polyt1_pack(pk, &t1->vec[i]);
        pk += MLDSA_POLY_T1_SZ;
    }
}

//  Unpack public key pk = (rho, t1).

static void unpack_pk(const mldsa_param_t *par, uint8_t rho[MLDSA_SEED_SZ],
                      pveck_t *t1, const uint8_t *pk)
{
    size_t i;

    for (i = 0; i < MLDSA_SEED_SZ; i++) {
        rho[i] = pk[i];
    }
    pk += MLDSA_SEED_SZ;

    for (i = 0; i < par->k; i++) {
        polyt1_unpack(&t1->vec[i], pk);
        pk += MLDSA_POLY_T1_SZ;
    }
}

//  Bit-pack secret key sk = (rho, tr, key, t0, s1, s2).

static void pack_sk(const mldsa_param_t *par, uint8_t *sk,
                    const uint8_t rho[MLDSA_SEED_SZ],
                    const uint8_t tr[MLDSA_TR_SZ],
                    const uint8_t key[MLDSA_SEED_SZ], const pveck_t *t0,
                    const pvecl_t *s1, const pveck_t *s2)
{
    size_t i;

    for (i = 0; i < MLDSA_SEED_SZ; i++) {
        sk[i] = rho[i];
    }
    sk += MLDSA_SEED_SZ;

    for (i = 0; i < MLDSA_SEED_SZ; i++) {
        sk[i] = key[i];
    }
    sk += MLDSA_SEED_SZ;

    for (i = 0; i < MLDSA_TR_SZ; i++) {
        sk[i] = tr[i];
    }
    sk += MLDSA_TR_SZ;

    for (i = 0; i < par->ell; i++) {
        polyeta_pack(par, sk, &s1->vec[i]);
        sk += par->eta_sz;
    }

    for (i = 0; i < par->k; i++) {
        polyeta_pack(par, sk, &s2->vec[i]);
        sk += par->eta_sz;
    }

    for (i = 0; i < par->k; i++) {
        polyt0_pack(sk, &t0->vec[i]);
        sk += MLDSA_POLY_T0_SZ;
    }
}

//  Unpack secret key sk = (rho, tr, key, t0, s1, s2).

static void unpack_sk(const mldsa_param_t *par, uint8_t rho[MLDSA_SEED_SZ],
                      uint8_t tr[MLDSA_TR_SZ], uint8_t key[MLDSA_SEED_SZ],
                      pveck_t *t0, pvecl_t *s1, pveck_t *s2, const uint8_t *sk)
{
    size_t i;

    for (i = 0; i < MLDSA_SEED_SZ; i++) {
        rho[i] = sk[i];
    }
    sk += MLDSA_SEED_SZ;

    for (i = 0; i < MLDSA_SEED_SZ; i++) {
        key[i] = sk[i];
    }
    sk += MLDSA_SEED_SZ;

    for (i = 0; i < MLDSA_TR_SZ; i++) {
        tr[i] = sk[i];
    }
    sk += MLDSA_TR_SZ;

    for (i = 0; i < par->ell; i++) {
        polyeta_unpack(par, &s1->vec[i], sk);
        sk += par->eta_sz;
    }

    for (i = 0; i < par->k; i++) {
        polyeta_unpack(par, &s2->vec[i], sk);
        sk += par->eta_sz;
    }

    for (i = 0; i < par->k; i++) {
        polyt0_unpack(&t0->vec[i], sk);
        sk += MLDSA_POLY_T0_SZ;
    }
}

//  Bit-pack signature sig = (c, z, h).

static void pack_sig(const mldsa_param_t *par, uint8_t *sig, const uint8_t *c,
                     const pvecl_t *z, const pveck_t *h)
{
    size_t i, j, k;

    for (i = 0; i < par->cp_sz; i++) {
        sig[i] = c[i];
    }
    sig += par->cp_sz;

    for (i = 0; i < par->ell; i++) {
        polyz_pack(par, sig, &z->vec[i]);
        sig += par->pzp_sz;
    }

    /* Encode h */
    for (i = 0; i < par->omega + par->k; i++) {
        sig[i] = 0;
    }

    k = 0;
    for (i = 0; i < par->k; i++) {
        for (j = 0; j < MLDSA_PAR_N; j++) {
            if (h->vec[i].coeffs[j] != 0) {
                sig[k++] = j;
            }
        }
        sig[par->omega + i] = k;
    }
}

//  Unpack signature sig = (c, z, h).

static int unpack_sig(const mldsa_param_t *par, uint8_t *c, pvecl_t *z,
                      pveck_t *h, const uint8_t *sig)
{
    unsigned int i, j, k;

    for (i = 0; i < par->cp_sz; i++) {
        c[i] = sig[i];
    }
    sig += par->cp_sz;

    for (i = 0; i < par->ell; i++) {
        polyz_unpack(par, &z->vec[i], sig);
        sig += par->pzp_sz;
    }

    /* Decode h */
    k = 0;
    for (i = 0; i < par->k; i++) {
        for (j = 0; j < MLDSA_PAR_N; j++) {
            h->vec[i].coeffs[j] = 0;
        }
        if (sig[par->omega + i] < k || sig[par->omega + i] > par->omega) {
            return 1;
        }

        for (j = k; j < sig[par->omega + i]; j++) {
            /* Coefficients are ordered for strong unforgeability */
            if (j > k && sig[j] <= sig[j - 1]) {
                return 1;
            }
            h->vec[i].coeffs[sig[j]] = 1;
        }
        k = sig[par->omega + i];
    }

    /* Extra indices are zero for strong unforgeability */
    for (j = k; j < par->omega; j++)
        if (sig[j])
            return 1;

    return 0;
}

//  Generates a public-private key pair from a seed

#ifdef MLDSA_PROFILE
#include "../plat_local.h"
#include <stdio.h>
uint64_t mldsa_profile_phase[10];
const char *mldsa_profile_name[10] = {
    "shake_seed     ", "matrix_expand  ", "uniform_eta    ",
    "polyvecl_ntt   ", "matrix_pwise   ", "reduce_invntt  ",
    "add_caddq_p2r  ", "pack_pk        ", "shake_tr       ",
    "pack_sk        ",
};
#define TAP(idx) do { uint64_t _t = plat_get_instret(); \
    mldsa_profile_phase[idx] += _t - _tap; _tap = _t; } while (0)
#else
#define TAP(idx) (void)0
#endif

/* Task #69: per-step polynomial checksum trace for the sign rejection loop.
 * Localizes the residual -O3 divergence (Marian vs Spike, same ELF): run both,
 * diff the "TRACE ..." lines; the first differing line is the diverging step.
 * Gated on the first rejection iteration only (nonce<=1) to avoid spam from
 * Marian's over-retries. printf is the bench's HTIF-backed putchar printf,
 * present on both Marian and Spike bare-metal builds. */
#ifdef MLDSA_SIGN_TRACE
extern int printf_(const char *, ...);
static uint32_t mldsa_dbg_poly_cks(const poly_t *a) {
    uint32_t h = 2166136261u;
    for (int j = 0; j < MLDSA_PAR_N; j++) { h ^= (uint32_t)a->coeffs[j]; h *= 16777619u; }
    return h;
}
static void mldsa_dbg_vecl(const char *tag, const mldsa_param_t *par, const pvecl_t *v) {
    uint32_t h = 0;
    for (unsigned i = 0; i < par->ell; i++) h = (h * 1000003u) ^ mldsa_dbg_poly_cks(&v->vec[i]);
    printf_("  TRACE %-12s ell h=%08x\r\n", tag, (unsigned)h);
}
static void mldsa_dbg_veck(const char *tag, const mldsa_param_t *par, const pveck_t *v) {
    uint32_t h = 0;
    for (unsigned i = 0; i < par->k; i++) h = (h * 1000003u) ^ mldsa_dbg_poly_cks(&v->vec[i]);
    printf_("  TRACE %-12s k   h=%08x\r\n", tag, (unsigned)h);
}
/* Raw-coeff dump of a pveck (all k*256 coeffs) as C initializers, for
 * capturing a known input vector (e.g. the inverse-NTT input w1) to seed a
 * standalone repro. One value per line is verbose but trivially parseable. */
static void mldsa_dbg_veck_raw(const char *tag, const mldsa_param_t *par, const pveck_t *v) {
    printf_("  RAW %s BEGIN k=%u\r\n", tag, (unsigned)par->k);
    for (unsigned i = 0; i < par->k; i++)
        for (int j = 0; j < MLDSA_PAR_N; j++)
            printf_("%d\r\n", (int)v->vec[i].coeffs[j]);
    printf_("  RAW %s END\r\n", tag);
}
#define DBG_VECL(tag, v) do { if (nonce <= 1) mldsa_dbg_vecl((tag), par, (v)); } while (0)
#define DBG_VECK(tag, v) do { if (nonce <= 1) mldsa_dbg_veck((tag), par, (v)); } while (0)
#define DBG_POLY(tag, p) do { if (nonce <= 1) printf_("  TRACE %-12s pol h=%08x\r\n", (tag), (unsigned)mldsa_dbg_poly_cks(p)); } while (0)
#define DBG_VAL(tag, val) do { if (nonce <= 1) printf_("  TRACE %-12s = %d\r\n", (tag), (int)(val)); } while (0)
#ifdef MLDSA_SIGN_TRACE_RAW
#define DBG_VECK_RAW(tag, v) do { if (nonce <= 1) mldsa_dbg_veck_raw((tag), par, (v)); } while (0)
#else
#define DBG_VECK_RAW(tag, v) (void)0
#endif
#else
#define DBG_VECL(tag, v) (void)0
#define DBG_VECK(tag, v) (void)0
#define DBG_POLY(tag, p) (void)0
#define DBG_VAL(tag, val) (void)0
#define DBG_VECK_RAW(tag, v) (void)0
#endif

int mldsa_keygen_internal(const mldsa_param_t *par, uint8_t *pk, uint8_t *sk,
                          const uint8_t *seed)
{
    uint8_t seedbuf[2 * MLDSA_SEED_SZ + MLDSA_CRH_SZ];
    uint8_t tr[MLDSA_TR_SZ];
    const uint8_t *rho, *rhop, *key;
    pvecl_t mat[par->k];
    pvecl_t s1, s1hat;
    pveck_t s2, t1, t0;
#ifdef MLDSA_PROFILE
    uint64_t _tap = plat_get_instret();
#endif

    /* Get randomness for rho, rhop and key */
    memcpy(seedbuf, seed, MLDSA_SEED_SZ);
    seedbuf[MLDSA_SEED_SZ + 0] = par->k;
    seedbuf[MLDSA_SEED_SZ + 1] = par->ell;
    shake256(seedbuf, 2 * MLDSA_SEED_SZ + MLDSA_CRH_SZ, seedbuf,
             MLDSA_SEED_SZ + 2);
    rho = seedbuf;
    rhop = rho + MLDSA_SEED_SZ;
    key = rhop + MLDSA_CRH_SZ;
    TAP(0);

    /* Expand matrix */
    polyvec_matrix_expand(par, mat, rho);
    TAP(1);

    /* Sample short vectors s1 and s2 */
    polyvecl_uniform_eta(par, &s1, rhop, 0);
    polyveck_uniform_eta(par, &s2, rhop, par->ell);
    TAP(2);

    /* Matrix-vector multiplication */
    s1hat = s1;
    polyvecl_ntt(par, &s1hat);
    TAP(3);
    polyvec_matrix_pointwise_montgomery(par, &t1, mat, &s1hat);
    TAP(4);
    polyveck_reduce(par, &t1);
    polyveck_invntt_tomont(par, &t1);
    TAP(5);

    /* Add error vector s2 */
    polyveck_add(par, &t1, &t1, &s2);

    /* Extract t1 and write public key */
    polyveck_caddq(par, &t1);
    polyveck_power2round(par, &t1, &t0, &t1);
    TAP(6);
    pack_pk(par, pk, rho, &t1);
    TAP(7);

    /* Compute H(rho, t1) and write secret key */
    shake256(tr, MLDSA_TR_SZ, pk, par->pk_sz);
    TAP(8);
    pack_sk(par, sk, rho, tr, key, &t0, &s1, &s2);
    TAP(9);

    return 0;
}

//  Deterministic algorithm to generate a signature for a formatted message M'

/*  benchmark instrumentation: rejection-loop iterations of the last
    mldsa_sign_internal() call (mirrors keccak.c's KeccakF1600_count). */
int64_t mldsa_sign_iters = 0;

int mldsa_sign_internal(const mldsa_param_t *par, uint8_t *sig, size_t *sig_sz,
                        const uint8_t *sk, const uint8_t *m, size_t m_sz,
                        const uint8_t *rnd)
{
    unsigned int n;
    uint8_t seedbuf[2 * MLDSA_SEED_SZ + MLDSA_TR_SZ + MLDSA_RND_SZ +
                    2 * MLDSA_CRH_SZ];
    uint8_t *rho, *tr, *key, *mu, *rhop, *rndp;
    uint16_t nonce = 0;
    pvecl_t mat[MLDSA_MAX_PAR_K], s1, y, z;
    pveck_t t0, s2, w1, w0, h;
    poly_t cp;
    keccak_state state;

    rho = seedbuf;
    tr = rho + MLDSA_SEED_SZ;
    key = tr + MLDSA_TR_SZ;
    rndp = key + MLDSA_SEED_SZ;
    mu = rndp + MLDSA_RND_SZ;
    rhop = mu + MLDSA_CRH_SZ;
    unpack_sk(par, rho, tr, key, &t0, &s1, &s2, sk);

    /* Compute mu = CRH(tr, 0, ctxlen, ctx, msg) */
    shake256_init(&state);
    shake256_absorb(&state, tr, MLDSA_TR_SZ);
    shake256_absorb(&state, m, m_sz);
    shake256_finalize(&state);
    shake256_squeeze(mu, MLDSA_CRH_SZ, &state);

    memcpy(rndp, rnd, MLDSA_RND_SZ);

    shake256(rhop, MLDSA_CRH_SZ, key,
             MLDSA_SEED_SZ + MLDSA_RND_SZ + MLDSA_CRH_SZ);

    /* Expand matrix and transform vectors */
    polyvec_matrix_expand(par, mat, rho);
    polyvecl_ntt(par, &s1);
    polyveck_ntt(par, &s2);
    polyveck_ntt(par, &t0);
    DBG_VECL("s1.ntt", &s1);
    DBG_VECK("s2.ntt", &s2);
    DBG_VECK("t0.ntt", &t0);

rej:
    /* Sample intermediate vector y */
    polyvecl_uniform_gamma1(par, &y, rhop, nonce++);
    DBG_VECL("y", &y);

    /* Matrix-vector multiplication */
    z = y;
    polyvecl_ntt(par, &z);
    DBG_VECL("z.ntt", &z);
    polyvec_matrix_pointwise_montgomery(par, &w1, mat, &z);
    DBG_VECK("w1.pwise", &w1);
    polyveck_reduce(par, &w1);
    DBG_VECK("w1.in", &w1);            /* exact inverse-NTT input (matches Spike) */
    DBG_VECK_RAW("w1.in", &w1);        /* raw coeffs to seed the repro */
    polyveck_invntt_tomont(par, &w1);
    DBG_VECK("w1.invntt", &w1);

    /* Decompose w and call the random oracle */
    polyveck_caddq(par, &w1);
    polyveck_decompose(par, &w1, &w0, &w1);
    DBG_VECK("w0.dec", &w0);
    DBG_VECK("w1.hi", &w1);
    polyveck_pack_w1(par, sig, &w1);

    shake256_init(&state);
    shake256_absorb(&state, mu, MLDSA_CRH_SZ);
    shake256_absorb(&state, sig, par->k * par->w1p_sz);
    shake256_finalize(&state);
    shake256_squeeze(sig, par->cp_sz, &state);
    poly_challenge(par, &cp, sig);
    mldsa_poly_ntt(&cp);
    DBG_POLY("cp.ntt", &cp);

    /* Compute z, reject if it reveals secret */
    polyvecl_pointwise_poly_montgomery(par, &z, &cp, &s1);
    polyvecl_invntt_tomont(par, &z);
    polyvecl_add(par, &z, &z, &y);
    polyvecl_reduce(par, &z);
    DBG_VECL("z.final", &z);
    DBG_VAL("rej.z", polyvecl_chknorm(par, &z, par->gamma1 - par->beta));
    if (polyvecl_chknorm(par, &z, par->gamma1 - par->beta))
        goto rej;

    /* Check that subtracting cs2 does not change high bits of w and low bits
     * do not reveal secret information */
    polyveck_pointwise_poly_montgomery(par, &h, &cp, &s2);
    polyveck_invntt_tomont(par, &h);
    polyveck_sub(par, &w0, &w0, &h);
    polyveck_reduce(par, &w0);
    DBG_VECK("w0.final", &w0);
    DBG_VAL("rej.w0", polyveck_chknorm(par, &w0, par->gamma2 - par->beta));
    if (polyveck_chknorm(par, &w0, par->gamma2 - par->beta))
        goto rej;

    /* Compute hints for w1 */
    polyveck_pointwise_poly_montgomery(par, &h, &cp, &t0);
    polyveck_invntt_tomont(par, &h);
    polyveck_reduce(par, &h);
    DBG_VECK("h.ct0", &h);
    DBG_VAL("rej.h", polyveck_chknorm(par, &h, par->gamma2));
    if (polyveck_chknorm(par, &h, par->gamma2))
        goto rej;

    polyveck_add(par, &w0, &w0, &h);
    n = polyveck_make_hint(par, &h, &w0, &w1);
    DBG_VAL("n.hint", n);
    if (n > par->omega)
        goto rej;

    /* Write signature */
    mldsa_sign_iters = nonce;       /* iterations taken (1 = first-try success) */
    pack_sig(par, sig, sig, &z, &h);
    *sig_sz = par->sig_sz;
    return 0;
}

//  Internal function to verify a signature sigma for a formatted message M'

int mldsa_verify_internal(const mldsa_param_t *par, const uint8_t *pk,
                          const uint8_t *m, size_t m_sz, const uint8_t *sig,
                          size_t sig_sz)
{
    unsigned int i;
    uint8_t buf[MLDSA_MAX_PAR_K * MLDSA_MAX_W1P_SZ];
    uint8_t rho[MLDSA_SEED_SZ];
    uint8_t mu[MLDSA_CRH_SZ];
    uint8_t c[MLDSA_MAX_CP_SZ];
    uint8_t c2[MLDSA_MAX_CP_SZ];
    poly_t cp;
    pvecl_t mat[MLDSA_MAX_PAR_K], z;
    pveck_t t1, w1, h;
    keccak_state state;

    if (sig_sz != par->sig_sz) {
        return 0;
    }

    unpack_pk(par, rho, &t1, pk);
    if (unpack_sig(par, c, &z, &h, sig)) {
        return 0;
    }
    if (polyvecl_chknorm(par, &z, par->gamma1 - par->beta)) {
        return 0;
    }

    /* Compute CRH(H(rho, t1), msg) */
    shake256(mu, MLDSA_TR_SZ, pk, par->pk_sz);
    shake256_init(&state);
    shake256_absorb(&state, mu, MLDSA_TR_SZ);
    shake256_absorb(&state, m, m_sz);
    shake256_finalize(&state);
    shake256_squeeze(mu, MLDSA_CRH_SZ, &state);

    /* Matrix-vector multiplication; compute Az - c2^dt1 */
    poly_challenge(par, &cp, c);
    polyvec_matrix_expand(par, mat, rho);

    polyvecl_ntt(par, &z);
    polyvec_matrix_pointwise_montgomery(par, &w1, mat, &z);

    mldsa_poly_ntt(&cp);
    polyveck_shiftl(par, &t1);
    polyveck_ntt(par, &t1);
    polyveck_pointwise_poly_montgomery(par, &t1, &cp, &t1);

    polyveck_sub(par, &w1, &w1, &t1);
    polyveck_reduce(par, &w1);
    polyveck_invntt_tomont(par, &w1);

    /* Reconstruct w1 */
    polyveck_caddq(par, &w1);
    polyveck_use_hint(par, &w1, &w1, &h);
    polyveck_pack_w1(par, buf, &w1);

    /* Call random oracle and verify challenge */
    shake256_init(&state);
    shake256_absorb(&state, mu, MLDSA_CRH_SZ);
    shake256_absorb(&state, buf, par->k * par->w1p_sz);
    shake256_finalize(&state);
    shake256_squeeze(c2, par->cp_sz, &state);
    for (i = 0; i < par->cp_sz; i++) {
        if (c[i] != c2[i]) {
            return 0;
        }
    }

    return 1;
}
